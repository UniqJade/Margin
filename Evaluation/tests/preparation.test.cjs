"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const Preparation = require("../tools/preparation.cjs");
const Core = require("../core.js");

function sampleCorpus() {
  const items = Array.from({ length: 40 }, (_, index) => {
    const workNumber = Math.floor(index / 4) + 1;
    const caseNumber = index + 1;
    return {
      id: `case-${String(caseNumber).padStart(3, "0")}`,
      workId: `work-${String(workNumber).padStart(2, "0")}`,
      category: Preparation.CATEGORIES[index % Preparation.CATEGORIES.length],
      text: `Excerpt ${caseNumber} opens with a distinct observation. Its second sentence closes case ${caseNumber}.`,
      chapter: `Chapter ${index % 4 + 1}`,
      attribution: {
        title: `Test Work ${workNumber}`,
        creator: `Test Creator ${workNumber}`,
        sourceURL: workNumber <= 5 ? `https://example.invalid/works/${workNumber}` : "",
        license: workNumber <= 5 ? "Public domain test fixture" : "Private evaluation test fixture",
      },
    };
  });
  return {
    schemaVersion: 1,
    corpus: {
      id: "test-corpus-v1",
      title: "Preparation test corpus",
      purpose: "Source-only local test data",
      items,
    },
  };
}

function temporaryDirectory(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "margin-preparation-test-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

function createAppleWorkbookFixture(directory, caseIDs) {
  const root = path.join(directory, "xlsx");
  fs.mkdirSync(path.join(root, "xl", "_rels"), { recursive: true });
  fs.mkdirSync(path.join(root, "xl", "worksheets"), { recursive: true });
  fs.writeFileSync(
    path.join(root, "xl", "workbook.xml"),
    `<?xml version="1.0"?><x:workbook xmlns:x="urn:test" xmlns:r="urn:rels"><x:sheets><x:sheet name="Apple 译文" sheetId="1" r:id="sheet-rel"/></x:sheets></x:workbook>`,
  );
  fs.writeFileSync(
    path.join(root, "xl", "_rels", "workbook.xml.rels"),
    `<?xml version="1.0"?><Relationships><Relationship Id="sheet-rel" Target="worksheets/sheet1.xml"/></Relationships>`,
  );
  const escape = (value) => value.replaceAll("&", "&amp;").replaceAll("<", "&lt;");
  const rows = caseIDs.map((caseID, index) => {
    const row = index + 6;
    return `<row r="${row}"><c r="A${row}"><v>${index + 1}</v></c><c r="B${row}" t="inlineStr"><is><t>${escape(caseID)}</t></is></c><c r="D${row}" t="inlineStr"><is><t>苹果译文第${index + 1}条。</t></is></c><c r="F${row}" t="inlineStr"><is><t>${index === 0 ? "已复核" : ""}</t></is></c></row>`;
  }).join("");
  fs.writeFileSync(
    path.join(root, "xl", "worksheets", "sheet1.xml"),
    `<?xml version="1.0"?><worksheet><sheetData>${rows}</sheetData></worksheet>`,
  );
  const output = path.join(directory, "apple.private.xlsx");
  const zipped = spawnSync("zip", ["-Xqr", output, "xl"], { cwd: root, encoding: "utf8" });
  assert.equal(zipped.status, 0, zipped.stderr);
  return output;
}

function completeJournal(validated) {
  let journal = Preparation.createJournal(
    validated.corpusHash,
    validated.items.map((item) => item.id),
    "2026-07-16T00:00:00Z",
  );
  validated.items.forEach((item, index) => {
    journal = Preparation.reserveLookupAttempt(
      journal,
      item.id,
      `2026-07-16T00:${String(index).padStart(2, "0")}:00Z`,
    );
    journal = Preparation.completeLookupAttempt(
      journal,
      item.id,
      {
        apple: `苹果私有候选译文第${index + 1}条。`,
        deepseek: `深度求索私有候选译文第${index + 1}条。`,
      },
      2,
      `2026-07-16T00:${String(index).padStart(2, "0")}:30Z`,
    );
  });
  return journal;
}

test("validates exactly 40 source-only cases as 10 works x 4 and four categories x 10", () => {
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);

  assert.equal(validated.items.length, 40);
  assert.equal(validated.workCount, 10);
  assert.deepEqual(
    validated.categoryCounts,
    Object.fromEntries(Preparation.CATEGORIES.map((category) => [category, 10])),
  );
  assert.match(validated.corpusHash, /^sha256:[a-f0-9]{64}$/);

  const firstHalf = sampleCorpus();
  const secondHalf = sampleCorpus();
  firstHalf.corpus.id = "combined-a";
  firstHalf.corpus.items = firstHalf.corpus.items.slice(0, 20);
  secondHalf.corpus.id = "combined-b";
  secondHalf.corpus.items = secondHalf.corpus.items.slice(20);
  const combined = Preparation.validateSourceCorpora([firstHalf, secondHalf]);
  assert.equal(combined.items.length, 40);
  assert.equal(combined.workCount, 10);
});

