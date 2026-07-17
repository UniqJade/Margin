#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const Preparation = require("./preparation.cjs");

const COMMAND_OPTIONS = Object.freeze({
  "capture-clipboard": new Set(["output"]),
  "xlsx-to-apple-json": new Set(["corpus", "xlsx", "output"]),
  validate: new Set(["corpus"]),
  epub: new Set(["corpus", "output"]),
  "journal-init": new Set(["corpus", "journal"]),
  "journal-amend": new Set(["corpus", "journal", "amended-case-id"]),
  "journal-reserve": new Set(["corpus", "journal", "case-id"]),
  "journal-stage-deepseek": new Set([
    "corpus",
    "journal",
    "case-id",
    "deepseek-file",
    "http-requests",
  ]),
  "journal-stage-deepseek-stdin": new Set([
    "corpus",
    "journal",
    "case-id",
    "http-requests",
  ]),
  "journal-import-apple": new Set([
    "corpus",
    "journal",
    "apple-json",
  ]),
  "journal-complete": new Set([
    "corpus",
    "journal",
    "case-id",
    "apple-file",
    "deepseek-file",
    "http-requests",
  ]),
  "journal-fail": new Set([
    "corpus",
    "journal",
    "case-id",
    "reason-code",
    "http-requests",
  ]),
  "journal-status": new Set(["corpus", "journal"]),
  merge: new Set([
    "corpus",
    "journal",
    "output",
    "dataset-id",
    "dataset-title",
    "created-at",
    "margin-commit",
    "provider-model",
    "prompt-contract-version",
    "macos-version",
    "books-version",
    "locale",
    "private-count",
    "public-domain-count",
  ]),
});

function usage() {
  return `Margin evaluation preparation (local only)

Commands:
  capture-clipboard --output PATH
  xlsx-to-apple-json --corpus PATH [...] --xlsx PATH --output PATH
  validate         --corpus PATH [--corpus PATH ...]
  epub             --corpus PATH [...] --output PATH
  journal-init     --corpus PATH [...] --journal PATH
  journal-amend    --corpus PATH [...] --journal PATH
                   --amended-case-id ID [--amended-case-id ID ...]
  journal-reserve  --corpus PATH [...] --journal PATH --case-id ID
  journal-stage-deepseek --corpus PATH [...] --journal PATH --case-id ID
                   --deepseek-file PATH --http-requests 0..2
  journal-stage-deepseek-stdin --corpus PATH [...] --journal PATH --case-id ID
                   --http-requests 0..2
  journal-import-apple --corpus PATH [...] --journal PATH --apple-json PATH
  journal-complete --corpus PATH [...] --journal PATH --case-id ID
                   --apple-file PATH --deepseek-file PATH --http-requests 0..2
  journal-fail     --corpus PATH [...] --journal PATH --case-id ID
                   --reason-code network|provider|capture|cancelled|other
                   --http-requests 0..2
  journal-status   --corpus PATH [...] --journal PATH
  merge            --corpus PATH [...] --journal PATH --output PATH
                   --dataset-id ID --dataset-title TITLE [--created-at ISO8601]
                   --margin-commit COMMIT --provider-model MODEL
                   --prompt-contract-version VERSION
                   --macos-version VERSION --books-version VERSION --locale LOCALE
                   --private-count N --public-domain-count N

The tool never performs network requests or automatic retries. Candidate text is
read from files and written only to the private journal and merged private JSON.
`;
}

function captureClipboard(outputPath) {
  let text;
  try {
    text = execFileSync("/usr/bin/pbpaste", ["-Prefer", "txt"], {
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
    });
  } catch (_error) {
    throw new Preparation.PreparationError("Could not read plain text from the clipboard.");
  }
  if (text.trim() === "") {
    throw new Preparation.PreparationError("Clipboard candidate text must not be empty.");
  }

  const directory = path.dirname(outputPath);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporaryPath = path.join(
    directory,
    `.${path.basename(outputPath)}.${process.pid}.tmp`,
  );
  try {
    fs.writeFileSync(temporaryPath, text, { encoding: "utf8", mode: 0o600 });
    fs.renameSync(temporaryPath, outputPath);
    fs.chmodSync(outputPath, 0o600);
    execFileSync("/usr/bin/pbcopy", [], { input: "", encoding: "utf8" });
  } catch (_error) {
    try { fs.unlinkSync(temporaryPath); } catch (_cleanupError) { /* best effort */ }
    throw new Preparation.PreparationError("Could not save the private clipboard candidate.");
  }
}

