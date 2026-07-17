const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const Core = require("../core.js");

function sampleDataset() {
  return {
    schemaVersion: 1,
    dataset: {
      id: "private-reading-v1",
      title: "Private reading sample",
      createdAt: "2026-07-15T00:00:00Z",
      cases: [
        {
          id: "history-01",
          category: "biography-history",
          source: {
            text: "The private source text must never enter a public export.",
            attribution: {
              title: "Private test",
              creator: "Local only",
              sourceURL: "",
              license: "private",
            },
          },
          candidates: {
            apple: { text: "Apple private translation." },
            deepseek: { text: "DeepSeek private translation." },
          },
        },
        {
          id: "fiction-01",
          category: "fiction-dialogue",
          source: {
            text: "A second private sentence keeps the test honest.",
            attribution: {
              title: "Private test",
              creator: "Local only",
              sourceURL: "",
              license: "private",
            },
          },
          candidates: {
            apple: { text: "Apple second translation." },
            deepseek: { text: "DeepSeek second translation." },
          },
        },
      ],
    },
  };
}

function sampleDatasetV2() {
  const input = sampleDataset();
  input.schemaVersion = 2;
  input.dataset.id = "secret-held-out-40";
  input.dataset.title = "Secret ten-book comparison";
  input.dataset.metadata = {
    corpusHash: "sha256-secret-corpus-fingerprint",
    marginCommit: "2b34cb4",
    providerModel: "deepseek-v4-flash",
    promptContractVersion: "passage-semantic-v1",
    appleBaseline: {
      macOSVersion: "26.5",
      booksVersion: "8.4",
      locale: "en_US-to-zh_Hans",
    },
    caseCounts: {
      private: 1,
      publicDomain: 1,
      total: 2,
    },
  };
  input.dataset.cases[0].source.attribution.title = "Secret book title";
  input.dataset.cases[0].source.attribution.creator = "Secret Author";
  return input;
}

function sampleDatasetV3() {
  const input = sampleDatasetV2();
  input.schemaVersion = 3;
  input.dataset.id = "secret-held-out-normalized-40";
  input.dataset.metadata.normalization = {
    contractVersion: "blind-display-v1",
    scriptConverter: "Foundation Traditional-Simplified",
    targetLanguage: "zh-Hans-CN",
  };
  input.dataset.cases.forEach((item, index) => {
    for (const provider of ["apple", "deepseek"]) {
      const rawText = item.candidates[provider].text;
      item.candidates[provider] = {
        rawText,
        displayText: `${rawText} Display ${index + 1}.`,
        normalization: {
          whitespaceAdjusted: false,
          scriptConverted: provider === "apple" && index === 0,
          quoteGlyphsAdjusted: false,
          outerQuoteAdjusted: provider === "apple",
        },
      };
    }
  });
  return input;
}

function officialDatasetV3() {
  const input = sampleDatasetV3();
  const templates = input.dataset.cases;
  input.dataset.id = "official-held-out-v010";
  input.dataset.title = "Margin v0.1.0 held-out evaluation";
  input.dataset.cases = Array.from({ length: 40 }, (_unused, index) => {
    const item = JSON.parse(JSON.stringify(templates[index % templates.length]));
    item.id = `official-${String(index + 1).padStart(2, "0")}`;
    item.source.text = `${item.source.text} [${index + 1}]`;
    return item;
  });
  input.dataset.metadata.caseCounts = {
    private: 12,
    publicDomain: 28,
    total: 40,
  };
  return input;
}

const completeResponse = {
  accuracy: "tie",
  naturalness: "A",
  ambiguity: "not-applicable",
  preference: "A",
  majorErrors: [],
  note: "",
};

test("validates a prepared blind dataset", () => {
  const dataset = Core.validateDataset(sampleDataset());
  assert.equal(dataset.dataset.cases.length, 2);
  assert.equal(dataset.dataset.cases[0].id, "history-01");
});