test("rejects candidate-bearing, duplicate, incorrectly sized, and invalid sentence corpora cleanly", () => {
  const withCandidates = sampleCorpus();
  withCandidates.corpus.items[0].candidates = { apple: { text: "private" } };
  assert.throws(
    () => Preparation.validateSourceCorpora([withCandidates]),
    /source-only/i,
  );

  const duplicateID = sampleCorpus();
  duplicateID.corpus.items[1].id = duplicateID.corpus.items[0].id;
  assert.throws(
    () => Preparation.validateSourceCorpora([duplicateID]),
    /IDs must be unique/i,
  );

  const duplicateText = sampleCorpus();
  duplicateText.corpus.items[1].text = `  ${duplicateText.corpus.items[0].text.toUpperCase()}  `;
  assert.throws(
    () => Preparation.validateSourceCorpora([duplicateText]),
    /source texts must be unique/i,
  );

  const tooFew = sampleCorpus();
  tooFew.corpus.items.pop();
  assert.throws(
    () => Preparation.validateSourceCorpora([tooFew]),
    /exactly 40 cases/i,
  );

  const oneSentence = sampleCorpus();
  oneSentence.corpus.items[0].text = "Only one sentence is present.";
  assert.throws(
    () => Preparation.validateSourceCorpora([oneSentence]),
    /between 2 and 4 sentences/i,
  );

  const missingLicense = sampleCorpus();
  missingLicense.corpus.items[0].attribution.license = "";
  assert.throws(
    () => Preparation.validateSourceCorpora([missingLicense]),
    /license.*non-empty string/i,
  );

  const tooLong = sampleCorpus();
  tooLong.corpus.items[0].text = `${"x".repeat(1_995)}. End.`;
  assert.throws(
    () => Preparation.validateSourceCorpora([tooLong]),
    /at most 2000 characters/i,
  );

  const unbalancedCategory = sampleCorpus();
  unbalancedCategory.corpus.items[0].category = Preparation.CATEGORIES[1];
  assert.throws(
    () => Preparation.validateSourceCorpora([unbalancedCategory]),
    /category must contain exactly 10 cases/i,
  );

  const unbalancedWork = sampleCorpus();
  unbalancedWork.corpus.items[0].workId = "work-02";
  unbalancedWork.corpus.items[0].attribution = {
    ...unbalancedWork.corpus.items[4].attribution,
  };
  assert.throws(
    () => Preparation.validateSourceCorpora([unbalancedWork]),
    /exactly 10 works|exactly 4 cases/i,
  );
});

test("canonical SHA-256 is independent of JSON key and item ordering", () => {
  const first = sampleCorpus();
  const second = sampleCorpus();
  second.corpus.items.reverse();
  second.corpus = {
    purpose: second.corpus.purpose,
    items: second.corpus.items.map((item) => ({
      attribution: {
        license: item.attribution.license,
        sourceURL: item.attribution.sourceURL,
        creator: item.attribution.creator,
        title: item.attribution.title,
      },
      text: item.text,
      category: item.category,
      chapter: item.chapter,
      workId: item.workId,
      id: item.id,
    })),
    title: second.corpus.title,
    id: second.corpus.id,
  };

  const firstValidated = Preparation.validateSourceCorpora([first]);
  const secondValidated = Preparation.validateSourceCorpora([second]);
  assert.equal(firstValidated.corpusHash, secondValidated.corpusHash);
  assert.equal(
    Preparation.canonicalSHA256({ z: 1, a: { y: 2, x: 3 } }),
    Preparation.canonicalSHA256({ a: { x: 3, y: 2 }, z: 1 }),
  );
});

