"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const CORPUS_SCHEMA_VERSION = 1;
const OUTPUT_SCHEMA_VERSION = 3;
const LEGACY_JOURNAL_VERSION = 1;
const JOURNAL_VERSION = 2;
const NORMALIZATION_CONTRACT_VERSION = "blind-display-v1";
const SCRIPT_CONVERTER = "Foundation Traditional-Simplified";
const TARGET_LANGUAGE = "zh-Hans-CN";
const TOTAL_CASES = 40;
const TOTAL_WORKS = 10;
const CASES_PER_WORK = 4;
const CASES_PER_CATEGORY = 10;
const MIN_SENTENCES = 2;
const MAX_SENTENCES = 4;
const MAX_SOURCE_CHARACTERS = 2_000;
const MAX_MARGIN_LOOKUP_ATTEMPTS = 40;
const MAX_HTTP_REQUESTS_PER_ATTEMPT = 2;
const MAX_HTTP_REQUESTS = MAX_MARGIN_LOOKUP_ATTEMPTS * MAX_HTTP_REQUESTS_PER_ATTEMPT;
const REQUIRED_PRIVATE_CASES = 12;
const REQUIRED_PUBLIC_DOMAIN_CASES = 28;

const CATEGORIES = Object.freeze([
  "biography-history",
  "fiction-dialogue",
  "news-general-nonfiction",
  "idiom-ambiguity-complex-syntax",
]);
const CATEGORY_SET = new Set(CATEGORIES);
const REASON_CODES = new Set(["network", "provider", "capture", "cancelled", "other"]);
const IDENTIFIER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const APPLE_IMPORT_SCHEMA_VERSION = 1;

class PreparationError extends Error {
  constructor(message) {
    super(message);
    this.name = "PreparationError";
  }
}

function fail(message) {
  throw new PreparationError(message);
}

function isPlainObject(value) {
  return value !== null
    && typeof value === "object"
    && !Array.isArray(value)
    && Object.getPrototypeOf(value) === Object.prototype;
}

function requireObject(value, field) {
  if (!isPlainObject(value)) fail(`${field} must be an object.`);
  return value;
}

function requireString(value, field, { allowEmpty = false } = {}) {
  if (typeof value !== "string" || (!allowEmpty && value.trim() === "")) {
    fail(`${field} must be ${allowEmpty ? "a string" : "a non-empty string"}.`);
  }
  return value;
}

function requireIdentifier(value, field) {
  const identifier = requireString(value, field);
  if (!IDENTIFIER_PATTERN.test(identifier)) {
    fail(`${field} must be a portable identifier using letters, digits, dots, underscores, or hyphens.`);
  }
  return identifier;
}

function requireInteger(value, field, minimum = 0) {
  if (!Number.isInteger(value) || value < minimum) {
    fail(`${field} must be an integer of at least ${minimum}.`);
  }
  return value;
}

function normalizeCandidateText(value, field) {
  return requireString(value, field).normalize("NFC").trim();
}

function requireChineseCandidate(value, field) {
  const text = normalizeCandidateText(value, field);
  const hanCount = (text.match(/\p{Script=Han}/gu) || []).length;
  const letterCount = (text.match(/\p{L}/gu) || []).length;
  if (hanCount < 2 || (letterCount > 0 && hanCount / letterCount < 0.15)) {
    fail(`${field} must contain a substantive Chinese translation.`);
  }
  return text;
}

function stripAppleBooksFooter(value) {
  const text = normalizeCandidateText(value, "Apple candidate text");
  const footer = /\n{2,}摘录来自\n{2,}[\s\S]+?\n{2,}此内容可能受版权保护。?\s*$/u;
  if (!footer.test(text)) return { text, stripped: false };
  return { text: text.replace(footer, "").trim(), stripped: true };
}