test("accepts schema v2 run metadata while keeping schema v1 imports", () => {
  const legacy = Core.validateDataset(sampleDataset());
  assert.equal(legacy.schemaVersion, 1);
  assert.equal(Object.hasOwn(legacy.dataset, "metadata"), false);

  const current = Core.validateDataset(sampleDatasetV2());
  assert.equal(current.schemaVersion, 2);
  assert.equal(current.dataset.metadata.providerModel, "deepseek-v4-flash");
  assert.equal(current.dataset.metadata.appleBaseline.locale, "en_US-to-zh_Hans");

  const badCounts = sampleDatasetV2();
  badCounts.dataset.metadata.caseCounts.total = 40;
  assert.throws(() => Core.validateDataset(badCounts), /sample counts/i);

  const missingMetadata = sampleDatasetV2();
  delete missingMetadata.dataset.metadata;
  assert.throws(() => Core.validateDataset(missingMetadata), /metadata/i);

  const normalized = Core.validateDataset(sampleDatasetV3());
  assert.equal(normalized.schemaVersion, 3);
  assert.equal(
    normalized.dataset.metadata.normalization.contractVersion,
    "blind-display-v1",
  );
  assert.equal(
    normalized.dataset.cases[0].candidates.apple.normalization.scriptConverted,
    true,
  );
});

test("rejects duplicate IDs and missing candidate text", () => {
  const duplicate = sampleDataset();
  duplicate.dataset.cases[1].id = "history-01";
  assert.throws(() => Core.validateDataset(duplicate), /unique/i);

  const missing = sampleDataset();
  missing.dataset.cases[0].candidates.apple.text = "";
  assert.throws(() => Core.validateDataset(missing), /candidate/i);

  const privateCategory = sampleDataset();
  privateCategory.dataset.cases[0].category = "notes-about-a-specific-book";
  assert.throws(() => Core.validateDataset(privateCategory), /category/i);
});

test("creates stable A/B assignments that survive serialization", () => {
  const dataset = Core.validateDataset(sampleDataset());
  const session = Core.createSession(dataset, () => 0.9, "2026-07-15T01:00:00Z");

  assert.deepEqual(session.assignments["history-01"], { A: "deepseek", B: "apple" });
  assert.deepEqual(session.assignments["fiction-01"], { A: "deepseek", B: "apple" });

  const restored = Core.restoreSession(dataset, JSON.stringify(session));
  assert.deepEqual(restored.assignments, session.assignments);
  assert.equal(restored.datasetFingerprint, Core.fingerprintDataset(dataset));
});

test("autosaved drafts survive restoration without counting as completed scores", () => {
  const dataset = Core.validateDataset(sampleDatasetV2());
  let session = Core.createSession(dataset, () => 0.9, "2026-07-15T01:00:00Z");
  session = Core.recordDraft(session, "history-01", {
    accuracy: "A",
    naturalness: null,
    ambiguity: "not-applicable",
    preference: null,
    majorErrors: ["B"],
    note: "unfinished local note",
  });

  const restored = Core.restoreSession(dataset, JSON.stringify(session));
  assert.equal(restored.drafts["history-01"].accuracy, "A");
  assert.equal(restored.drafts["history-01"].note, "unfinished local note");
  assert.equal(Core.isComplete(dataset, restored), false);

  const saved = Core.recordResponse(restored, "history-01", completeResponse);
  assert.equal(Object.hasOwn(saved.drafts, "history-01"), false);
  assert.deepEqual(saved.assignments, session.assignments);

  const edited = Core.recordDraft(saved, "history-01", {
    ...completeResponse,
    naturalness: "B",
  });
  assert.equal(Object.hasOwn(edited.responses, "history-01"), false);
  assert.equal(edited.drafts["history-01"].naturalness, "B");
});