function parseOptions(command, args) {
  const allowed = COMMAND_OPTIONS[command];
  if (!allowed) throw new Preparation.PreparationError("Unknown preparation command.");
  const options = { corpus: [], "amended-case-id": [] };
  for (let index = 0; index < args.length; index += 2) {
    const token = args[index];
    const value = args[index + 1];
    if (typeof token !== "string" || !token.startsWith("--") || value === undefined) {
      throw new Preparation.PreparationError("Command options must use --name value pairs.");
    }
    const name = token.slice(2);
    if (!allowed.has(name)) throw new Preparation.PreparationError("The command contains an unsupported option.");
    if (name === "corpus" || name === "amended-case-id") options[name].push(value);
    else if (Object.hasOwn(options, name)) {
      throw new Preparation.PreparationError("A command option was provided more than once.");
    } else options[name] = value;
  }
  return options;
}

function requireOption(options, name) {
  const value = options[name];
  if (typeof value !== "string" || value.trim() === "") {
    throw new Preparation.PreparationError(`Required option --${name} is missing.`);
  }
  return value;
}

function integerOption(options, name) {
  const raw = requireOption(options, name);
  if (!/^\d+$/.test(raw)) throw new Preparation.PreparationError(`Option --${name} must be an integer.`);
  return Number(raw);
}

function loadValidated(options) {
  return Preparation.loadAndValidateCorpora(options.corpus);
}

function loadVerifiedJournal(options, validated) {
  return Preparation.loadJournal(
    requireOption(options, "journal"),
    validated.corpusHash,
    validated.items.map((item) => item.id),
  );
}

function readCandidate(inputPath) {
  let text;
  try {
    text = fs.readFileSync(inputPath, "utf8");
  } catch (_error) {
    throw new Preparation.PreparationError("Could not read a candidate input file.");
  }
  if (text.trim() === "") throw new Preparation.PreparationError("Candidate input text must not be empty.");
  return text;
}

function readCandidateFromStdin() {
  let text;
  try {
    text = fs.readFileSync(0, "utf8");
  } catch (_error) {
    throw new Preparation.PreparationError("Could not read a candidate from standard input.");
  }
  if (text.trim() === "") {
    throw new Preparation.PreparationError("Candidate input text must not be empty.");
  }
  return text;
}

function safeStatus(journal) {
  return [
    `attempts=${journal.totals.marginLookupAttempts}/${journal.limits.maxMarginLookupAttempts}`,
    `http=${journal.totals.httpRequests}/${journal.limits.maxHttpRequests}`,
    `staged=${journal.totals.deepseekCollectedCases}`,
    `complete=${journal.totals.completeCases}/${journal.caseOrder.length}`,
    `failed=${journal.totals.failedCases}`,
  ].join(" ");
}

