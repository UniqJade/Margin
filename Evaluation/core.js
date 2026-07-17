(function attachMarginEvaluation(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.MarginEvaluation = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function createMarginEvaluation() {
  "use strict";

  const DATASET_SCHEMA_VERSIONS = new Set([1, 2, 3]);
  const SESSION_VERSION = 2;
  const PROVIDERS = ["apple", "deepseek"];
  const LABELS = ["A", "B"];
  const CATEGORIES = new Set([
    "biography-history",
    "fiction-dialogue",
    "news-general-nonfiction",
    "idiom-ambiguity-complex-syntax",
  ]);
  const COMPARISON_CHOICES = new Set(["A", "tie", "B"]);
  const AMBIGUITY_CHOICES = new Set(["A", "tie", "B", "not-applicable"]);

  function fail(message) {
    throw new Error(message);
  }

  function requiredString(value, path, allowEmpty = false) {
    if (typeof value !== "string" || (!allowEmpty && value.trim() === "")) {
      fail(`${path} must be ${allowEmpty ? "a string" : "a non-empty string"}.`);
    }
    return value;
  }

  function requiredNonNegativeInteger(value, path) {
    if (!Number.isInteger(value) || value < 0) {
      fail(`${path} must be a non-negative integer.`);
    }
    return value;
  }

  function requiredBoolean(value, path) {
    if (typeof value !== "boolean") fail(`${path} must be a boolean.`);
    return value;
  }

  function validateNormalizationMetadata(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      fail("dataset.metadata.normalization must be an object for schemaVersion 3.");
    }
    const targetLanguage = requiredString(
      value.targetLanguage,
      "dataset.metadata.normalization.targetLanguage",
    );
    if (targetLanguage !== "zh-Hans-CN") {
      fail("dataset.metadata.normalization.targetLanguage must be zh-Hans-CN.");
    }
    return {
      contractVersion: requiredString(
        value.contractVersion,
        "dataset.metadata.normalization.contractVersion",
      ),
      scriptConverter: requiredString(
        value.scriptConverter,
        "dataset.metadata.normalization.scriptConverter",
      ),
      targetLanguage,
    };
  }

  function validateRunMetadata(value, caseCount, schemaVersion) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      fail("dataset.metadata must be an object for schemaVersion 2 or 3.");
    }
    if (!value.appleBaseline || typeof value.appleBaseline !== "object"
      || Array.isArray(value.appleBaseline)) {
      fail("dataset.metadata.appleBaseline must be an object.");
    }
    if (!value.caseCounts || typeof value.caseCounts !== "object" || Array.isArray(value.caseCounts)) {
      fail("dataset.metadata.caseCounts must be an object.");
    }
    const metadata = {
      corpusHash: requiredString(value.corpusHash, "dataset.metadata.corpusHash"),
      marginCommit: requiredString(value.marginCommit, "dataset.metadata.marginCommit"),
      providerModel: requiredString(value.providerModel, "dataset.metadata.providerModel"),
      promptContractVersion: requiredString(
        value.promptContractVersion,
        "dataset.metadata.promptContractVersion",
      ),
      appleBaseline: {
        macOSVersion: requiredString(
          value.appleBaseline.macOSVersion,
          "dataset.metadata.appleBaseline.macOSVersion",
        ),
        booksVersion: requiredString(
          value.appleBaseline.booksVersion,
          "dataset.metadata.appleBaseline.booksVersion",
        ),
        locale: requiredString(
          value.appleBaseline.locale,
          "dataset.metadata.appleBaseline.locale",
        ),
      },
      caseCounts: {
        private: requiredNonNegativeInteger(
          value.caseCounts.private,
          "dataset.metadata.caseCounts.private",
        ),
        publicDomain: requiredNonNegativeInteger(
          value.caseCounts.publicDomain,
          "dataset.metadata.caseCounts.publicDomain",
        ),
        total: requiredNonNegativeInteger(
          value.caseCounts.total,
          "dataset.metadata.caseCounts.total",
        ),
      },
    };
    if (schemaVersion === 3) {
      metadata.normalization = validateNormalizationMetadata(value.normalization);
    }
    if (metadata.caseCounts.private + metadata.caseCounts.publicDomain !== caseCount
      || metadata.caseCounts.total !== caseCount) {
      fail("Run metadata sample counts must equal the number of evaluation cases.");
    }
    return metadata;
  }

  function validateDataset(input) {
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      fail("Dataset must be a JSON object.");
    }
    if (!DATASET_SCHEMA_VERSIONS.has(input.schemaVersion)) {
      fail("Unsupported dataset schemaVersion; expected 1, 2, or 3.");
    }
    const sourceDataset = input.dataset;
    if (!sourceDataset || typeof sourceDataset !== "object" || Array.isArray(sourceDataset)) {
      fail("dataset must be an object.");
    }
    if (!Array.isArray(sourceDataset.cases) || sourceDataset.cases.length === 0) {
      fail("dataset.cases must contain at least one evaluation item.");
    }

    const ids = new Set();
    const cases = sourceDataset.cases.map((item, index) => {
      const path = `dataset.cases[${index}]`;
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        fail(`${path} must be an object.`);
      }
      const id = requiredString(item.id, `${path}.id`);
      if (ids.has(id)) fail("Evaluation case IDs must be unique.");
      ids.add(id);

      const category = requiredString(item.category, `${path}.category`);
      if (!CATEGORIES.has(category)) {
        fail(`${path}.category must use one of Margin's four standard evaluation categories.`);
      }
      if (!item.source || typeof item.source !== "object") {
        fail(`${path}.source must be an object.`);
      }
      const attribution = item.source.attribution;
      if (!attribution || typeof attribution !== "object") {
        fail(`${path}.source.attribution must document provenance and licensing.`);
      }
      const source = {
        text: requiredString(item.source.text, `${path}.source.text`),
        attribution: {
          title: requiredString(attribution.title, `${path}.source.attribution.title`),
          creator: requiredString(attribution.creator, `${path}.source.attribution.creator`),
          sourceURL: requiredString(
            attribution.sourceURL,
            `${path}.source.attribution.sourceURL`,
            true,
          ),
          license: requiredString(attribution.license, `${path}.source.attribution.license`),
        },
      };

      if (!item.candidates || typeof item.candidates !== "object") {
        fail(`${path}.candidates must contain Apple and DeepSeek candidate text.`);
      }
      const candidates = {};
      for (const provider of PROVIDERS) {
        const candidate = item.candidates[provider];
        if (!candidate || typeof candidate !== "object") {
          fail(`${path}.candidates.${provider} candidate is required.`);
        }
        if (input.schemaVersion === 3) {
          const normalization = candidate.normalization;
          if (!normalization || typeof normalization !== "object" || Array.isArray(normalization)) {
            fail(`${path}.candidates.${provider}.normalization must be an object.`);
          }
          candidates[provider] = {
            rawText: requiredString(
              candidate.rawText,
              `${path}.candidates.${provider}.rawText candidate`,
            ),
            displayText: requiredString(
              candidate.displayText,
              `${path}.candidates.${provider}.displayText candidate`,
            ),
            normalization: {
              whitespaceAdjusted: requiredBoolean(
                normalization.whitespaceAdjusted,
                `${path}.candidates.${provider}.normalization.whitespaceAdjusted`,
              ),
              scriptConverted: requiredBoolean(
                normalization.scriptConverted,
                `${path}.candidates.${provider}.normalization.scriptConverted`,
              ),
              quoteGlyphsAdjusted: requiredBoolean(
                normalization.quoteGlyphsAdjusted,
                `${path}.candidates.${provider}.normalization.quoteGlyphsAdjusted`,
              ),
              outerQuoteAdjusted: requiredBoolean(
                normalization.outerQuoteAdjusted,
                `${path}.candidates.${provider}.normalization.outerQuoteAdjusted`,
              ),
            },
          };
        } else {
          candidates[provider] = {
            text: requiredString(
              candidate.text,
              `${path}.candidates.${provider}.text candidate`,
            ),
          };
        }
      }

      return { id, category, source, candidates };
    });

    const normalizedDataset = {
      id: requiredString(sourceDataset.id, "dataset.id"),
      title: requiredString(sourceDataset.title, "dataset.title"),
      createdAt: requiredString(sourceDataset.createdAt, "dataset.createdAt"),
      cases,
    };
    if (input.schemaVersion >= 2) {
      normalizedDataset.metadata = validateRunMetadata(
        sourceDataset.metadata,
        cases.length,
        input.schemaVersion,
      );
    }

    return {
      schemaVersion: input.schemaVersion,
      dataset: normalizedDataset,
    };
  }

  function fingerprintDataset(dataset) {
    const normalized = validateDataset(dataset);
    const serialized = JSON.stringify(normalized);
    let hash = 0x811c9dc5;
    for (let index = 0; index < serialized.length; index += 1) {
      hash ^= serialized.charCodeAt(index);
      hash = Math.imul(hash, 0x01000193);
    }
    return `fnv1a-${(hash >>> 0).toString(16).padStart(8, "0")}`;
  }

  function defaultRandom() {
    if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
      const value = new Uint32Array(1);
      crypto.getRandomValues(value);
      return value[0] / 0x100000000;
    }
    return Math.random();
  }

  function createSession(dataset, random = defaultRandom, now = new Date().toISOString()) {
    const normalized = validateDataset(dataset);
    const assignments = {};
    for (const item of normalized.dataset.cases) {
      assignments[item.id] = random() < 0.5
        ? { A: "apple", B: "deepseek" }
        : { A: "deepseek", B: "apple" };
    }
    return {
      sessionVersion: SESSION_VERSION,
      datasetFingerprint: fingerprintDataset(normalized),
      createdAt: now,
      finalized: false,
      finalizedAt: null,
      currentIndex: 0,
      assignments,
      responses: {},
      drafts: {},
    };
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function validateSessionShape(dataset, session) {
    if (!session || typeof session !== "object" || Array.isArray(session)) {
      fail("Saved progress is not a session object.");
    }
    if (![1, SESSION_VERSION].includes(session.sessionVersion)) {
      fail("Saved progress uses an unsupported session version.");
    }
    const normalizedSession = clone(session);
    if (normalizedSession.sessionVersion === 1) {
      normalizedSession.sessionVersion = SESSION_VERSION;
      normalizedSession.drafts = {};
    }
    if (typeof normalizedSession.finalized !== "boolean") {
      fail("Saved progress has an invalid finalized state.");
    }
    if (typeof normalizedSession.createdAt !== "string" || normalizedSession.createdAt.trim() === "") {
      fail("Saved progress has no creation timestamp.");
    }
    if (!normalizedSession.assignments || typeof normalizedSession.assignments !== "object" || Array.isArray(normalizedSession.assignments)) {
      fail("Saved progress has no valid A/B assignments.");
    }
    if (normalizedSession.datasetFingerprint !== fingerprintDataset(dataset)) {
      fail("Saved progress belongs to a different dataset.");
    }
    if (!normalizedSession.responses || typeof normalizedSession.responses !== "object" || Array.isArray(normalizedSession.responses)) {
      fail("Saved progress has no valid response collection.");
    }
    if (!normalizedSession.drafts || typeof normalizedSession.drafts !== "object" || Array.isArray(normalizedSession.drafts)) {
      fail("Saved progress has no valid draft collection.");
    }
    if (!Number.isInteger(normalizedSession.currentIndex)
      || normalizedSession.currentIndex < 0
      || normalizedSession.currentIndex >= dataset.dataset.cases.length) {
      fail("Saved progress has an invalid current item.");
    }
    for (const item of dataset.dataset.cases) {
      const assignment = normalizedSession.assignments && normalizedSession.assignments[item.id];
      if (!assignment || !PROVIDERS.includes(assignment.A) || !PROVIDERS.includes(assignment.B)) {
        fail(`Saved progress has no valid A/B assignment for ${item.id}.`);
      }
      if (assignment.A === assignment.B) {
        fail(`Saved progress repeats a provider for ${item.id}.`);
      }
      if (normalizedSession.responses && normalizedSession.responses[item.id]) {
        validateResponse(normalizedSession.responses[item.id]);
      }
      if (normalizedSession.drafts && normalizedSession.drafts[item.id]) {
        validateDraft(normalizedSession.drafts[item.id]);
      }
    }
    if (normalizedSession.finalized) {
      if (typeof normalizedSession.finalizedAt !== "string" || normalizedSession.finalizedAt.trim() === "") {
        fail("A finalized session must record when it was finalized.");
      }
      if (!dataset.dataset.cases.every((item) => normalizedSession.responses[item.id])) {
        fail("A finalized session must contain a complete response for every item.");
      }
    }
    return normalizedSession;
  }

  function restoreSession(dataset, serialized) {
    const normalized = validateDataset(dataset);
    let parsed;
    try {
      parsed = typeof serialized === "string" ? JSON.parse(serialized) : clone(serialized);
    } catch (_error) {
      fail("Saved progress is not valid JSON.");
    }
    return clone(validateSessionShape(normalized, parsed));
  }

  function storageKey(dataset) {
    return `margin-evaluation:${fingerprintDataset(dataset)}`;
  }

  function validateResponse(response) {
    if (!response || typeof response !== "object" || Array.isArray(response)) {
      fail("A response must be an object.");
    }
    if (!COMPARISON_CHOICES.has(response.accuracy)) {
      fail("Choose which candidate is more accurate, or mark them equal.");
    }
    if (!COMPARISON_CHOICES.has(response.naturalness)) {
      fail("Choose which candidate reads more naturally, or mark them equal.");
    }
    if (!AMBIGUITY_CHOICES.has(response.ambiguity)) {
      fail("Evaluate ambiguity handling or mark it not applicable.");
    }
    if (!COMPARISON_CHOICES.has(response.preference)) {
      fail("Choose the candidate you would prefer while reading, or mark them equal.");
    }
    if (!Array.isArray(response.majorErrors)
      || response.majorErrors.some((label) => !LABELS.includes(label))
      || new Set(response.majorErrors).size !== response.majorErrors.length) {
      fail("Major semantic errors must be a unique list containing A and/or B.");
    }
    if (typeof response.note !== "string") fail("The optional note must be text.");
    return response;
  }

  function validateDraft(draft) {
    if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
      fail("A draft must be an object.");
    }
    const optionalChoice = (value, choices, message) => {
      if (value != null && !choices.has(value)) fail(message);
      return value == null ? null : value;
    };
    const majorErrors = draft.majorErrors == null ? [] : draft.majorErrors;
    if (!Array.isArray(majorErrors)
      || majorErrors.some((label) => !LABELS.includes(label))
      || new Set(majorErrors).size !== majorErrors.length) {
      fail("Draft major semantic errors must be a unique list containing A and/or B.");
    }
    if (draft.note != null && typeof draft.note !== "string") {
      fail("The draft note must be text.");
    }
    return {
      accuracy: optionalChoice(draft.accuracy, COMPARISON_CHOICES, "Draft accuracy is invalid."),
      naturalness: optionalChoice(
        draft.naturalness,
        COMPARISON_CHOICES,
        "Draft naturalness is invalid.",
      ),
      ambiguity: optionalChoice(
        draft.ambiguity,
        AMBIGUITY_CHOICES,
        "Draft ambiguity is invalid.",
      ),
      preference: optionalChoice(
        draft.preference,
        COMPARISON_CHOICES,
        "Draft preference is invalid.",
      ),
      majorErrors: [...majorErrors],
      note: draft.note == null ? "" : draft.note,
    };
  }

  function recordDraft(session, caseID, draft) {
    if (session.finalized) fail("This session is finalized and cannot be edited.");
    if (!Object.prototype.hasOwnProperty.call(session.assignments, caseID)) {
      fail(`Unknown evaluation case: ${caseID}.`);
    }
    const next = clone(session);
    next.drafts[caseID] = clone(validateDraft(draft));
    delete next.responses[caseID];
    return next;
  }

  function recordResponse(session, caseID, response) {
    if (session.finalized) fail("This session is finalized and cannot be edited.");
    if (!Object.prototype.hasOwnProperty.call(session.assignments, caseID)) {
      fail(`Unknown evaluation case: ${caseID}.`);
    }
    const next = clone(session);
    next.responses[caseID] = clone(validateResponse(response));
    delete next.drafts[caseID];
    return next;
  }

  function setCurrentIndex(dataset, session, index) {
    if (session.finalized) fail("This session is finalized and cannot be navigated for editing.");
    if (!Number.isInteger(index) || index < 0 || index >= dataset.dataset.cases.length) {
      fail("Evaluation item index is out of range.");
    }
    const next = clone(session);
    next.currentIndex = index;
    return next;
  }

  function isComplete(dataset, session) {
    return dataset.dataset.cases.every((item) => {
      try {
        validateResponse(session.responses[item.id]);
        return true;
      } catch (_error) {
        return false;
      }
    });
  }

  function finalizeSession(dataset, session, now = new Date().toISOString()) {
    if (session.finalized) return clone(session);
    if (!isComplete(dataset, session)) {
      fail("Score every item before finalizing the session.");
    }
    const next = clone(session);
    next.finalized = true;
    next.finalizedAt = now;
    return next;
  }

  function caseByID(dataset, caseID) {
    const item = dataset.dataset.cases.find((candidate) => candidate.id === caseID);
    if (!item) fail(`Unknown evaluation case: ${caseID}.`);
    return item;
  }

  function candidateDisplayText(candidate) {
    return Object.hasOwn(candidate, "displayText") ? candidate.displayText : candidate.text;
  }

  function candidateRawText(candidate) {
    return Object.hasOwn(candidate, "rawText") ? candidate.rawText : candidate.text;
  }

  function candidateNormalization(candidate) {
    return Object.hasOwn(candidate, "normalization")
      ? clone(candidate.normalization)
      : {
        whitespaceAdjusted: false,
        scriptConverted: false,
        quoteGlyphsAdjusted: false,
        outerQuoteAdjusted: false,
      };
  }

  function blindCase(dataset, session, caseID) {
    const item = caseByID(dataset, caseID);
    const assignment = session.assignments[caseID];
    return {
      id: item.id,
      category: item.category,
      source: clone(item.source),
      candidates: {
        A: candidateDisplayText(item.candidates[assignment.A]),
        B: candidateDisplayText(item.candidates[assignment.B]),
      },
      response: session.responses[caseID] ? clone(session.responses[caseID]) : null,
    };
  }

  function revealCase(dataset, session, caseID) {
    if (!session.finalized) fail("Provider identities remain hidden until the session is finalized.");
    const item = caseByID(dataset, caseID);
    const blind = blindCase(dataset, session, caseID);
    return {
      ...blind,
      providers: clone(session.assignments[caseID]),
      rawCandidates: {
        A: candidateRawText(item.candidates[session.assignments[caseID].A]),
        B: candidateRawText(item.candidates[session.assignments[caseID].B]),
      },
      normalization: {
        A: candidateNormalization(item.candidates[session.assignments[caseID].A]),
        B: candidateNormalization(item.candidates[session.assignments[caseID].B]),
      },
    };
  }

  function labelForProvider(assignment, provider) {
    return assignment.A === provider ? "A" : "B";
  }

  function emptyMetrics(total) {
    return {
      total,
      deepseekNaturalnessPreferred: { count: 0, total, rate: 0 },
      deepseekAccuracyEqualOrBetter: { count: 0, total, rate: 0 },
      deepseekReadingPreferred: { count: 0, total, rate: 0 },
      deepseekMajorSemanticErrors: 0,
    };
  }

  function finishRates(metrics) {
    for (const key of [
      "deepseekNaturalnessPreferred",
      "deepseekAccuracyEqualOrBetter",
      "deepseekReadingPreferred",
    ]) {
      metrics[key].rate = metrics[key].total === 0
        ? 0
        : metrics[key].count / metrics[key].total;
    }
    return metrics;
  }

  function addToMetrics(metrics, response, assignment) {
    const deepseekLabel = labelForProvider(assignment, "deepseek");
    if (response.naturalness === deepseekLabel) {
      metrics.deepseekNaturalnessPreferred.count += 1;
    }
    if (response.accuracy === "tie" || response.accuracy === deepseekLabel) {
      metrics.deepseekAccuracyEqualOrBetter.count += 1;
    }
    if (response.preference === deepseekLabel) {
      metrics.deepseekReadingPreferred.count += 1;
    }
    if (response.majorErrors.includes(deepseekLabel)) {
      metrics.deepseekMajorSemanticErrors += 1;
    }
  }

  function officialEligibility(dataset) {
    const expected = {
      schemaVersion: 3,
      total: 40,
      private: 12,
      publicDomain: 28,
    };
    const metadata = dataset.schemaVersion >= 2 ? dataset.dataset.metadata : null;
    const reasons = [];
    if (dataset.schemaVersion !== expected.schemaVersion) {
      reasons.push("The official v0.1.0 gate requires dataset schemaVersion 3.");
    }
    if (dataset.dataset.cases.length !== expected.total) {
      reasons.push("The official v0.1.0 gate requires exactly 40 cases.");
    }
    if (metadata && (metadata.caseCounts.private !== expected.private
      || metadata.caseCounts.publicDomain !== expected.publicDomain
      || metadata.caseCounts.total !== expected.total)) {
      reasons.push("The official v0.1.0 gate requires 12 private and 28 public-domain cases.");
    }
    return {
      eligible: reasons.length === 0,
      status: reasons.length === 0 ? "official" : "unofficial",
      expected,
      reasons,
    };
  }

  function computeSummary(dataset, session) {
    if (!session.finalized) fail("Finalize the session before computing revealed results.");
    const metrics = emptyMetrics(dataset.dataset.cases.length);
    const grouped = {};

    for (const item of dataset.dataset.cases) {
      const response = session.responses[item.id];
      const assignment = session.assignments[item.id];
      addToMetrics(metrics, response, assignment);
      if (!grouped[item.category]) grouped[item.category] = emptyMetrics(0);
      grouped[item.category].total += 1;
      for (const key of [
        "deepseekNaturalnessPreferred",
        "deepseekAccuracyEqualOrBetter",
        "deepseekReadingPreferred",
      ]) {
        grouped[item.category][key].total += 1;
      }
      addToMetrics(grouped[item.category], response, assignment);
    }

    finishRates(metrics);
    for (const category of Object.values(grouped)) finishRates(category);
    const eligibility = officialEligibility(dataset);
    const releaseGate = {
      naturalness: {
        requiredCount: 24,
        denominator: 40,
        passed: eligibility.eligible
          ? metrics.deepseekNaturalnessPreferred.count >= 24
          : null,
      },
      accuracy: {
        requiredCount: 36,
        denominator: 40,
        passed: eligibility.eligible
          ? metrics.deepseekAccuracyEqualOrBetter.count >= 36
          : null,
      },
      majorSemanticErrors: {
        maximum: 1,
        passed: eligibility.eligible ? metrics.deepseekMajorSemanticErrors <= 1 : null,
      },
    };
    releaseGate.status = eligibility.eligible
      && releaseGate.naturalness.passed
      && releaseGate.accuracy.passed
      && releaseGate.majorSemanticErrors.passed
      ? "pass"
      : eligibility.eligible ? "fail" : "unofficial";
    releaseGate.passed = eligibility.eligible ? releaseGate.status === "pass" : null;
    const output = {
      metrics,
      categories: grouped,
      officialEligibility: eligibility,
      releaseGate,
    };
    if (dataset.schemaVersion === 3) {
      output.outputHygiene = computeOutputHygiene(dataset);
    }
    return output;
  }

  function computeOutputHygiene(dataset) {
    const totals = {};
    for (const provider of PROVIDERS) {
      totals[provider] = {
        whitespaceAdjustedCases: 0,
        scriptConvertedCases: 0,
        quoteGlyphsAdjustedCases: 0,
        outerQuoteAdjustedCases: 0,
      };
    }
    for (const item of dataset.dataset.cases) {
      for (const provider of PROVIDERS) {
        const flags = candidateNormalization(item.candidates[provider]);
        if (flags.whitespaceAdjusted) totals[provider].whitespaceAdjustedCases += 1;
        if (flags.scriptConverted) totals[provider].scriptConvertedCases += 1;
        if (flags.quoteGlyphsAdjusted) totals[provider].quoteGlyphsAdjustedCases += 1;
        if (flags.outerQuoteAdjusted) totals[provider].outerQuoteAdjustedCases += 1;
      }
    }
    return totals;
  }

  function createDetailedExport(dataset, session) {
    if (!session.finalized) fail("Finalize the session before exporting revealed results.");
    return {
      exportVersion: 2,
      kind: "margin-detailed-evaluation",
      exportedAt: new Date().toISOString(),
      schemaVersion: dataset.schemaVersion,
      datasetFingerprint: session.datasetFingerprint,
      dataset: clone(dataset.dataset),
      session: clone(session),
      summary: computeSummary(dataset, session),
    };
  }

  function createPublicSummary(dataset, session) {
    if (!session.finalized) fail("Finalize the session before exporting a public summary.");
    const output = {
      exportVersion: 2,
      kind: "margin-public-evaluation-summary",
      exportedAt: new Date().toISOString(),
      sampleCount: dataset.dataset.cases.length,
      finalizedAt: session.finalizedAt,
      summary: computeSummary(dataset, session),
      limitations: [
        "Single evaluator",
        "Evaluator is the project author",
        "Provider identities were hidden until finalization",
      ],
    };
    if (dataset.schemaVersion >= 2) {
      const metadata = dataset.dataset.metadata;
      output.run = {
        marginCommit: metadata.marginCommit,
        providerModel: metadata.providerModel,
        promptContractVersion: metadata.promptContractVersion,
        appleBaseline: clone(metadata.appleBaseline),
        caseCounts: clone(metadata.caseCounts),
      };
      if (dataset.schemaVersion === 3) output.run.normalization = clone(metadata.normalization);
    }
    return output;
  }

  function csvCell(value) {
    let text = value == null ? "" : String(value);
    if (/^[=+\-@]/.test(text)) text = `'${text}`;
    return `"${text.replaceAll('"', '""')}"`;
  }

  function toDetailedCSV(dataset, session) {
    if (!session.finalized) fail("Finalize the session before exporting revealed results.");
    const header = [
      "case_id", "category", "source", "source_title", "source_creator", "source_license",
      "display_candidate_a", "raw_candidate_a", "provider_a",
      "display_candidate_b", "raw_candidate_b", "provider_b",
      "accuracy", "naturalness", "ambiguity", "preference", "major_errors", "note",
    ];
    const rows = [header.map(csvCell).join(",")];
    for (const item of dataset.dataset.cases) {
      const revealed = revealCase(dataset, session, item.id);
      const response = session.responses[item.id];
      rows.push([
        item.id,
        item.category,
        item.source.text,
        item.source.attribution.title,
        item.source.attribution.creator,
        item.source.attribution.license,
        revealed.candidates.A,
        revealed.rawCandidates.A,
        revealed.providers.A,
        revealed.candidates.B,
        revealed.rawCandidates.B,
        revealed.providers.B,
        response.accuracy,
        response.naturalness,
        response.ambiguity,
        response.preference,
        response.majorErrors.join("|"),
        response.note,
      ].map(csvCell).join(","));
    }
    return `${rows.join("\n")}\n`;
  }

  return Object.freeze({
    validateDataset,
    fingerprintDataset,
    createSession,
    restoreSession,
    storageKey,
    recordDraft,
    recordResponse,
    setCurrentIndex,
    isComplete,
    finalizeSession,
    blindCase,
    revealCase,
    computeSummary,
    createDetailedExport,
    createPublicSummary,
    toDetailedCSV,
  });
});