function validateAppleCandidate(value) {
  const cleaned = stripAppleBooksFooter(value);
  if (/摘录来自|此内容可能受版权保护/u.test(cleaned.text)) {
    fail("Apple candidate contains an unrecognized Books interface footer.");
  }
  if (/(?:\.{3}|…)\s*[”’"']?$/u.test(cleaned.text)) {
    fail("Apple candidate shows a possible truncation marker.");
  }
  return {
    text: requireChineseCandidate(cleaned.text, "Apple candidate text"),
    strippedFooter: cleaned.stripped,
  };
}

function normalizeDisplayWhitespace(value, field = "candidate text") {
  return requireString(value, field).normalize("NFC").trim().replace(/\s+/gu, " ");
}

function canonicalizePairedASCIIQuotes(value, quote, opening, closing, {
  preserveWordApostrophes = false,
} = {}) {
  const characters = [...value];
  const positions = [];
  for (let index = 0; index < characters.length; index += 1) {
    if (characters[index] !== quote) continue;
    if (preserveWordApostrophes) {
      const previous = characters[index - 1] || "";
      const next = characters[index + 1] || "";
      if (/[\p{L}\p{N}]/u.test(previous) && /[\p{L}\p{N}]/u.test(next)) continue;
    }
    positions.push(index);
  }
  if (positions.length === 0 || positions.length % 2 !== 0) return value;
  positions.forEach((position, index) => {
    characters[position] = index % 2 === 0 ? opening : closing;
  });
  return characters.join("");
}

function canonicalizeQuoteGlyphs(value) {
  let output = value
    .replaceAll("「", "“")
    .replaceAll("」", "”")
    .replaceAll("『", "‘")
    .replaceAll("』", "’")
    .replaceAll("﹁", "“")
    .replaceAll("﹂", "”")
    .replaceAll("﹃", "‘")
    .replaceAll("﹄", "’");
  output = canonicalizePairedASCIIQuotes(output, '"', "“", "”");
  output = canonicalizePairedASCIIQuotes(
    output,
    "'",
    "‘",
    "’",
    { preserveWordApostrophes: true },
  );
  return output;
}

const WHOLE_TEXT_QUOTE_PAIRS = Object.freeze([
  ['"', '"'],
  ["'", "'"],
  ["“", "”"],
  ["‘", "’"],
  ["「", "」"],
  ["『", "』"],
  ["﹁", "﹂"],
  ["﹃", "﹄"],
]);

function wholeTextQuotePair(value) {
  const text = value.trim();
  return WHOLE_TEXT_QUOTE_PAIRS.find(
    ([opening, closing]) => text.startsWith(opening) && text.endsWith(closing)
      && text.length > opening.length + closing.length,
  ) || null;
}

function stripOneWholeTextQuote(value) {
  const pair = wholeTextQuotePair(value);
  if (!pair) return { text: value, stripped: false };
  const [opening, closing] = pair;
  return {
    text: value.slice(opening.length, value.length - closing.length).trim(),
    stripped: true,
  };
}

function applySourceControlledOuterQuote(sourceText, candidateText) {
  const sourceIsWrapped = Boolean(wholeTextQuotePair(normalizeDisplayWhitespace(
    sourceText,
    "source text",
  )));
  const stripped = stripOneWholeTextQuote(candidateText);
  const text = sourceIsWrapped ? `“${stripped.text}”` : stripped.text;
  return { text, adjusted: text !== candidateText };
}

function convertTraditionalToSimplifiedBatch(values) {
  if (!Array.isArray(values) || values.some((value) => typeof value !== "string")) {
    fail("Script conversion requires an array of strings.");
  }
  const cacheRoot = path.join(os.tmpdir(), "margin-evaluation-swift-cache");
  fs.mkdirSync(cacheRoot, { recursive: true, mode: 0o700 });
  const helperPath = path.join(__dirname, "traditional-to-simplified.swift");
  const result = spawnSync("/usr/bin/swift", [helperPath], {
    input: JSON.stringify(values),
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
    env: {
      ...process.env,
      CLANG_MODULE_CACHE_PATH: path.join(cacheRoot, "clang"),
      SWIFT_MODULE_CACHE_PATH: path.join(cacheRoot, "swift"),
    },
  });
  if (result.error || result.status !== 0) {
    fail("The local Simplified Chinese converter could not be run.");
  }
  let converted;
  try {
    converted = JSON.parse(result.stdout);
  } catch (_error) {
    fail("The local Simplified Chinese converter returned an unreadable result.");
  }
  if (!Array.isArray(converted)
    || converted.length !== values.length
    || converted.some((value) => typeof value !== "string")) {
    fail("The local Simplified Chinese converter returned an invalid result.");
  }
  return converted;
}

function normalizeBlindCandidate(sourceText, rawText, simplifiedText) {
  const raw = normalizeCandidateText(rawText, "raw candidate text");
  const whitespace = normalizeDisplayWhitespace(raw, "raw candidate text");
  const simplified = requireString(
    simplifiedText,
    "Simplified candidate text",
  ).normalize("NFC");
  const quotes = canonicalizeQuoteGlyphs(simplified);
  const outer = applySourceControlledOuterQuote(sourceText, quotes);
  const displayText = requireChineseCandidate(outer.text, "blind display candidate text");
  return {
    rawText: raw,
    displayText,
    normalization: {
      whitespaceAdjusted: whitespace !== raw,
      scriptConverted: simplified !== whitespace,
      quoteGlyphsAdjusted: quotes !== simplified,
      outerQuoteAdjusted: outer.adjusted,
    },
  };
}

function normalizeBlindCandidates(validated, journal, converter = convertTraditionalToSimplifiedBatch) {
  const inputs = validated.items.flatMap((item) => {
    const candidates = journal.attempts[item.id].candidates;
    return ["apple", "deepseek"].map((provider) => normalizeDisplayWhitespace(
      candidates[provider].text,
      `${provider} candidate text`,
    ));
  });
  const simplified = converter(inputs);
  if (!Array.isArray(simplified)
    || simplified.length !== inputs.length
    || simplified.some((value) => typeof value !== "string")) {
    fail("The Simplified Chinese converter returned an invalid batch.");
  }
  const cases = validated.items.map((item, itemIndex) => {
    const raw = journal.attempts[item.id].candidates;
    return {
      apple: normalizeBlindCandidate(item.text, raw.apple.text, simplified[itemIndex * 2]),
      deepseek: normalizeBlindCandidate(
        item.text,
        raw.deepseek.text,
        simplified[itemIndex * 2 + 1],
      ),
    };
  });
  const displayTexts = cases.flatMap((candidates) => [
    candidates.apple.displayText,
    candidates.deepseek.displayText,
  ]);
  const reconverted = converter(displayTexts);
  if (!Array.isArray(reconverted)
    || reconverted.length !== displayTexts.length
    || reconverted.some((value, index) => value !== displayTexts[index])) {
    fail("Blind display normalization is not idempotent.");
  }
  cases.forEach((candidates, index) => {
    for (const provider of ["apple", "deepseek"]) {
      const repeated = normalizeBlindCandidate(
        validated.items[index].text,
        candidates[provider].displayText,
        candidates[provider].displayText,
      );
      if (repeated.displayText !== candidates[provider].displayText) {
        fail("Blind display normalization is not idempotent.");
      }
    }
  });
  return cases;
}

function assertOnlyKeys(value, allowed, field) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(`${field} contains an unsupported field.`);
  }
}

function normalizeTextIdentity(value) {
  return value.normalize("NFC").trim().replace(/\s+/gu, " ").toLocaleLowerCase("en-US");
}