test("restores legacy session v1 data by adding an empty draft collection", () => {
  const dataset = Core.validateDataset(sampleDataset());
  const session = Core.createSession(dataset, () => 0.1);
  session.sessionVersion = 1;
  delete session.drafts;

  const restored = Core.restoreSession(dataset, session);
  assert.equal(restored.sessionVersion, 2);
  assert.deepEqual(restored.drafts, {});
});

test("refuses progress from a different dataset", () => {
  const first = Core.validateDataset(sampleDataset());
  const session = Core.createSession(first, () => 0.1);
  const changed = sampleDataset();
  changed.dataset.cases[0].source.text += " Changed.";

  assert.throws(
    () => Core.restoreSession(Core.validateDataset(changed), JSON.stringify(session)),
    /different dataset/i,
  );
});

test("schema v3 fingerprint includes raw, display, and normalization contract data", () => {
  const original = Core.validateDataset(sampleDatasetV3());
  const session = Core.createSession(original, () => 0.1);

  const changedDisplay = sampleDatasetV3();
  changedDisplay.dataset.cases[0].candidates.apple.displayText += " Changed.";
  assert.throws(
    () => Core.restoreSession(Core.validateDataset(changedDisplay), session),
    /different dataset/i,
  );

  const changedRaw = sampleDatasetV3();
  changedRaw.dataset.cases[0].candidates.apple.rawText += " Changed.";
  assert.throws(
    () => Core.restoreSession(Core.validateDataset(changedRaw), session),
    /different dataset/i,
  );

  const changedContract = sampleDatasetV3();
  changedContract.dataset.metadata.normalization.contractVersion = "blind-display-v2";
  assert.throws(
    () => Core.restoreSession(Core.validateDataset(changedContract), session),
    /different dataset/i,
  );
});

test("refuses a corrupted finalized session with missing responses", () => {
  const dataset = Core.validateDataset(sampleDataset());
  const session = Core.createSession(dataset, () => 0.1);
  session.finalized = true;
  session.finalizedAt = "2026-07-15T02:00:00Z";

  assert.throws(() => Core.restoreSession(dataset, JSON.stringify(session)), /finalized.*complete/i);
});

test("requires every response before finalizing and locks finalized sessions", () => {
  const dataset = Core.validateDataset(sampleDataset());
  let session = Core.createSession(dataset, () => 0.1);
  session = Core.recordResponse(session, "history-01", completeResponse);

  assert.equal(Core.isComplete(dataset, session), false);
  assert.throws(() => Core.finalizeSession(dataset, session), /every item/i);

  session = Core.recordResponse(session, "fiction-01", completeResponse);
  session = Core.finalizeSession(dataset, session, "2026-07-15T02:00:00Z");
  assert.equal(session.finalized, true);
  assert.throws(
    () => Core.recordResponse(session, "history-01", completeResponse),
    /finalized/i,
  );
});

test("reveals providers only after finalization", () => {
  const dataset = Core.validateDataset(sampleDataset());
  let session = Core.createSession(dataset, () => 0.1);

  assert.throws(() => Core.revealCase(dataset, session, "history-01"), /finalized/i);

  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);
  const revealed = Core.revealCase(dataset, session, "history-01");
  assert.equal(revealed.providers.A, "apple");
  assert.equal(revealed.providers.B, "deepseek");
});

test("schema v3 exposes only display text before reveal and raw text afterward", () => {
  const dataset = Core.validateDataset(sampleDatasetV3());
  let session = Core.createSession(dataset, () => 0.1);
  const blind = Core.blindCase(dataset, session, "history-01");
  assert.match(blind.candidates.A, /Display 1/);
  assert.equal(Object.hasOwn(blind, "rawCandidates"), false);
  assert.equal(Object.hasOwn(blind, "normalization"), false);
  assert.doesNotMatch(JSON.stringify(blind), /Apple private translation\\./);

  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);
  const revealed = Core.revealCase(dataset, session, "history-01");
  assert.equal(revealed.rawCandidates.A, "Apple private translation.");
  assert.equal(revealed.normalization.A.scriptConverted, true);
});