test("creates a minimal EPUB with stored mimetype and exactly one source case per chapter", (t) => {
  const directory = temporaryDirectory(t);
  const output = path.join(directory, "nested", "reading.epub");
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);
  Preparation.createEpub(validated, output, "2026-07-16T00:00:00Z");

  const listing = spawnSync("unzip", ["-Z1", output], { encoding: "utf8" });
  assert.equal(listing.status, 0, listing.stderr);
  const integrity = spawnSync("unzip", ["-tqq", output], { encoding: "utf8" });
  assert.equal(integrity.status, 0, integrity.stderr);
  const entries = listing.stdout.trim().split("\n");
  assert.equal(entries[0], "mimetype");
  assert.equal(entries.filter((entry) => /OEBPS\/chapters\/chapter-\d{3}\.xhtml$/.test(entry)).length, 40);

  const verbose = spawnSync("unzip", ["-lv", output], { encoding: "utf8" });
  assert.equal(verbose.status, 0, verbose.stderr);
  assert.match(verbose.stdout, /\s0%\s+.*mimetype/);

  const allChapterText = entries
    .filter((entry) => entry.includes("OEBPS/chapters/"))
    .map((entry) => spawnSync("unzip", ["-p", output, entry], { encoding: "utf8" }).stdout)
    .join("\n");
  assert.doesNotMatch(allChapterText, /\b(?:apple|deepseek|provider|candidate)\b/i);
  assert.equal((allChapterText.match(/<main>/g) || []).length, 40);
});

test("journal is atomic, resumable by corpus hash, private, and permits no retry", (t) => {
  const directory = temporaryDirectory(t);
  const journalPath = path.join(directory, "private", "progress.json");
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);
  const first = Preparation.initializeJournal(
    journalPath,
    validated,
    "2026-07-16T00:00:00Z",
  );
  assert.equal(first.corpusHash, validated.corpusHash);
  assert.equal(fs.statSync(journalPath).mode & 0o777, 0o600);
  assert.deepEqual(
    fs.readdirSync(path.dirname(journalPath)).sort(),
    [path.basename(journalPath)],
  );

  const resumed = Preparation.initializeJournal(
    journalPath,
    validated,
    "2026-07-16T01:00:00Z",
  );
  assert.equal(resumed.createdAt, "2026-07-16T00:00:00Z");

  const firstCaseID = validated.items[0].id;
  const reserved = Preparation.reserveLookupAttempt(resumed, firstCaseID);
  assert.equal(reserved.totals.marginLookupAttempts, 1);
  assert.equal(reserved.totals.httpRequestBudget, 2);
  assert.throws(
    () => Preparation.reserveLookupAttempt(reserved, firstCaseID),
    /single lookup attempt|retries are disabled/i,
  );
  assert.throws(
    () => Preparation.completeLookupAttempt(
      reserved,
      firstCaseID,
      { apple: "private A", deepseek: "private B" },
      3,
    ),
    /at most two HTTP requests/i,
  );

  const journalWithUnknownData = JSON.parse(JSON.stringify(reserved));
  journalWithUnknownData.attempts[firstCaseID].apiKey = "must-not-be-accepted";
  assert.throws(
    () => Preparation.validateJournal(
      journalWithUnknownData,
      validated.corpusHash,
      validated.items.map((item) => item.id),
    ),
    /unsupported field/i,
  );

  const changed = sampleCorpus();
  changed.corpus.items[0].text = "A changed first sentence. A changed second sentence.";
  const other = Preparation.validateSourceCorpora([changed]);
  assert.throws(
    () => Preparation.loadJournal(
      journalPath,
      other.corpusHash,
      other.items.map((item) => item.id),
    ),
    /different corpus hash/i,
  );
});

