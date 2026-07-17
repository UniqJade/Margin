#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const Preparation = require("./preparation.cjs");

const DEVELOPMENT_CASES = 10;
const DEVELOPMENT_WORKS = 5;
const CASES_PER_WORK = 2;
const MAX_ROUNDS = 3;
const MAX_HTTP_REQUESTS = 60;
const MIN_FIRST_ATTEMPT_ALIGNMENT = 8;

function fail(message) {
  throw new Error(message);
}

function normalizedIdentity(text) {
  return text.normalize("NFKC").replace(/\s+/gu, " ").trim().toLocaleLowerCase("en-US");
}

function readJSON(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function validateDevelopmentCorpus(document, heldOutDocument) {
  const corpus = document?.corpus;
  const heldOut = heldOutDocument?.corpus;
  if (document?.schemaVersion !== 1 || !corpus || !Array.isArray(corpus.items)) {
    fail("Development corpus must use the source corpus schema version 1.");
  }
  if (!heldOut || !Array.isArray(heldOut.items)) fail("Held-out corpus is invalid.");
  if (corpus.items.length !== DEVELOPMENT_CASES) {
    fail(`Development corpus must contain exactly ${DEVELOPMENT_CASES} cases.`);
  }

  const heldOutWorks = new Set(heldOut.items.map((item) => item.workId));
  const heldOutTexts = new Set(heldOut.items.map((item) => normalizedIdentity(item.text)));
  const ids = new Set();
  const texts = new Set();
  const workCounts = new Map();

  for (const item of corpus.items) {
    if (!item || typeof item !== "object" || Array.isArray(item)) fail("Each development case must be an object.");
    if (Object.hasOwn(item, "candidates")) fail("Development corpus must remain source-only.");
    if (typeof item.id !== "string" || item.id.trim() === "" || ids.has(item.id)) fail("Development case IDs must be unique.");
    ids.add(item.id);
    if (!Preparation.CATEGORIES.includes(item.category)) fail("Development cases must use a standard evaluation category.");
    if (typeof item.text !== "string" || item.text.trim() === "") fail("Development cases must contain source text.");
    const identity = normalizedIdentity(item.text);
    if (texts.has(identity) || heldOutTexts.has(identity)) fail("Development text must be unique and absent from held-out corpora.");
    texts.add(identity);
    const sentenceCount = Preparation.countSentences(item.text);
    if (sentenceCount < 2 || sentenceCount > 4) fail("Development cases must contain 2–4 sentences.");
    if ([...item.text].length > 2_000) fail("Development cases must not exceed 2,000 Unicode characters.");
    if (typeof item.workId !== "string" || item.workId.trim() === "") fail("Development cases must identify their work.");
    if (heldOutWorks.has(item.workId)) fail("Development works must be separate from the public held-out works.");
    workCounts.set(item.workId, (workCounts.get(item.workId) || 0) + 1);
    const attribution = item.attribution;
    if (!attribution || !/public domain/i.test(attribution.license || "")) fail("Every development case must document public-domain status.");
    if (!/^https:\/\/www\.gutenberg\.org\/(?:ebooks|cache\/epub)\//u.test(attribution.sourceURL || "")) {
      fail("Every development case must link to its Project Gutenberg source.");
    }
  }

  if (workCounts.size !== DEVELOPMENT_WORKS || [...workCounts.values()].some((count) => count !== CASES_PER_WORK)) {
    fail(`Development corpus must use ${DEVELOPMENT_WORKS} works with ${CASES_PER_WORK} cases each.`);
  }
  return { corpusId: corpus.id, cases: ids.size, works: workCounts.size };
}

function summarizeRun(document, expectedCorpusId) {
  if (document?.schemaVersion !== 1 || document.corpusId !== expectedCorpusId || !Array.isArray(document.rounds)) {
    fail("Development result metadata does not match the locked corpus.");
  }
  if (document.rounds.length === 0 || document.rounds.length > MAX_ROUNDS) {
    fail(`Development results must contain between 1 and ${MAX_ROUNDS} rounds.`);
  }

  let totalHTTP = 0;
  let latest = null;
  const roundNumbers = new Set();
  for (const round of document.rounds) {
    if (!Number.isInteger(round.round) || round.round < 1 || round.round > MAX_ROUNDS || roundNumbers.has(round.round)) {
      fail("Development round numbers must be unique integers from 1 through 3.");
    }
    roundNumbers.add(round.round);
    if (!Array.isArray(round.cases) || round.cases.length !== DEVELOPMENT_CASES) {
      fail(`Every completed development round must contain exactly ${DEVELOPMENT_CASES} cases.`);
    }
    const caseIDs = new Set();
    for (const item of round.cases) {
      if (typeof item.id !== "string" || item.id === "" || caseIDs.has(item.id)) fail("Round case IDs must be unique.");
      caseIDs.add(item.id);
      if (typeof item.finalNatural !== "boolean" || typeof item.firstAttemptAlignment !== "boolean") {
        fail("Round outcomes must record finalNatural and firstAttemptAlignment booleans.");
      }
      if (!Number.isInteger(item.httpRequests) || item.httpRequests < 1 || item.httpRequests > 2) {
        fail("Each development case must consume one or two HTTP requests.");
      }
      totalHTTP += item.httpRequests;
    }
    latest = round;
  }
  if (totalHTTP > MAX_HTTP_REQUESTS) fail(`Development runs must not exceed ${MAX_HTTP_REQUESTS} HTTP requests.`);

  const naturalSuccesses = latest.cases.filter((item) => item.finalNatural).length;
  const firstAttemptAlignments = latest.cases.filter((item) => item.firstAttemptAlignment).length;
  return {
    rounds: document.rounds.length,
    totalHTTP,
    naturalSuccesses,
    firstAttemptAlignments,
    passed: naturalSuccesses === DEVELOPMENT_CASES && firstAttemptAlignments >= MIN_FIRST_ATTEMPT_ALIGNMENT,
  };
}

function parseOptions(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!flag?.startsWith("--") || value === undefined) fail("Options must use --name VALUE pairs.");
    options[flag.slice(2)] = value;
  }
  return options;
}

function main(argv) {
  const [command, ...optionArguments] = argv;
  const options = parseOptions(optionArguments);
  if (!command || !options.corpus || !options["held-out"]) {
    fail("Usage: development-gate.cjs validate|report --corpus PATH --held-out PATH [--results PATH]");
  }
  const validation = validateDevelopmentCorpus(readJSON(options.corpus), readJSON(options["held-out"]));
  if (command === "validate") {
    process.stdout.write(`Development corpus valid: cases=${validation.cases} works=${validation.works}\n`);
    return;
  }
  if (command === "report") {
    if (!options.results) fail("report requires --results PATH.");
    const summary = summarizeRun(readJSON(options.results), validation.corpusId);
    process.stdout.write(`Development gate: ${summary.passed ? "PASS" : "FAIL"} rounds=${summary.rounds} http=${summary.totalHTTP}/${MAX_HTTP_REQUESTS} natural=${summary.naturalSuccesses}/${DEVELOPMENT_CASES} aligned=${summary.firstAttemptAlignments}/${DEVELOPMENT_CASES}\n`);
    if (!summary.passed) process.exitCode = 2;
    return;
  }
  fail("Unknown development gate command.");
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`Development gate error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  constants: { DEVELOPMENT_CASES, DEVELOPMENT_WORKS, CASES_PER_WORK, MAX_ROUNDS, MAX_HTTP_REQUESTS, MIN_FIRST_ATTEMPT_ALIGNMENT },
  summarizeRun,
  validateDevelopmentCorpus,
};