test("computes release metrics from the hidden provider assignments", () => {
  const dataset = Core.validateDataset(sampleDataset());
  let session = Core.createSession(dataset, () => 0.1);

  session = Core.recordResponse(session, "history-01", {
    accuracy: "tie",
    naturalness: "B",
    ambiguity: "B",
    preference: "B",
    majorErrors: [],
    note: "DeepSeek reads more naturally.",
  });
  session = Core.recordResponse(session, "fiction-01", {
    accuracy: "B",
    naturalness: "A",
    ambiguity: "not-applicable",
    preference: "A",
    majorErrors: ["A"],
    note: "Apple has the major error in this assignment.",
  });
  session = Core.finalizeSession(dataset, session);

  const summary = Core.computeSummary(dataset, session);
  assert.equal(summary.metrics.deepseekNaturalnessPreferred.count, 1);
  assert.equal(summary.metrics.deepseekNaturalnessPreferred.rate, 0.5);
  assert.equal(summary.metrics.deepseekAccuracyEqualOrBetter.count, 2);
  assert.equal(summary.metrics.deepseekAccuracyEqualOrBetter.rate, 1);
  assert.equal(summary.metrics.deepseekMajorSemanticErrors, 0);
  assert.equal(summary.officialEligibility.eligible, false);
  assert.equal(summary.officialEligibility.status, "unofficial");
  assert.equal(summary.releaseGate.naturalness.requiredCount, 24);
  assert.equal(summary.releaseGate.naturalness.denominator, 40);
  assert.equal(summary.releaseGate.status, "unofficial");
  assert.equal(summary.releaseGate.passed, null);
});

test("applies the v0.1.0 gate only to the exact official schema v3 40-case composition", () => {
  const dataset = Core.validateDataset(officialDatasetV3());
  let session = Core.createSession(dataset, () => 0.1);
  dataset.dataset.cases.forEach((item, index) => {
    session = Core.recordResponse(session, item.id, {
      accuracy: index < 36 ? "tie" : "A",
      naturalness: index < 24 ? "B" : "A",
      ambiguity: "not-applicable",
      preference: "B",
      majorErrors: index === 0 ? ["B"] : [],
      note: "",
    });
  });
  session = Core.finalizeSession(dataset, session);

  const passing = Core.computeSummary(dataset, session);
  assert.equal(passing.officialEligibility.eligible, true);
  assert.equal(passing.officialEligibility.status, "official");
  assert.equal(passing.releaseGate.status, "pass");
  assert.equal(passing.releaseGate.passed, true);
  assert.equal(passing.releaseGate.naturalness.requiredCount, 24);
  assert.equal(passing.releaseGate.accuracy.requiredCount, 36);
  assert.equal(passing.releaseGate.majorSemanticErrors.maximum, 1);

  const wrongComposition = officialDatasetV3();
  wrongComposition.dataset.metadata.caseCounts.private = 20;
  wrongComposition.dataset.metadata.caseCounts.publicDomain = 20;
  const unofficialDataset = Core.validateDataset(wrongComposition);
  let unofficialSession = Core.createSession(unofficialDataset, () => 0.1);
  for (const item of unofficialDataset.dataset.cases) {
    unofficialSession = Core.recordResponse(unofficialSession, item.id, {
      ...completeResponse,
      accuracy: "B",
      naturalness: "B",
      preference: "B",
    });
  }
  unofficialSession = Core.finalizeSession(unofficialDataset, unofficialSession);
  const unofficial = Core.computeSummary(unofficialDataset, unofficialSession);
  assert.equal(unofficial.metrics.deepseekNaturalnessPreferred.count, 40);
  assert.equal(unofficial.officialEligibility.eligible, false);
  assert.equal(unofficial.releaseGate.status, "unofficial");
  assert.equal(unofficial.releaseGate.passed, null);

  const legacyRaw = officialDatasetV3();
  legacyRaw.schemaVersion = 1;
  delete legacyRaw.dataset.metadata;
  legacyRaw.dataset.cases.forEach((item) => {
    for (const provider of ["apple", "deepseek"]) {
      item.candidates[provider] = { text: item.candidates[provider].rawText };
    }
  });
  const legacyDataset = Core.validateDataset(legacyRaw);
  let legacySession = Core.createSession(legacyDataset, () => 0.1);
  for (const item of legacyDataset.dataset.cases) {
    legacySession = Core.recordResponse(legacySession, item.id, {
      ...completeResponse,
      accuracy: "B",
      naturalness: "B",
      preference: "B",
    });
  }
  legacySession = Core.finalizeSession(legacyDataset, legacySession);
  const legacy = Core.computeSummary(legacyDataset, legacySession);
  assert.equal(legacy.metrics.deepseekNaturalnessPreferred.count, 40);
  assert.equal(legacy.officialEligibility.eligible, false);
  assert.equal(legacy.releaseGate.status, "unofficial");
});