test("stages DeepSeek first, migrates legacy journals, and imports Apple rows without retries", () => {
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);
  const caseIDs = validated.items.map((item) => item.id);
  let journal = Preparation.createJournal(
    validated.corpusHash,
    caseIDs,
    "2026-07-17T00:00:00Z",
  );

  caseIDs.forEach((caseID, index) => {
    journal = Preparation.reserveLookupAttempt(
      journal,
      caseID,
      `2026-07-17T00:${String(index).padStart(2, "0")}:00Z`,
    );
    if (index === 0) {
      journal = Preparation.completeLookupAttempt(
        journal,
        caseID,
        {
          apple: "苹果候选译文。\n\n摘录来自\n\n测试语料\n\n此内容可能受版权保护。",
          deepseek: "深度求索候选译文。",
        },
        1,
        "2026-07-17T00:00:30Z",
      );
    } else {
      journal = Preparation.stageDeepSeekCandidate(
        journal,
        caseID,
        `深度求索候选译文第${index + 1}条。`,
        index === 1 ? 0 : 1,
        `2026-07-17T00:${String(index).padStart(2, "0")}:30Z`,
      );
    }
  });

  assert.equal(journal.totals.marginLookupAttempts, 40);
  assert.equal(journal.totals.deepseekCollectedCases, 39);
  assert.equal(journal.totals.completeCases, 1);
  assert.equal(journal.totals.httpRequests, 39);
  assert.throws(
    () => Preparation.reserveLookupAttempt(journal, caseIDs[1]),
    /single lookup attempt|retries are disabled/i,
  );

  const appleImport = {
    schemaVersion: 1,
    rows: caseIDs.map((caseID, index) => ({
      case: index + 1,
      caseID,
      appleTranslation: index === 0 ? "苹果候选译文。" : `苹果候选译文第${index + 1}条。`,
      note: "",
    })),
  };
  const completed = Preparation.importAppleCandidates(
    journal,
    appleImport,
    "2026-07-17T01:00:00Z",
  );
  assert.equal(completed.totals.deepseekCollectedCases, 0);
  assert.equal(completed.totals.completeCases, 40);
  assert.equal(completed.attempts[caseIDs[0]].candidates.apple.text, "苹果候选译文。");
  assert.equal(completed.attempts[caseIDs[1]].httpRequests, 0);
  Preparation.validateJournal(completed, validated.corpusHash, caseIDs);

  const changedImport = JSON.parse(JSON.stringify(appleImport));
  changedImport.rows[0].appleTranslation = "另一条苹果候选译文。";
  assert.throws(
    () => Preparation.importAppleCandidates(journal, changedImport),
    /differs.*recognized footer/i,
  );

  const legacy = Preparation.createJournal(validated.corpusHash, caseIDs);
  legacy.journalVersion = 1;
  delete legacy.totals.deepseekCollectedCases;
  const migrated = Preparation.validateJournal(legacy, validated.corpusHash, caseIDs);
  assert.equal(migrated.journalVersion, Preparation.constants.JOURNAL_VERSION);
  assert.equal(migrated.totals.deepseekCollectedCases, 0);
});

test("extracts the controlled Apple workbook without third-party spreadsheet dependencies", (t) => {
  const directory = temporaryDirectory(t);
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);
  const caseIDs = validated.items.map((item) => item.id);
  const workbookPath = createAppleWorkbookFixture(directory, caseIDs);
  const extracted = Preparation.extractAppleImportFromXlsx(workbookPath, caseIDs);

  assert.equal(extracted.schemaVersion, 1);
  assert.equal(extracted.rows.length, 40);
  assert.deepEqual(extracted.rows[0], {
    case: 1,
    caseID: caseIDs[0],
    appleTranslation: "苹果译文第1条。",
    note: "已复核",
  });
  const changed = JSON.parse(JSON.stringify(extracted));
  changed.rows[1].caseID = changed.rows[0].caseID;
  assert.throws(
    () => Preparation.validateAppleImportDocument(changed, caseIDs),
    /exactly match.*order/i,
  );
});