function countSentences(value) {
  if (typeof Intl.Segmenter === "function") {
    const segmenter = new Intl.Segmenter("en", { granularity: "sentence" });
    return [...segmenter.segment(value)]
      .filter((segment) => /[\p{L}\p{N}]/u.test(segment.segment))
      .length;
  }
  return value
    .split(/(?<=[.!?])[\s”’"')\]]+/u)
    .filter((segment) => /[\p{L}\p{N}]/u.test(segment))
    .length;
}

function validateAttribution(input, field) {
  const attribution = requireObject(input, field);
  assertOnlyKeys(
    attribution,
    new Set(["title", "creator", "sourceURL", "license", "firstPublished"]),
    field,
  );
  const normalized = {
    title: requireString(attribution.title, `${field}.title`).trim(),
    creator: requireString(attribution.creator, `${field}.creator`).trim(),
    sourceURL: requireString(
      attribution.sourceURL,
      `${field}.sourceURL`,
      { allowEmpty: true },
    ).trim(),
    license: requireString(attribution.license, `${field}.license`).trim(),
  };
  if (normalized.sourceURL !== "") {
    let parsedURL;
    try {
      parsedURL = new URL(normalized.sourceURL);
    } catch (_error) {
      fail(`${field}.sourceURL must be empty or an absolute URL.`);
    }
    if (parsedURL.protocol !== "https:" && parsedURL.protocol !== "http:") {
      fail(`${field}.sourceURL must use HTTP or HTTPS when present.`);
    }
  }
  if (Object.hasOwn(attribution, "firstPublished")) {
    normalized.firstPublished = requireInteger(
      attribution.firstPublished,
      `${field}.firstPublished`,
      1,
    );
  }
  return normalized;
}

function validateCorpusDocument(input, documentIndex) {
  const root = requireObject(input, `corpora[${documentIndex}]`);
  assertOnlyKeys(root, new Set(["schemaVersion", "corpus"]), `corpora[${documentIndex}]`);
  if (root.schemaVersion !== CORPUS_SCHEMA_VERSION) {
    fail(`corpora[${documentIndex}].schemaVersion must be ${CORPUS_SCHEMA_VERSION}.`);
  }
  const corpus = requireObject(root.corpus, `corpora[${documentIndex}].corpus`);
  assertOnlyKeys(
    corpus,
    new Set(["id", "title", "purpose", "items"]),
    `corpora[${documentIndex}].corpus`,
  );
  if (!Array.isArray(corpus.items)) {
    fail(`corpora[${documentIndex}].corpus.items must be an array.`);
  }
  return {
    id: requireIdentifier(corpus.id, `corpora[${documentIndex}].corpus.id`),
    title: requireString(corpus.title, `corpora[${documentIndex}].corpus.title`).trim(),
    purpose: requireString(corpus.purpose, `corpora[${documentIndex}].corpus.purpose`).trim(),
    items: corpus.items.map((inputItem, itemIndex) => {
      const field = `corpora[${documentIndex}].corpus.items[${itemIndex}]`;
      const item = requireObject(inputItem, field);
      if (Object.hasOwn(item, "candidates")) fail(`${field} must be source-only.`);
      assertOnlyKeys(
        item,
        new Set(["id", "workId", "category", "text", "chapter", "attribution"]),
        field,
      );
      const id = requireIdentifier(item.id, `${field}.id`);
      const workId = requireIdentifier(item.workId, `${field}.workId`);
      const category = requireString(item.category, `${field}.category`).trim();
      if (!CATEGORY_SET.has(category)) {
        fail(`${field}.category must use one of the four standard evaluation categories.`);
      }
      const text = requireString(item.text, `${field}.text`).normalize("NFC").trim();
      const characterCount = [...text].length;
      if (characterCount > MAX_SOURCE_CHARACTERS) {
        fail(`${field}.text must contain at most ${MAX_SOURCE_CHARACTERS} characters.`);
      }
      const sentenceCount = countSentences(text);
      if (sentenceCount < MIN_SENTENCES || sentenceCount > MAX_SENTENCES) {
        fail(`${field}.text must contain between ${MIN_SENTENCES} and ${MAX_SENTENCES} sentences.`);
      }
      const normalized = {
        id,
        workId,
        category,
        text,
        attribution: validateAttribution(item.attribution, `${field}.attribution`),
      };
      if (Object.hasOwn(item, "chapter")) {
        if (typeof item.chapter !== "string" && !Number.isInteger(item.chapter)) {
          fail(`${field}.chapter must be a string or integer when present.`);
        }
        if (typeof item.chapter === "string" && item.chapter.trim() === "") {
          fail(`${field}.chapter must not be empty.`);
        }
        normalized.chapter = typeof item.chapter === "string" ? item.chapter.trim() : item.chapter;
      }
      return normalized;
    }),
  };
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (isPlainObject(value)) {
    const result = {};
    for (const key of Object.keys(value).sort()) result[key] = canonicalize(value[key]);
    return result;
  }
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  fail("Canonical JSON contains an unsupported value.");
}

function canonicalJSONString(value) {
  return JSON.stringify(canonicalize(value));
}

function canonicalSHA256(value) {
  return `sha256:${crypto.createHash("sha256").update(canonicalJSONString(value), "utf8").digest("hex")}`;
}

function validateSourceCorpora(inputs) {
  if (!Array.isArray(inputs) || inputs.length === 0) fail("At least one source corpus is required.");
  const corpora = inputs.map(validateCorpusDocument);
  const corpusIDs = new Set();
  const caseIDs = new Set();
  const textIdentities = new Set();
  const workItems = new Map();
  const workAttributions = new Map();
  const categoryCounts = Object.fromEntries(CATEGORIES.map((category) => [category, 0]));

  for (const corpus of corpora) {
    if (corpusIDs.has(corpus.id)) fail("Corpus IDs must be unique across combined inputs.");
    corpusIDs.add(corpus.id);
    for (const item of corpus.items) {
      if (caseIDs.has(item.id)) fail("Evaluation case IDs must be unique across combined inputs.");
      caseIDs.add(item.id);
      const textIdentity = normalizeTextIdentity(item.text);
      if (textIdentities.has(textIdentity)) fail("Evaluation source texts must be unique.");
      textIdentities.add(textIdentity);
      categoryCounts[item.category] += 1;
      const workList = workItems.get(item.workId) || [];
      workList.push(item.id);
      workItems.set(item.workId, workList);
      const attributionIdentity = canonicalJSONString(item.attribution);
      if (workAttributions.has(item.workId)
        && workAttributions.get(item.workId) !== attributionIdentity) {
        fail("Every case sharing a workId must use identical attribution metadata.");
      }
      workAttributions.set(item.workId, attributionIdentity);
    }
  }

  const items = corpora.flatMap((corpus) => corpus.items).sort((left, right) => left.id.localeCompare(right.id));
  if (items.length !== TOTAL_CASES) fail(`Combined corpora must contain exactly ${TOTAL_CASES} cases.`);
  if (workItems.size !== TOTAL_WORKS) fail(`Combined corpora must contain exactly ${TOTAL_WORKS} works.`);
  for (const ids of workItems.values()) {
    if (ids.length !== CASES_PER_WORK) {
      fail(`Every work must contribute exactly ${CASES_PER_WORK} cases.`);
    }
  }
  for (const category of CATEGORIES) {
    if (categoryCounts[category] !== CASES_PER_CATEGORY) {
      fail(`Every category must contain exactly ${CASES_PER_CATEGORY} cases.`);
    }
  }

  const canonicalCorpus = {
    schemaVersion: CORPUS_SCHEMA_VERSION,
    corpora: corpora
      .map((corpus) => ({
        id: corpus.id,
        title: corpus.title,
        purpose: corpus.purpose,
        items: [...corpus.items].sort((left, right) => left.id.localeCompare(right.id)),
      }))
      .sort((left, right) => left.id.localeCompare(right.id)),
  };

  return {
    corpora,
    items,
    categoryCounts,
    workCount: workItems.size,
    canonicalCorpus,
    corpusHash: canonicalSHA256(canonicalCorpus),
  };
}

function readJSONFile(inputPath) {
  let contents;
  try {
    contents = fs.readFileSync(inputPath, "utf8");
  } catch (_error) {
    fail("Could not read a JSON input file.");
  }
  try {
    return JSON.parse(contents);
  } catch (_error) {
    fail("Could not parse a JSON input file.");
  }
}

function loadAndValidateCorpora(inputPaths) {
  if (!Array.isArray(inputPaths) || inputPaths.length === 0) {
    fail("At least one --corpus input path is required.");
  }
  return validateSourceCorpora(inputPaths.map(readJSONFile));
}

function decodeXMLText(value) {
  return value
    .replace(/&#x([0-9a-f]+);/giu, (_match, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&#([0-9]+);/gu, (_match, code) => String.fromCodePoint(Number.parseInt(code, 10)))
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'")
    .replaceAll("&amp;", "&");
}

function readZipEntry(archivePath, entryPath, { optional = false } = {}) {
  const result = spawnSync("unzip", ["-p", archivePath, entryPath], {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    if (optional) return "";
    fail("Could not read the controlled Apple translation workbook.");
  }
  return result.stdout;
}

function xmlAttribute(attributes, name) {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
  const match = new RegExp(`(?:^|\\s)${escapedName}="([^"]*)"`, "u").exec(attributes);
  return match ? decodeXMLText(match[1]) : "";
}

function inlineXMLText(fragment) {
  return [...fragment.matchAll(/<(?:\w+:)?t\b[^>]*>([\s\S]*?)<\/(?:\w+:)?t>/gu)]
    .map((match) => decodeXMLText(match[1]))
    .join("");
}

function extractAppleImportFromXlsx(inputPath, caseOrder) {
  const workbookPath = path.resolve(requireString(inputPath, "Apple workbook path"));
  if (!fs.existsSync(workbookPath)) fail("Could not read the Apple translation workbook.");
  if (!Array.isArray(caseOrder) || caseOrder.length !== TOTAL_CASES) {
    fail(`Apple workbook extraction requires exactly ${TOTAL_CASES} case IDs.`);
  }

  const workbookXML = readZipEntry(workbookPath, "xl/workbook.xml");
  const sheetMatch = [...workbookXML.matchAll(/<(?:\w+:)?sheet\b([^>]*)\/?>/gu)]
    .find((match) => xmlAttribute(match[1], "name") === "Apple 译文");
  if (!sheetMatch) fail("Apple workbook is missing the expected translation sheet.");
  const relationshipID = xmlAttribute(sheetMatch[1], "r:id");
  const relationshipsXML = readZipEntry(workbookPath, "xl/_rels/workbook.xml.rels");
  const relationshipMatch = [
    ...relationshipsXML.matchAll(/<(?:\w+:)?Relationship\b([^>]*)\/?>/gu),
  ]
    .find((match) => xmlAttribute(match[1], "Id") === relationshipID);
  if (!relationshipMatch) fail("Apple workbook has an invalid translation sheet relationship.");
  const target = xmlAttribute(relationshipMatch[1], "Target").replace(/^\/?xl\//u, "");
  const sheetXML = readZipEntry(workbookPath, `xl/${target}`);

  const sharedStringsXML = readZipEntry(
    workbookPath,
    "xl/sharedStrings.xml",
    { optional: true },
  );
  const sharedStrings = [
    ...sharedStringsXML.matchAll(
      /<(?:\w+:)?si\b[^>]*>([\s\S]*?)<\/(?:\w+:)?si>/gu,
    ),
  ]
    .map((match) => inlineXMLText(match[1]));
  const cells = new Map();
  for (const match of sheetXML.matchAll(
    /<(?:\w+:)?c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:\w+:)?c>)/gu,
  )) {
    const reference = xmlAttribute(match[1], "r");
    if (!reference) continue;
    const type = xmlAttribute(match[1], "t");
    const body = match[2] || "";
    let value = "";
    if (type === "inlineStr") {
      value = inlineXMLText(body);
    } else {
      const valueMatch = /<(?:\w+:)?v\b[^>]*>([\s\S]*?)<\/(?:\w+:)?v>/u.exec(body);
      const rawValue = valueMatch ? decodeXMLText(valueMatch[1]) : "";
      if (type === "s") {
        const index = Number.parseInt(rawValue, 10);
        value = Number.isInteger(index) && sharedStrings[index] !== undefined
          ? sharedStrings[index]
          : "";
      } else {
        value = rawValue;
      }
    }
    cells.set(reference, value);
  }

  const rows = caseOrder.map((caseID, index) => {
    const rowNumber = index + 6;
    const caseNumber = Number.parseInt(cells.get(`A${rowNumber}`) || "", 10);
    const workbookCaseID = (cells.get(`B${rowNumber}`) || "").trim();
    if (caseNumber !== index + 1 || workbookCaseID !== caseID) {
      fail("Apple workbook Case and Case ID columns must remain unchanged and in order.");
    }
    return {
      case: index + 1,
      caseID,
      appleTranslation: cells.get(`D${rowNumber}`) || "",
      note: cells.get(`F${rowNumber}`) || "",
    };
  });
  return {
    schemaVersion: APPLE_IMPORT_SCHEMA_VERSION,
    rows,
  };
}

function escapeXML(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function writeTextFile(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, contents, { encoding: "utf8", mode: 0o600 });
}

function createEpub(validated, outputPath, modifiedAt = new Date().toISOString()) {
  if (!validated || !Array.isArray(validated.items) || validated.items.length !== TOTAL_CASES) {
    fail("A validated 40-case corpus is required to create an EPUB.");
  }
  const destination = path.resolve(requireString(outputPath, "EPUB output path"));
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "margin-evaluation-epub-"));
  const archivePath = path.join(
    path.dirname(destination),
    `.${path.basename(destination)}.${process.pid}.${crypto.randomBytes(6).toString("hex")}.tmp`,
  );
  try {
    writeTextFile(path.join(temporaryRoot, "mimetype"), "application/epub+zip");
    writeTextFile(
      path.join(temporaryRoot, "META-INF", "container.xml"),
      `<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
`,
    );

    const manifest = [];
    const spine = [];
    const navigation = [];
    validated.items.forEach((item, index) => {
      const number = String(index + 1).padStart(3, "0");
      const fileName = `chapter-${number}.xhtml`;
      manifest.push(`    <item id="chapter-${number}" href="chapters/${fileName}" media-type="application/xhtml+xml"/>`);
      spine.push(`    <itemref idref="chapter-${number}"/>`);
      navigation.push(`      <li><a href="chapters/${fileName}">Case ${index + 1}</a></li>`);
      writeTextFile(
        path.join(temporaryRoot, "OEBPS", "chapters", fileName),
        `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head><meta charset="utf-8"/><title>Case ${index + 1}</title></head>
<body><main><h1>Case ${index + 1}</h1><p>${escapeXML(item.text)}</p></main></body>
</html>
`,
      );
    });

    writeTextFile(
      path.join(temporaryRoot, "OEBPS", "nav.xhtml"),
      `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
<head><meta charset="utf-8"/><title>Contents</title></head>
<body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol>
${navigation.join("\n")}
    </ol></nav></body>
</html>
`,
    );
    writeTextFile(
      path.join(temporaryRoot, "OEBPS", "package.opf"),
      `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="publication-id" xml:lang="en">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/">
    <dc:identifier id="publication-id">urn:sha256:${validated.corpusHash.slice("sha256:".length)}</dc:identifier>
    <dc:title>Evaluation Reading Corpus</dc:title>
    <dc:language>en</dc:language>
    <dcterms:modified>${escapeXML(modifiedAt.replace(/\.\d{3}Z$/, "Z"))}</dcterms:modified>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
${manifest.join("\n")}
  </manifest>
  <spine>
${spine.join("\n")}
  </spine>
</package>
`,
    );

    const first = spawnSync("zip", ["-X0q", archivePath, "mimetype"], {
      cwd: temporaryRoot,
      encoding: "utf8",
    });
    if (first.error || first.status !== 0) fail("Could not create the EPUB archive with the system zip tool.");
    const remainder = spawnSync("zip", ["-X9qr", archivePath, "META-INF", "OEBPS"], {
      cwd: temporaryRoot,
      encoding: "utf8",
    });
    if (remainder.error || remainder.status !== 0) {
      fail("Could not finish the EPUB archive with the system zip tool.");
    }
    fs.renameSync(archivePath, destination);
    fs.chmodSync(destination, 0o600);
    return destination;
  } catch (error) {
    try { fs.rmSync(archivePath, { force: true }); } catch (_cleanupError) {}
    if (error instanceof PreparationError) throw error;
    fail("Could not write the EPUB output.");
  } finally {
    try { fs.rmSync(temporaryRoot, { recursive: true, force: true }); } catch (_cleanupError) {}
  }
}

function atomicWriteJSON(outputPath, value) {
  const destination = path.resolve(requireString(outputPath, "JSON output path"));
  const directory = path.dirname(destination);
  fs.mkdirSync(directory, { recursive: true });
  const temporary = path.join(
    directory,
    `.${path.basename(destination)}.${process.pid}.${crypto.randomBytes(6).toString("hex")}.tmp`,
  );
  let descriptor;
  try {
    descriptor = fs.openSync(temporary, "wx", 0o600);
    fs.writeFileSync(descriptor, `${JSON.stringify(value, null, 2)}\n`, "utf8");
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
    fs.renameSync(temporary, destination);
    fs.chmodSync(destination, 0o600);
    try {
      const directoryDescriptor = fs.openSync(directory, "r");
      try { fs.fsyncSync(directoryDescriptor); } finally { fs.closeSync(directoryDescriptor); }
    } catch (_error) {}
    return destination;
  } catch (_error) {
    if (descriptor !== undefined) {
      try { fs.closeSync(descriptor); } catch (_closeError) {}
    }
    try { fs.rmSync(temporary, { force: true }); } catch (_cleanupError) {}
    fail("Could not atomically write private JSON output.");
  }
}

function atomicBackupPrivateJSON(inputPath, label, now = new Date().toISOString()) {
  const sourcePath = path.resolve(requireString(inputPath, "private JSON path"));
  const safeLabel = requireIdentifier(label, "backup label");
  let contents;
  try {
    contents = fs.readFileSync(sourcePath);
  } catch (_error) {
    fail("Could not read the private JSON file before backup.");
  }
  const timestamp = now.replace(/[^0-9]/gu, "").slice(0, 14);
  const baseName = path.basename(sourcePath).replace(/(?:\.private)?\.json$/u, "");
  const backupPath = path.join(
    path.dirname(sourcePath),
    `${baseName}.${safeLabel}-${timestamp}.private.json`,
  );
  const temporaryPath = `${backupPath}.${process.pid}.${crypto.randomBytes(6).toString("hex")}.tmp`;
  try {
    const descriptor = fs.openSync(temporaryPath, "wx", 0o600);
    try {
      fs.writeFileSync(descriptor, contents);
      fs.fsyncSync(descriptor);
    } finally {
      fs.closeSync(descriptor);
    }
    fs.renameSync(temporaryPath, backupPath);
    fs.chmodSync(backupPath, 0o600);
  } catch (_error) {
    try { fs.unlinkSync(temporaryPath); } catch (_cleanupError) {}
    fail("Could not create the private JSON backup.");
  }
  return backupPath;
}

function journalLimits() {
  return {
    maxMarginLookupAttempts: MAX_MARGIN_LOOKUP_ATTEMPTS,
    maxHttpRequests: MAX_HTTP_REQUESTS,
    maxHttpRequestsPerAttempt: MAX_HTTP_REQUESTS_PER_ATTEMPT,
    automaticRetries: false,
  };
}

function createJournal(corpusHash, caseIDs, now = new Date().toISOString()) {
  requireString(corpusHash, "corpusHash");
  if (!Array.isArray(caseIDs) || caseIDs.length !== TOTAL_CASES) {
    fail(`A journal requires exactly ${TOTAL_CASES} case IDs.`);
  }
  const uniqueIDs = new Set(caseIDs);
  if (uniqueIDs.size !== caseIDs.length) fail("Journal case IDs must be unique.");
  caseIDs.forEach((id, index) => requireIdentifier(id, `caseIDs[${index}]`));
  return {
    journalVersion: JOURNAL_VERSION,
    corpusHash,
    createdAt: requireString(now, "journal timestamp"),
    updatedAt: now,
    limits: journalLimits(),
    caseOrder: [...caseIDs],
    attempts: {},
    totals: {
      marginLookupAttempts: 0,
      httpRequestBudget: 0,
      httpRequests: 0,
      deepseekCollectedCases: 0,
      completeCases: 0,
      failedCases: 0,
    },
  };
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function migrateJournalDocument(input) {
  const journal = clone(requireObject(input, "journal"));
  if (journal.journalVersion === LEGACY_JOURNAL_VERSION) {
    journal.journalVersion = JOURNAL_VERSION;
    const totals = requireObject(journal.totals, "journal.totals");
    journal.totals = {
      marginLookupAttempts: totals.marginLookupAttempts,
      httpRequestBudget: totals.httpRequestBudget,
      httpRequests: totals.httpRequests,
      deepseekCollectedCases: 0,
      completeCases: totals.completeCases,
      failedCases: totals.failedCases,
    };
  }
  return journal;
}

function validateJournal(journal, expectedCorpusHash, expectedCaseIDs) {
  const value = migrateJournalDocument(journal);
  assertOnlyKeys(
    value,
    new Set([
      "journalVersion",
      "corpusHash",
      "createdAt",
      "updatedAt",
      "limits",
      "caseOrder",
      "attempts",
      "totals",
    ]),
    "journal",
  );
  if (value.journalVersion !== JOURNAL_VERSION) fail("Journal version is unsupported.");
  if (value.corpusHash !== expectedCorpusHash) fail("Journal belongs to a different corpus hash.");
  if (!Array.isArray(value.caseOrder)
    || value.caseOrder.length !== expectedCaseIDs.length
    || value.caseOrder.some((id, index) => id !== expectedCaseIDs[index])) {
    fail("Journal case order does not match the validated corpus.");
  }
  const expectedLimits = journalLimits();
  if (canonicalJSONString(value.limits) !== canonicalJSONString(expectedLimits)) {
    fail("Journal safety limits are invalid.");
  }
  const attempts = requireObject(value.attempts, "journal.attempts");
  const allowedIDs = new Set(expectedCaseIDs);
  let httpRequests = 0;
  let deepseekCollectedCases = 0;
  let completeCases = 0;
  let failedCases = 0;
  const attemptNumbers = new Set();
  for (const [caseID, attemptInput] of Object.entries(attempts)) {
    if (!allowedIDs.has(caseID)) fail("Journal contains an unknown case attempt.");
    const attempt = requireObject(attemptInput, "journal attempt");
    assertOnlyKeys(
      attempt,
      new Set([
        "status",
        "attemptNumber",
        "httpRequests",
        "startedAt",
        "deepseekCollectedAt",
        "completedAt",
        "candidates",
        "reasonCode",
      ]),
      "journal attempt",
    );
    if (!new Set(["reserved", "deepseekCollected", "complete", "failed"]).has(attempt.status)) {
      fail("Journal contains an invalid attempt status.");
    }
    const attemptNumber = requireInteger(attempt.attemptNumber, "journal attempt number", 1);
    if (attemptNumbers.has(attemptNumber)) fail("Journal attempt numbers must be unique.");
    attemptNumbers.add(attemptNumber);
    requireString(attempt.startedAt, "journal attempt start timestamp");
    const requestCount = requireInteger(attempt.httpRequests, "journal HTTP request count", 0);
    if (requestCount > MAX_HTTP_REQUESTS_PER_ATTEMPT) {
      fail("A journal attempt exceeds the HTTP request limit.");
    }
    httpRequests += requestCount;
    if (attempt.status === "complete") {
      const candidates = requireObject(attempt.candidates, "journal candidates");
      assertOnlyKeys(candidates, new Set(["apple", "deepseek"]), "journal candidates");
      for (const provider of ["apple", "deepseek"]) {
        const candidate = requireObject(candidates[provider], "journal candidate");
        assertOnlyKeys(candidate, new Set(["text"]), "journal candidate");
        requireString(candidate.text, "journal candidate text");
      }
      requireString(attempt.completedAt, "journal attempt completion timestamp");
      if (Object.hasOwn(attempt, "reasonCode")) {
        fail("A complete journal attempt must not contain a failure reason.");
      }
      completeCases += 1;
    } else if (attempt.status === "deepseekCollected") {
      const candidates = requireObject(attempt.candidates, "journal candidates");
      assertOnlyKeys(candidates, new Set(["deepseek"]), "journal candidates");
      const candidate = requireObject(candidates.deepseek, "journal candidate");
      assertOnlyKeys(candidate, new Set(["text"]), "journal candidate");
      requireChineseCandidate(candidate.text, "DeepSeek candidate text");
      requireString(attempt.deepseekCollectedAt, "DeepSeek collection timestamp");
      if (Object.hasOwn(attempt, "completedAt") || Object.hasOwn(attempt, "reasonCode")) {
        fail("A DeepSeek-collected attempt must not contain completion or failure fields.");
      }
      deepseekCollectedCases += 1;
    } else {
      if (Object.hasOwn(attempt, "candidates")) {
        fail("Only complete journal attempts may contain candidates.");
      }
      if (attempt.status === "reserved"
        && (Object.hasOwn(attempt, "deepseekCollectedAt")
          || Object.hasOwn(attempt, "completedAt")
          || Object.hasOwn(attempt, "reasonCode"))) {
        fail("A reserved journal attempt must not contain completion fields.");
      }
    }
    if (attempt.status === "failed") {
      if (!REASON_CODES.has(attempt.reasonCode)) fail("Journal failure reason code is invalid.");
      requireString(attempt.completedAt, "journal attempt failure timestamp");
      if (Object.hasOwn(attempt, "deepseekCollectedAt")) {
        fail("A failed journal attempt must not contain a DeepSeek collection timestamp.");
      }
      failedCases += 1;
    }
  }
  const marginLookupAttempts = Object.keys(attempts).length;
  if (marginLookupAttempts > MAX_MARGIN_LOOKUP_ATTEMPTS) {
    fail("Journal exceeds the Margin lookup attempt limit.");
  }
  for (let number = 1; number <= marginLookupAttempts; number += 1) {
    if (!attemptNumbers.has(number)) fail("Journal attempt numbers must form a continuous sequence.");
  }
  const httpRequestBudget = marginLookupAttempts * MAX_HTTP_REQUESTS_PER_ATTEMPT;
  if (httpRequestBudget > MAX_HTTP_REQUESTS || httpRequests > MAX_HTTP_REQUESTS) {
    fail("Journal exceeds the HTTP request limit.");
  }
  const totals = requireObject(value.totals, "journal.totals");
  const expectedTotals = {
    marginLookupAttempts,
    httpRequestBudget,
    httpRequests,
    deepseekCollectedCases,
    completeCases,
    failedCases,
  };
  if (canonicalJSONString(totals) !== canonicalJSONString(expectedTotals)) {
    fail("Journal totals do not match its attempts.");
  }
  requireString(value.createdAt, "journal.createdAt");
  requireString(value.updatedAt, "journal.updatedAt");
  return value;
}

function loadJournal(journalPath, expectedCorpusHash, expectedCaseIDs) {
  return validateJournal(readJSONFile(journalPath), expectedCorpusHash, expectedCaseIDs);
}

function initializeJournal(journalPath, validated, now = new Date().toISOString()) {
  const caseIDs = validated.items.map((item) => item.id);
  if (fs.existsSync(journalPath)) {
    const raw = readJSONFile(journalPath);
    const existing = validateJournal(raw, validated.corpusHash, caseIDs);
    if (raw.journalVersion !== existing.journalVersion) {
      atomicWriteJSON(journalPath, existing);
    }
    try { fs.chmodSync(journalPath, 0o600); } catch (_error) {}
    return clone(existing);
  }
  const journal = createJournal(validated.corpusHash, caseIDs, now);
  atomicWriteJSON(journalPath, journal);
  return journal;
}

function amendJournalForUntestedSources(
  journalPath,
  validated,
  amendedCaseIDs,
  now = new Date().toISOString(),
) {
  if (!Array.isArray(amendedCaseIDs) || amendedCaseIDs.length === 0) {
    fail("A source-only amendment requires at least one amended case ID.");
  }
  const caseIDs = validated.items.map((item) => item.id);
  const rawJournal = readJSONFile(journalPath);
  const journal = validateJournal(rawJournal, rawJournal.corpusHash, caseIDs);
  if (journal.corpusHash === validated.corpusHash) {
    fail("The amended corpus hash must differ from the journal corpus hash.");
  }

  const uniqueAmendedIDs = new Set(amendedCaseIDs);
  if (uniqueAmendedIDs.size !== amendedCaseIDs.length) {
    fail("Amended case IDs must be unique.");
  }
  for (const caseID of uniqueAmendedIDs) {
    if (!caseIDs.includes(caseID)) fail("An amended case ID is not present in the corpus.");
    if (Object.hasOwn(journal.attempts, caseID)) {
      fail("A case that already consumed a lookup attempt cannot be amended.");
    }
  }

  const next = clone(journal);
  next.corpusHash = validated.corpusHash;
  next.updatedAt = requireString(now, "amendment timestamp");
  validateJournal(next, validated.corpusHash, caseIDs);
  atomicWriteJSON(journalPath, next);
  return next;
}

function recalculateJournalTotals(journal) {
  const attempts = Object.values(journal.attempts);
  journal.totals = {
    marginLookupAttempts: attempts.length,
    httpRequestBudget: attempts.length * MAX_HTTP_REQUESTS_PER_ATTEMPT,
    httpRequests: attempts.reduce((sum, attempt) => sum + attempt.httpRequests, 0),
    deepseekCollectedCases: attempts.filter(
      (attempt) => attempt.status === "deepseekCollected",
    ).length,
    completeCases: attempts.filter((attempt) => attempt.status === "complete").length,
    failedCases: attempts.filter((attempt) => attempt.status === "failed").length,
  };
}

function reserveLookupAttempt(journal, caseID, now = new Date().toISOString()) {
  const next = clone(journal);
  if (!next.caseOrder.includes(caseID)) fail("Cannot reserve an attempt for an unknown case.");
  if (Object.hasOwn(next.attempts, caseID)) {
    fail("This case already consumed its single lookup attempt; automatic retries are disabled.");
  }
  if (next.totals.marginLookupAttempts >= MAX_MARGIN_LOOKUP_ATTEMPTS) {
    fail("The maximum of 40 Margin lookup attempts has been reached.");
  }
  if (next.totals.httpRequestBudget + MAX_HTTP_REQUESTS_PER_ATTEMPT > MAX_HTTP_REQUESTS) {
    fail("The maximum HTTP request budget has been reached.");
  }
  next.attempts[caseID] = {
    status: "reserved",
    attemptNumber: next.totals.marginLookupAttempts + 1,
    httpRequests: 0,
    startedAt: requireString(now, "attempt timestamp"),
  };
  next.updatedAt = now;
  recalculateJournalTotals(next);
  return next;
}

function completeLookupAttempt(
  journal,
  caseID,
  candidateTexts,
  httpRequests,
  now = new Date().toISOString(),
) {
  const next = clone(journal);
  const attempt = next.attempts[caseID];
  if (!attempt || attempt.status !== "reserved") fail("The case has no reserved lookup attempt to complete.");
  const requestCount = requireInteger(httpRequests, "HTTP request count", 0);
  if (requestCount > MAX_HTTP_REQUESTS_PER_ATTEMPT) {
    fail("A Margin lookup attempt may use at most two HTTP requests.");
  }
  const candidates = requireObject(candidateTexts, "candidate inputs");
  attempt.status = "complete";
  attempt.httpRequests = requestCount;
  attempt.completedAt = requireString(now, "completion timestamp");
  attempt.candidates = {
    apple: { text: requireString(candidates.apple, "Apple candidate text").trim() },
    deepseek: { text: requireString(candidates.deepseek, "DeepSeek candidate text").trim() },
  };
  next.updatedAt = now;
  recalculateJournalTotals(next);
  return next;
}

function stageDeepSeekCandidate(
  journal,
  caseID,
  candidateText,
  httpRequests,
  now = new Date().toISOString(),
) {
  const next = clone(journal);
  const attempt = next.attempts[caseID];
  if (!attempt || attempt.status !== "reserved") {
    fail("The case has no reserved lookup attempt awaiting a DeepSeek result.");
  }
  const requestCount = requireInteger(httpRequests, "HTTP request count", 0);
  if (requestCount > MAX_HTTP_REQUESTS_PER_ATTEMPT) {
    fail("A Margin lookup attempt may use at most two HTTP requests.");
  }
  attempt.status = "deepseekCollected";
  attempt.httpRequests = requestCount;
  attempt.deepseekCollectedAt = requireString(now, "DeepSeek collection timestamp");
  attempt.candidates = {
    deepseek: {
      text: requireChineseCandidate(candidateText, "DeepSeek candidate text"),
    },
  };
  next.updatedAt = now;
  recalculateJournalTotals(next);
  return next;
}

function validateAppleImportDocument(input, caseOrder) {
  const document = requireObject(input, "Apple import");
  assertOnlyKeys(document, new Set(["schemaVersion", "rows"]), "Apple import");
  if (document.schemaVersion !== APPLE_IMPORT_SCHEMA_VERSION) {
    fail(`Apple import schemaVersion must be ${APPLE_IMPORT_SCHEMA_VERSION}.`);
  }
  if (!Array.isArray(document.rows) || document.rows.length !== caseOrder.length) {
    fail(`Apple import must contain exactly ${caseOrder.length} rows.`);
  }
  return document.rows.map((inputRow, index) => {
    const row = requireObject(inputRow, `Apple import rows[${index}]`);
    assertOnlyKeys(
      row,
      new Set(["case", "caseID", "appleTranslation", "note"]),
      `Apple import rows[${index}]`,
    );
    if (requireInteger(row.case, `Apple import rows[${index}].case`, 1) !== index + 1) {
      fail("Apple import case numbers must remain in the original order.");
    }
    if (requireIdentifier(row.caseID, `Apple import rows[${index}].caseID`) !== caseOrder[index]) {
      fail("Apple import case IDs must exactly match the journal order.");
    }
    if (Object.hasOwn(row, "note") && typeof row.note !== "string") {
      fail(`Apple import rows[${index}].note must be a string when present.`);
    }
    return {
      case: index + 1,
      caseID: caseOrder[index],
      candidate: validateAppleCandidate(row.appleTranslation),
    };
  });
}

function importAppleCandidates(
  journal,
  importDocument,
  now = new Date().toISOString(),
) {
  const next = clone(journal);
  const rows = validateAppleImportDocument(importDocument, next.caseOrder);
  for (const row of rows) {
    const attempt = next.attempts[row.caseID];
    if (!attempt) fail("Every Apple import case must already have a Margin lookup attempt.");
    if (attempt.status === "deepseekCollected") {
      attempt.status = "complete";
      attempt.completedAt = requireString(now, "Apple import timestamp");
      attempt.candidates = {
        apple: { text: row.candidate.text },
        deepseek: attempt.candidates.deepseek,
      };
      continue;
    }
    if (attempt.status === "complete") {
      const existing = validateAppleCandidate(attempt.candidates.apple.text);
      if (normalizeTextIdentity(existing.text) !== normalizeTextIdentity(row.candidate.text)) {
        fail("Apple import differs from an already completed candidate beyond a recognized footer.");
      }
      attempt.candidates = {
        apple: { text: row.candidate.text },
        deepseek: attempt.candidates.deepseek,
      };
      continue;
    }
    fail("Apple import requires every case to be complete or waiting only for Apple.");
  }
  next.updatedAt = now;
  recalculateJournalTotals(next);
  return next;
}

function failLookupAttempt(
  journal,
  caseID,
  reasonCode,
  httpRequests,
  now = new Date().toISOString(),
) {
  const next = clone(journal);
  const attempt = next.attempts[caseID];
  if (!attempt || attempt.status !== "reserved") fail("The case has no reserved lookup attempt to fail.");
  if (!REASON_CODES.has(reasonCode)) fail("Failure reason code is unsupported.");
  const requestCount = requireInteger(httpRequests, "HTTP request count", 0);
  if (requestCount > MAX_HTTP_REQUESTS_PER_ATTEMPT) {
    fail("A Margin lookup attempt may use at most two HTTP requests.");
  }
  attempt.status = "failed";
  attempt.httpRequests = requestCount;
  attempt.completedAt = requireString(now, "failure timestamp");
  attempt.reasonCode = reasonCode;
  next.updatedAt = now;
  recalculateJournalTotals(next);
  return next;
}

function saveJournal(journalPath, journal, validated) {
  const caseIDs = validated.items.map((item) => item.id);
  validateJournal(journal, validated.corpusHash, caseIDs);
  atomicWriteJSON(journalPath, journal);
  return journal;
}

function requireMetadata(input, totalCases) {
  const metadata = requireObject(input, "metadata");
  const appleBaseline = requireObject(metadata.appleBaseline, "metadata.appleBaseline");
  const caseCounts = requireObject(metadata.caseCounts, "metadata.caseCounts");
  const normalization = requireObject(metadata.normalization, "metadata.normalization");
  const privateCount = requireInteger(caseCounts.private, "metadata.caseCounts.private", 0);
  const publicDomainCount = requireInteger(
    caseCounts.publicDomain,
    "metadata.caseCounts.publicDomain",
    0,
  );
  const total = requireInteger(caseCounts.total, "metadata.caseCounts.total", 0);
  if (total !== totalCases || privateCount + publicDomainCount !== total) {
    fail("Evaluation case counts must sum to the complete corpus size.");
  }
  if (privateCount !== REQUIRED_PRIVATE_CASES
    || publicDomainCount !== REQUIRED_PUBLIC_DOMAIN_CASES
    || total !== TOTAL_CASES) {
    fail("Formal evaluation case counts must be 12 private and 28 public-domain cases.");
  }
  return {
    corpusHash: requireString(metadata.corpusHash, "metadata.corpusHash"),
    marginCommit: requireString(metadata.marginCommit, "metadata.marginCommit").trim(),
    providerModel: requireString(metadata.providerModel, "metadata.providerModel").trim(),
    promptContractVersion: requireString(
      metadata.promptContractVersion,
      "metadata.promptContractVersion",
    ).trim(),
    normalization: {
      contractVersion: requireString(
        normalization.contractVersion,
        "metadata.normalization.contractVersion",
      ).trim(),
      scriptConverter: requireString(
        normalization.scriptConverter,
        "metadata.normalization.scriptConverter",
      ).trim(),
      targetLanguage: requireString(
        normalization.targetLanguage,
        "metadata.normalization.targetLanguage",
      ).trim(),
    },
    appleBaseline: {
      macOSVersion: requireString(appleBaseline.macOSVersion, "metadata.appleBaseline.macOSVersion").trim(),
      booksVersion: requireString(appleBaseline.booksVersion, "metadata.appleBaseline.booksVersion").trim(),
      locale: requireString(appleBaseline.locale, "metadata.appleBaseline.locale").trim(),
    },
    caseCounts: { private: privateCount, publicDomain: publicDomainCount, total },
  };
}

function mergeCompleteJournal(validated, journal, datasetInput, metadataInput) {
  const caseIDs = validated.items.map((item) => item.id);
  validateJournal(journal, validated.corpusHash, caseIDs);
  if (journal.totals.marginLookupAttempts > MAX_MARGIN_LOOKUP_ATTEMPTS
    || journal.totals.httpRequestBudget > MAX_HTTP_REQUESTS
    || journal.totals.httpRequests > MAX_HTTP_REQUESTS) {
    fail("Journal safety limits were exceeded.");
  }
  if (journal.totals.completeCases !== validated.items.length
    || journal.totals.failedCases !== 0
    || validated.items.some((item) => journal.attempts[item.id]?.status !== "complete")) {
    fail("Journal must contain one complete, non-retried attempt for every corpus case.");
  }
  const dataset = requireObject(datasetInput, "dataset metadata");
  const createdAt = requireString(dataset.createdAt, "dataset.createdAt").trim();
  if (Number.isNaN(Date.parse(createdAt))) fail("dataset.createdAt must be a valid timestamp.");
  const metadata = requireMetadata(
    {
      ...metadataInput,
      corpusHash: validated.corpusHash,
      normalization: {
        contractVersion: NORMALIZATION_CONTRACT_VERSION,
        scriptConverter: SCRIPT_CONVERTER,
        targetLanguage: TARGET_LANGUAGE,
      },
    },
    validated.items.length,
  );
  if (metadata.corpusHash !== journal.corpusHash) fail("Metadata corpus hash does not match the journal.");
  const normalizedCandidates = normalizeBlindCandidates(
    validated,
    journal,
    convertTraditionalToSimplifiedBatch,
  );
  return {
    schemaVersion: OUTPUT_SCHEMA_VERSION,
    dataset: {
      id: requireIdentifier(dataset.id, "dataset.id"),
      title: requireString(dataset.title, "dataset.title").trim(),
      createdAt,
      metadata,
      cases: validated.items.map((item, index) => ({
        id: item.id,
        category: item.category,
        source: {
          text: item.text,
          attribution: {
            title: item.attribution.title,
            creator: item.attribution.creator,
            sourceURL: item.attribution.sourceURL,
            license: item.attribution.license,
          },
        },
        candidates: normalizedCandidates[index],
      })),
    },
  };
}

module.exports = {
  CATEGORIES,
  constants: {
    CORPUS_SCHEMA_VERSION,
    OUTPUT_SCHEMA_VERSION,
    JOURNAL_VERSION,
    TOTAL_CASES,
    TOTAL_WORKS,
    CASES_PER_WORK,
    CASES_PER_CATEGORY,
    MIN_SENTENCES,
    MAX_SENTENCES,
    MAX_SOURCE_CHARACTERS,
    MAX_MARGIN_LOOKUP_ATTEMPTS,
    MAX_HTTP_REQUESTS_PER_ATTEMPT,
    MAX_HTTP_REQUESTS,
    REQUIRED_PRIVATE_CASES,
    REQUIRED_PUBLIC_DOMAIN_CASES,
    NORMALIZATION_CONTRACT_VERSION,
    SCRIPT_CONVERTER,
    TARGET_LANGUAGE,
  },
  PreparationError,
  atomicBackupPrivateJSON,
  atomicWriteJSON,
  canonicalJSONString,
  canonicalSHA256,
  completeLookupAttempt,
  countSentences,
  createEpub,
  createJournal,
  extractAppleImportFromXlsx,
  failLookupAttempt,
  importAppleCandidates,
  amendJournalForUntestedSources,
  initializeJournal,
  loadAndValidateCorpora,
  loadJournal,
  mergeCompleteJournal,
  normalizeBlindCandidate,
  normalizeBlindCandidates,
  convertTraditionalToSimplifiedBatch,
  readJSONFile,
  reserveLookupAttempt,
  saveJournal,
  stageDeepSeekCandidate,
  stripAppleBooksFooter,
  validateAppleImportDocument,
  validateJournal,
  validateSourceCorpora,
};