test("exports detailed JSON and escaped CSV locally", () => {
  const raw = sampleDataset();
  raw.dataset.cases[0].source.text = "A source with a comma, and a \"quote\".";
  raw.dataset.cases[0].candidates.apple.text = "=HYPERLINK(\"https://example.invalid\")";
  const dataset = Core.validateDataset(raw);
  let session = Core.createSession(dataset, () => 0.1);
  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);

  const detail = Core.createDetailedExport(dataset, session);
  assert.equal(detail.exportVersion, 2);
  assert.equal(detail.schemaVersion, 1);
  assert.equal(detail.dataset.cases[0].source.text, raw.dataset.cases[0].source.text);
  const csv = Core.toDetailedCSV(dataset, session);
  assert.match(csv, /"A source with a comma, and a ""quote""\."/);
  assert.match(csv, /"'=HYPERLINK\(""https:\/\/example\.invalid""\)"/);
});

test("schema v3 detailed exports retain raw and display text while hygiene stays separate", () => {
  const dataset = Core.validateDataset(sampleDatasetV3());
  let session = Core.createSession(dataset, () => 0.1);
  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);

  const detail = Core.createDetailedExport(dataset, session);
  assert.equal(detail.exportVersion, 2);
  assert.equal(detail.schemaVersion, 3);
  assert.equal(
    detail.dataset.cases[0].candidates.apple.rawText,
    "Apple private translation.",
  );
  assert.match(detail.dataset.cases[0].candidates.apple.displayText, /Display 1/);
  const summary = Core.computeSummary(dataset, session);
  assert.equal(summary.outputHygiene.apple.scriptConvertedCases, 1);
  assert.equal(summary.outputHygiene.apple.outerQuoteAdjustedCases, 2);
  assert.equal(Object.hasOwn(summary.releaseGate, "outputHygiene"), false);

  const csv = Core.toDetailedCSV(dataset, session);
  assert.match(csv, /"display_candidate_a","raw_candidate_a"/);
  assert.match(csv, /Apple private translation\./);
});

test("public summary contains aggregates but no source or candidate text", () => {
  const dataset = Core.validateDataset(sampleDatasetV2());
  let session = Core.createSession(dataset, () => 0.1);
  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);

  const output = JSON.stringify(Core.createPublicSummary(dataset, session));
  assert.doesNotMatch(output, /private source text/i);
  assert.doesNotMatch(output, /Apple private translation/i);
  assert.doesNotMatch(output, /DeepSeek private translation/i);
  assert.doesNotMatch(output, /private-reading-v1|fnv1a-/i);
  assert.doesNotMatch(output, /secret-held-out-40|secret ten-book|secret book title|secret author/i);
  assert.doesNotMatch(output, /sha256-secret-corpus-fingerprint/i);
  assert.doesNotMatch(output, /datasetFingerprint|corpusHash|\"dataset\"|\"source\"|\"candidates\"/i);
  assert.match(output, /deepseek-v4-flash|passage-semantic-v1|en_US-to-zh_Hans/);
  assert.match(output, /deepseekNaturalnessPreferred/);
});