test("blind display normalization removes provider wrappers and preserves internal quotations", () => {
  const unwrappedSource = "The narrator described the room. Nobody answered.";
  const normalized = Preparation.normalizeBlindCandidate(
    unwrappedSource,
    "  “「繁體」是內部引語。”  ",
    "“「繁体」是内部引语。”",
  );
  assert.equal(normalized.rawText, "“「繁體」是內部引語。”");
  assert.equal(normalized.displayText, "“繁体”是内部引语。");
  assert.deepEqual(normalized.normalization, {
    whitespaceAdjusted: false,
    scriptConverted: true,
    quoteGlyphsAdjusted: true,
    outerQuoteAdjusted: true,
  });

  const repeated = Preparation.normalizeBlindCandidate(
    unwrappedSource,
    normalized.displayText,
    normalized.displayText,
  );
  assert.equal(repeated.displayText, normalized.displayText);
  assert.deepEqual(repeated.normalization, {
    whitespaceAdjusted: false,
    scriptConverted: false,
    quoteGlyphsAdjusted: false,
    outerQuoteAdjusted: false,
  });
});

test("source-controlled outer quotes are identical while English apostrophes remain intact", () => {
  const source = "\"Don't leave,\" she said. \"I won't.\"";
  const first = Preparation.normalizeBlindCandidate(
    source,
    "她说：“Don't leave。”随后又说：“I won't。”",
    "她说：“Don't leave。”随后又说：“I won't。”",
  );
  const second = Preparation.normalizeBlindCandidate(
    source,
    "“她说：‘不要走。’随后又说：‘我不会。’”",
    "“她说：‘不要走。’随后又说：‘我不会。’”",
  );
  assert.equal(first.displayText.startsWith("“"), true);
  assert.equal(first.displayText.endsWith("”"), true);
  assert.match(first.displayText, /Don't leave|I won't/);
  assert.equal(second.displayText.startsWith("“"), true);
  assert.equal(second.displayText.endsWith("”"), true);
  assert.equal(second.displayText.startsWith("““"), false);
});

test("Foundation converter changes Traditional Chinese for both providers without network access", () => {
  const converted = Preparation.convertTraditionalToSimplifiedBatch([
    "繁體中文與軟體",
    "這是另一條譯文",
  ]);
  assert.deepEqual(converted, ["繁体中文与软体", "这是另一条译文"]);
});

test("private journal backup is mode 0600 and leaves the source unchanged", (t) => {
  const directory = temporaryDirectory(t);
  const journalPath = path.join(directory, "collection-journal.private.json");
  const contents = { private: "candidate data" };
  Preparation.atomicWriteJSON(journalPath, contents);
  const backupPath = Preparation.atomicBackupPrivateJSON(
    journalPath,
    "pre-apple-import",
    "2026-07-17T12:34:56Z",
  );
  assert.equal(fs.statSync(backupPath).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(fs.readFileSync(backupPath, "utf8")), contents);
  assert.deepEqual(JSON.parse(fs.readFileSync(journalPath, "utf8")), contents);
  assert.match(path.basename(backupPath), /pre-apple-import-20260717123456/);
});

test("migrates completed attempts only when amended source cases are untested", (t) => {
  const directory = temporaryDirectory(t);
  const journalPath = path.join(directory, "progress.json");
  const blockedJournalPath = path.join(directory, "blocked.json");
  const original = Preparation.validateSourceCorpora([sampleCorpus()]);
  const firstCaseID = original.items[0].id;
  const amendedCaseID = original.items[1].id;

  let journal = Preparation.createJournal(
    original.corpusHash,
    original.items.map((item) => item.id),
    "2026-07-16T00:00:00Z",
  );
  journal = Preparation.reserveLookupAttempt(journal, firstCaseID);
  journal = Preparation.completeLookupAttempt(
    journal,
    firstCaseID,
    { apple: "private Apple result", deepseek: "private DeepSeek result" },
    1,
  );
  Preparation.atomicWriteJSON(journalPath, journal);
  Preparation.atomicWriteJSON(blockedJournalPath, journal);

  const revisedCorpus = sampleCorpus();
  revisedCorpus.corpus.items[1].text = "A revised first sentence remains source only. A revised second sentence stays untested.";
  const revised = Preparation.validateSourceCorpora([revisedCorpus]);
  const migrated = Preparation.amendJournalForUntestedSources(
    journalPath,
    revised,
    [amendedCaseID],
    "2026-07-16T02:00:00Z",
  );

  assert.equal(migrated.corpusHash, revised.corpusHash);
  assert.equal(migrated.totals.completeCases, 1);
  assert.equal(migrated.totals.httpRequests, 1);
  assert.equal(migrated.attempts[firstCaseID].candidates.apple.text, "private Apple result");
  assert.equal(fs.statSync(journalPath).mode & 0o777, 0o600);
  assert.throws(
    () => Preparation.amendJournalForUntestedSources(
      blockedJournalPath,
      revised,
      [firstCaseID],
    ),
    /already consumed a lookup attempt/i,
  );
});

