"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const Gate = require("../tools/development-gate.cjs");

const root = path.resolve(__dirname, "..");
const development = JSON.parse(fs.readFileSync(path.join(root, "corpora/development-public-domain.json"), "utf8"));
const heldOut = JSON.parse(fs.readFileSync(path.join(root, "corpora/public-domain.json"), "utf8"));

function outcomes({ natural = 10, aligned = 8, requests = 2 } = {}) {
  return development.corpus.items.map((item, index) => ({
    id: item.id,
    finalNatural: index < natural,
    firstAttemptAlignment: index < aligned,
    httpRequests: requests,
  }));
}

test("development corpus is ten source-only cases from five works separate from held-out", () => {
  assert.deepEqual(
    Gate.validateDevelopmentCorpus(development, heldOut),
    { corpusId: "margin-public-domain-development-v1", cases: 10, works: 5 },
  );
});

test("development corpus rejects held-out works and candidate output", () => {
  const reusedWork = structuredClone(development);
  reusedWork.corpus.items[0].workId = heldOut.corpus.items[0].workId;
  assert.throws(() => Gate.validateDevelopmentCorpus(reusedWork, heldOut), /separate from.*held-out/i);

  const withCandidate = structuredClone(development);
  withCandidate.corpus.items[0].candidates = { deepseek: { text: "private" } };
  assert.throws(() => Gate.validateDevelopmentCorpus(withCandidate, heldOut), /source-only/i);
});

test("development gate requires ten natural results and eight first-attempt alignments", () => {
  const passing = Gate.summarizeRun({
    schemaVersion: 1,
    corpusId: development.corpus.id,
    rounds: [{ round: 1, cases: outcomes() }],
  }, development.corpus.id);
  assert.equal(passing.passed, true);
  assert.equal(passing.totalHTTP, 20);

  const weakAlignment = Gate.summarizeRun({
    schemaVersion: 1,
    corpusId: development.corpus.id,
    rounds: [{ round: 1, cases: outcomes({ aligned: 7 }) }],
  }, development.corpus.id);
  assert.equal(weakAlignment.passed, false);

  const failedNatural = Gate.summarizeRun({
    schemaVersion: 1,
    corpusId: development.corpus.id,
    rounds: [{ round: 1, cases: outcomes({ natural: 9 }) }],
  }, development.corpus.id);
  assert.equal(failedNatural.passed, false);
});

test("development gate enforces three rounds and sixty HTTP requests", () => {
  const threeRounds = {
    schemaVersion: 1,
    corpusId: development.corpus.id,
    rounds: [1, 2, 3].map((round) => ({ round, cases: outcomes() })),
  };
  const summary = Gate.summarizeRun(threeRounds, development.corpus.id);
  assert.equal(summary.totalHTTP, 60);

  const fourthRound = structuredClone(threeRounds);
  fourthRound.rounds.push({ round: 4, cases: outcomes({ requests: 1 }) });
  assert.throws(() => Gate.summarizeRun(fourthRound, development.corpus.id), /between 1 and 3 rounds/i);
});