test("schema v3 public summary includes only aggregate output hygiene", () => {
  const dataset = Core.validateDataset(sampleDatasetV3());
  let session = Core.createSession(dataset, () => 0.1);
  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);

  const output = JSON.stringify(Core.createPublicSummary(dataset, session));
  assert.match(output, /outputHygiene|scriptConvertedCases|outerQuoteAdjustedCases/);
  assert.match(output, /blind-display-v1|Foundation Traditional-Simplified/);
  assert.doesNotMatch(output, /Apple private translation|Display 1/);
});

test("public summary field names cannot disclose identity-bearing records", () => {
  const dataset = Core.validateDataset(sampleDatasetV2());
  let session = Core.createSession(dataset, () => 0.1);
  for (const item of dataset.dataset.cases) {
    session = Core.recordResponse(session, item.id, completeResponse);
  }
  session = Core.finalizeSession(dataset, session);

  const forbidden = /(title|author|creator|source|candidate|dataset.*id|fingerprint|corpushash)/i;
  function visit(value) {
    if (!value || typeof value !== "object") return;
    for (const [key, child] of Object.entries(value)) {
      assert.doesNotMatch(key, forbidden);
      visit(child);
    }
  }
  visit(Core.createPublicSummary(dataset, session));
});

test("static page declares a no-network CSP and implementation has no network calls", () => {
  const root = path.resolve(__dirname, "..");
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const app = fs.readFileSync(path.join(root, "app.js"), "utf8");
  const core = fs.readFileSync(path.join(root, "core.js"), "utf8");

  assert.match(html, /connect-src 'none'/);
  assert.match(html, /default-src 'none'/);
  assert.doesNotMatch(`${app}\n${core}`, /\bfetch\s*\(|XMLHttpRequest|WebSocket|EventSource/);
});

test("interface exposes the proofreader keyboard workflow and autosave hooks", () => {
  const root = path.resolve(__dirname, "..");
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const app = fs.readFileSync(path.join(root, "app.js"), "utf8");

  assert.match(html, /id="key-ledger"/);
  assert.match(html, /<kbd>1<\/kbd>[\s\S]*<kbd>2<\/kbd>[\s\S]*<kbd>3<\/kbd>/);
  assert.match(html, /<kbd>4<\/kbd>[\s\S]*<kbd>M<\/kbd>[\s\S]*<kbd>Enter<\/kbd>/);
  assert.match(app, /recordDraft/);
  assert.match(app, /addEventListener\("keydown"/);
});

test("checked-in corpus is source-only and every item documents public-domain provenance", () => {
  const corpusPath = path.resolve(__dirname, "../corpora/public-domain.json");
  const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));

  assert.ok(corpus.corpus.items.length > 0);
  for (const item of corpus.corpus.items) {
    assert.equal(Object.hasOwn(item, "candidates"), false);
    assert.match(item.attribution.license, /public domain/i);
    assert.match(
      item.attribution.sourceURL,
      /^https:\/\/www\.gutenberg\.org\/(?:ebooks|cache\/epub)\//,
    );
  }
});

test("interface demo is explicitly self-authored and not represented as provider evidence", () => {
  const demoPath = path.resolve(__dirname, "../fixtures/demo-session.json");
  const demo = Core.validateDataset(JSON.parse(fs.readFileSync(demoPath, "utf8")));
  const readme = fs.readFileSync(path.resolve(__dirname, "../README.md"), "utf8");

  for (const item of demo.dataset.cases) {
    assert.match(item.source.attribution.license, /self-authored/i);
  }
  assert.match(readme, /provider\s+labels are synthetic placeholders/i);
  assert.match(readme, /not evidence about either translation service/i);
});