test("request budget derives 80 HTTP requests from at most 40 single attempts", () => {
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);
  const journal = completeJournal(validated);

  assert.equal(journal.totals.marginLookupAttempts, 40);
  assert.equal(journal.totals.httpRequestBudget, 80);
  assert.equal(journal.totals.httpRequests, 80);
  assert.equal(journal.totals.completeCases, 40);
  assert.equal(journal.limits.automaticRetries, false);
  Preparation.validateJournal(
    journal,
    validated.corpusHash,
    validated.items.map((item) => item.id),
  );
});

test("merges only a complete journal into the exact evaluator schema v3 private shape", (t) => {
  const directory = temporaryDirectory(t);
  const outputPath = path.join(directory, "arbitrary", "dataset.private.json");
  const validated = Preparation.validateSourceCorpora([sampleCorpus()]);
  const incomplete = Preparation.createJournal(
    validated.corpusHash,
    validated.items.map((item) => item.id),
  );
  const datasetMetadata = {
    id: "private-reading-v2",
    title: "Private reading evaluation",
    createdAt: "2026-07-16T00:00:00Z",
  };
  const evaluationMetadata = {
    marginCommit: "0123456789abcdef",
    providerModel: "deepseek-v4-flash",
    promptContractVersion: "lookup-v2",
    appleBaseline: {
      macOSVersion: "26.5",
      booksVersion: "8.5",
      locale: "zh-Hans-CN",
    },
    caseCounts: { private: 12, publicDomain: 28, total: 40 },
  };
  assert.throws(
    () => Preparation.mergeCompleteJournal(
      validated,
      incomplete,
      datasetMetadata,
      evaluationMetadata,
    ),
    /complete.*every corpus case/i,
  );

  const journal = completeJournal(validated);
  assert.throws(
    () => Preparation.mergeCompleteJournal(
      validated,
      journal,
      datasetMetadata,
      {
        ...evaluationMetadata,
        caseCounts: { private: 20, publicDomain: 20, total: 40 },
      },
    ),
    /12 private and 28 public-domain/i,
  );
  const output = Preparation.mergeCompleteJournal(
    validated,
    journal,
    datasetMetadata,
    evaluationMetadata,
  );
  assert.deepEqual(Object.keys(output), ["schemaVersion", "dataset"]);
  assert.equal(output.schemaVersion, 3);
  assert.deepEqual(
    Object.keys(output.dataset),
    ["id", "title", "createdAt", "metadata", "cases"],
  );
  assert.deepEqual(
    Object.keys(output.dataset.metadata),
    [
      "corpusHash",
      "marginCommit",
      "providerModel",
      "promptContractVersion",
      "normalization",
      "appleBaseline",
      "caseCounts",
    ],
  );
  assert.equal(output.dataset.metadata.corpusHash, validated.corpusHash);
  assert.deepEqual(output.dataset.metadata.normalization, {
    contractVersion: "blind-display-v1",
    scriptConverter: "Foundation Traditional-Simplified",
    targetLanguage: "zh-Hans-CN",
  });
  assert.equal(output.dataset.cases.length, 40);
  assert.deepEqual(Object.keys(output.dataset.cases[0].candidates), ["apple", "deepseek"]);
  assert.deepEqual(
    Object.keys(output.dataset.cases[0].candidates.apple),
    ["rawText", "displayText", "normalization"],
  );
  assert.equal(Core.validateDataset(output).schemaVersion, 3);

  Preparation.atomicWriteJSON(outputPath, output);
  assert.equal(fs.statSync(outputPath).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(fs.readFileSync(outputPath, "utf8")), output);

  const cli = path.resolve(__dirname, "../tools/prepare-evaluation.cjs");
  const corpusPath = path.join(directory, "inputs with spaces", "corpus.json");
  const journalPath = path.join(directory, "inputs with spaces", "journal.json");
  const cliOutputPath = path.join(directory, "outputs with spaces", "merged.private.json");
  Preparation.atomicWriteJSON(corpusPath, sampleCorpus());
  Preparation.atomicWriteJSON(journalPath, journal);
  const cliMergeArguments = [
    cli,
    "merge",
    "--corpus", corpusPath,
    "--journal", journalPath,
    "--output", cliOutputPath,
    "--dataset-id", datasetMetadata.id,
    "--dataset-title", datasetMetadata.title,
    "--created-at", datasetMetadata.createdAt,
    "--margin-commit", evaluationMetadata.marginCommit,
    "--provider-model", evaluationMetadata.providerModel,
    "--prompt-contract-version", evaluationMetadata.promptContractVersion,
    "--macos-version", evaluationMetadata.appleBaseline.macOSVersion,
    "--books-version", evaluationMetadata.appleBaseline.booksVersion,
    "--locale", evaluationMetadata.appleBaseline.locale,
    "--private-count", "12",
    "--public-domain-count", "28",
  ];
  const invalidCLIArguments = [...cliMergeArguments];
  invalidCLIArguments[invalidCLIArguments.indexOf("--private-count") + 1] = "20";
  invalidCLIArguments[invalidCLIArguments.indexOf("--public-domain-count") + 1] = "20";
  const invalidCLIMerge = spawnSync(process.execPath, invalidCLIArguments, { encoding: "utf8" });
  assert.equal(invalidCLIMerge.status, 1);
  assert.match(invalidCLIMerge.stderr, /12 private and 28 public-domain/i);

  const cliMerge = spawnSync(process.execPath, cliMergeArguments, { encoding: "utf8" });
  assert.equal(cliMerge.status, 0, cliMerge.stderr);
  const cliOutput = JSON.parse(fs.readFileSync(cliOutputPath, "utf8"));
  assert.equal(Core.validateDataset(cliOutput).schemaVersion, 3);
  assert.doesNotMatch(cliMerge.stdout, /苹果私有候选|深度求索私有候选/);
});