function run(command, options) {
  if (command === "capture-clipboard") {
    captureClipboard(requireOption(options, "output"));
    process.stdout.write("Captured one private clipboard candidate.\n");
    return;
  }
  const validated = loadValidated(options);
  switch (command) {
    case "validate":
      process.stdout.write(
        `Validated ${validated.items.length} source-only cases across ${validated.workCount} works.\n`,
      );
      return;
    case "xlsx-to-apple-json": {
      const document = Preparation.extractAppleImportFromXlsx(
        requireOption(options, "xlsx"),
        validated.items.map((item) => item.id),
      );
      Preparation.atomicWriteJSON(requireOption(options, "output"), document);
      process.stdout.write(`Extracted ${document.rows.length} Apple workbook rows.\n`);
      return;
    }
    case "epub":
      Preparation.createEpub(validated, requireOption(options, "output"));
      process.stdout.write(`Created a ${validated.items.length}-chapter source-only EPUB.\n`);
      return;
    case "journal-init": {
      const journal = Preparation.initializeJournal(
        requireOption(options, "journal"),
        validated,
      );
      process.stdout.write(`Journal ready. ${safeStatus(journal)}\n`);
      return;
    }
    case "journal-amend": {
      const next = Preparation.amendJournalForUntestedSources(
        requireOption(options, "journal"),
        validated,
        options["amended-case-id"],
      );
      process.stdout.write(`Journal amended for untested source-only cases. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-reserve": {
      const journalPath = requireOption(options, "journal");
      const journal = loadVerifiedJournal(options, validated);
      const next = Preparation.reserveLookupAttempt(
        journal,
        requireOption(options, "case-id"),
      );
      Preparation.saveJournal(journalPath, next, validated);
      process.stdout.write(`Lookup attempt reserved. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-complete": {
      const journalPath = requireOption(options, "journal");
      const journal = loadVerifiedJournal(options, validated);
      const next = Preparation.completeLookupAttempt(
        journal,
        requireOption(options, "case-id"),
        {
          apple: readCandidate(requireOption(options, "apple-file")),
          deepseek: readCandidate(requireOption(options, "deepseek-file")),
        },
        integerOption(options, "http-requests"),
      );
      Preparation.saveJournal(journalPath, next, validated);
      process.stdout.write(`Lookup attempt completed. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-stage-deepseek": {
      const journalPath = requireOption(options, "journal");
      const journal = loadVerifiedJournal(options, validated);
      const next = Preparation.stageDeepSeekCandidate(
        journal,
        requireOption(options, "case-id"),
        readCandidate(requireOption(options, "deepseek-file")),
        integerOption(options, "http-requests"),
      );
      Preparation.saveJournal(journalPath, next, validated);
      process.stdout.write(`DeepSeek result staged. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-stage-deepseek-stdin": {
      const journalPath = requireOption(options, "journal");
      const journal = loadVerifiedJournal(options, validated);
      const next = Preparation.stageDeepSeekCandidate(
        journal,
        requireOption(options, "case-id"),
        readCandidateFromStdin(),
        integerOption(options, "http-requests"),
      );
      Preparation.saveJournal(journalPath, next, validated);
      process.stdout.write(`DeepSeek result staged. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-import-apple": {
      const journalPath = requireOption(options, "journal");
      const journal = loadVerifiedJournal(options, validated);
      const input = Preparation.readJSONFile(requireOption(options, "apple-json"));
      const next = Preparation.importAppleCandidates(journal, input);
      Preparation.atomicBackupPrivateJSON(journalPath, "pre-apple-import");
      Preparation.saveJournal(journalPath, next, validated);
      process.stdout.write(`Apple results imported after a private backup. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-fail": {
      const journalPath = requireOption(options, "journal");
      const journal = loadVerifiedJournal(options, validated);
      const next = Preparation.failLookupAttempt(
        journal,
        requireOption(options, "case-id"),
        requireOption(options, "reason-code"),
        integerOption(options, "http-requests"),
      );
      Preparation.saveJournal(journalPath, next, validated);
      process.stdout.write(`Lookup attempt marked failed. ${safeStatus(next)}\n`);
      return;
    }
    case "journal-status": {
      const journal = loadVerifiedJournal(options, validated);
      process.stdout.write(`Journal status: ${safeStatus(journal)}\n`);
      return;
    }
    case "merge": {
      const journal = loadVerifiedJournal(options, validated);
      const createdAt = options["created-at"] || new Date().toISOString();
      const privateCount = integerOption(options, "private-count");
      const publicDomainCount = integerOption(options, "public-domain-count");
      const output = Preparation.mergeCompleteJournal(
        validated,
        journal,
        {
          id: requireOption(options, "dataset-id"),
          title: requireOption(options, "dataset-title"),
          createdAt,
        },
        {
          corpusHash: validated.corpusHash,
          marginCommit: requireOption(options, "margin-commit"),
          providerModel: requireOption(options, "provider-model"),
          promptContractVersion: requireOption(options, "prompt-contract-version"),
          appleBaseline: {
            macOSVersion: requireOption(options, "macos-version"),
            booksVersion: requireOption(options, "books-version"),
            locale: requireOption(options, "locale"),
          },
          caseCounts: {
            private: privateCount,
            publicDomain: publicDomainCount,
            total: privateCount + publicDomainCount,
          },
        },
      );
      Preparation.atomicWriteJSON(requireOption(options, "output"), output);
      process.stdout.write(`Merged ${output.dataset.cases.length} complete cases into evaluator schema v3.\n`);
      return;
    }
    default:
      throw new Preparation.PreparationError("Unknown preparation command.");
  }
}

function main(argv) {
  if (argv.length === 0 || argv[0] === "--help" || argv[0] === "-h") {
    process.stdout.write(usage());
    return 0;
  }
  const command = argv[0];
  try {
    const options = parseOptions(command, argv.slice(1));
    run(command, options);
    return 0;
  } catch (error) {
    const message = error instanceof Preparation.PreparationError
      ? error.message
      : "Unexpected local preparation failure.";
    process.stderr.write(`Preparation failed: ${message}\n`);
    return 1;
  }
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));

module.exports = { main, parseOptions, run, usage };