test("CLI logs only safe counts and clean failures, never source, candidate, or API key", (t) => {
  const directory = temporaryDirectory(t);
  const corpusPath = path.join(directory, "input.json");
  const journalPath = path.join(directory, "journal.json");
  const applePath = path.join(directory, "apple.txt");
  const deepseekPath = path.join(directory, "deepseek.txt");
  const sourceSecret = "SOURCE-SECRET-DO-NOT-LOG";
  const appleSecret = "APPLE-CANDIDATE-SECRET-DO-NOT-LOG";
  const deepseekSecret = "DEEPSEEK-CANDIDATE-SECRET-DO-NOT-LOG";
  const stagedSecret = "私密候选绝对不可写入终端日志";
  const apiKeySecret = "PRIVATE_CREDENTIAL_SENTINEL_DO_NOT_LOG";
  const fingerprintPattern = /(?:sha256|fnv1a):?[a-f0-9-]{8,}/i;
  const corpus = sampleCorpus();
  corpus.corpus.items[0].text = `${sourceSecret} begins this sentence. A second sentence completes it.`;
  fs.writeFileSync(corpusPath, JSON.stringify(corpus));
  fs.writeFileSync(applePath, appleSecret);
  fs.writeFileSync(deepseekPath, deepseekSecret);
  const cli = path.resolve(__dirname, "../tools/prepare-evaluation.cjs");

  const init = spawnSync(process.execPath, [
    cli,
    "journal-init",
    "--corpus", corpusPath,
    "--journal", journalPath,
  ], { encoding: "utf8" });
  assert.equal(init.status, 0, init.stderr);
  assert.doesNotMatch(`${init.stdout}${init.stderr}`, fingerprintPattern);
  const validated = Preparation.loadAndValidateCorpora([corpusPath]);
  const caseID = validated.items[0].id;
  const reserve = spawnSync(process.execPath, [
    cli,
    "journal-reserve",
    "--corpus", corpusPath,
    "--journal", journalPath,
    "--case-id", caseID,
  ], { encoding: "utf8" });
  assert.equal(reserve.status, 0, reserve.stderr);
  const complete = spawnSync(process.execPath, [
    cli,
    "journal-complete",
    "--corpus", corpusPath,
    "--journal", journalPath,
    "--case-id", caseID,
    "--apple-file", applePath,
    "--deepseek-file", deepseekPath,
    "--http-requests", "2",
  ], { encoding: "utf8" });
  assert.equal(complete.status, 0, complete.stderr);
  const secondCaseID = validated.items[1].id;
  const reserveSecond = spawnSync(process.execPath, [
    cli,
    "journal-reserve",
    "--corpus", corpusPath,
    "--journal", journalPath,
    "--case-id", secondCaseID,
  ], { encoding: "utf8" });
  assert.equal(reserveSecond.status, 0, reserveSecond.stderr);
  const stageFromStdin = spawnSync(process.execPath, [
    cli,
    "journal-stage-deepseek-stdin",
    "--corpus", corpusPath,
    "--journal", journalPath,
    "--case-id", secondCaseID,
    "--http-requests", "1",
  ], { encoding: "utf8", input: stagedSecret });
  assert.equal(stageFromStdin.status, 0, stageFromStdin.stderr);

  const status = spawnSync(process.execPath, [
    cli,
    "journal-status",
    "--corpus", corpusPath,
    "--journal", journalPath,
  ], { encoding: "utf8" });
  assert.equal(status.status, 0, status.stderr);
  assert.doesNotMatch(`${status.stdout}${status.stderr}`, fingerprintPattern);

  const validate = spawnSync(process.execPath, [
    cli,
    "validate",
    "--corpus", corpusPath,
  ], { encoding: "utf8" });
  assert.equal(validate.status, 0, validate.stderr);
  assert.doesNotMatch(`${validate.stdout}${validate.stderr}`, fingerprintPattern);

  const epub = spawnSync(process.execPath, [
    cli,
    "epub",
    "--corpus", corpusPath,
    "--output", path.join(directory, "private.epub"),
  ], { encoding: "utf8" });
  assert.equal(epub.status, 0, epub.stderr);
  assert.doesNotMatch(`${epub.stdout}${epub.stderr}`, fingerprintPattern);

  const combinedLogs = [
    init,
    reserve,
    complete,
    reserveSecond,
    stageFromStdin,
    status,
    validate,
    epub,
  ]
    .map((result) => `${result.stdout}${result.stderr}`)
    .join("");
  assert.doesNotMatch(combinedLogs, new RegExp(sourceSecret));
  assert.doesNotMatch(combinedLogs, new RegExp(appleSecret));
  assert.doesNotMatch(combinedLogs, new RegExp(deepseekSecret));
  assert.doesNotMatch(combinedLogs, new RegExp(stagedSecret));

  const rejected = spawnSync(process.execPath, [
    cli,
    "validate",
    "--corpus", corpusPath,
    "--api-key", apiKeySecret,
  ], { encoding: "utf8" });
  assert.equal(rejected.status, 1);
  assert.match(rejected.stderr, /^Preparation failed: /);
  assert.doesNotMatch(`${rejected.stdout}${rejected.stderr}`, new RegExp(apiKeySecret));
  assert.doesNotMatch(`${rejected.stdout}${rejected.stderr}`, fingerprintPattern);
  assert.doesNotMatch(rejected.stderr, /at .*preparation|node:internal|SyntaxError/);

  const changedCorpus = sampleCorpus();
  changedCorpus.corpus.items[0].text = "Changed private source begins here. Its second sentence remains private.";
  const changedCorpusPath = path.join(directory, "changed.json");
  fs.writeFileSync(changedCorpusPath, JSON.stringify(changedCorpus));
  const mismatch = spawnSync(process.execPath, [
    cli,
    "journal-status",
    "--corpus", changedCorpusPath,
    "--journal", journalPath,
  ], { encoding: "utf8" });
  assert.equal(mismatch.status, 1);
  assert.doesNotMatch(`${mismatch.stdout}${mismatch.stderr}`, fingerprintPattern);
});
