(function runEvaluationApp() {
  "use strict";

  const Core = globalThis.MarginEvaluation;
  const LAST_DATASET_KEY = "margin-evaluation:last-dataset";

  const elements = {
    importView: document.querySelector("#import-view"),
    evaluationView: document.querySelector("#evaluation-view"),
    resultsView: document.querySelector("#results-view"),
    datasetFile: document.querySelector("#dataset-file"),
    clearProgress: document.querySelector("#clear-progress"),
    notice: document.querySelector("#notice"),
    railFill: document.querySelector("#rail-fill"),
    railCount: document.querySelector("#rail-count"),
    caseCategory: document.querySelector("#case-category"),
    casePosition: document.querySelector("#case-position"),
    savedStatus: document.querySelector("#saved-status"),
    majorErrorStatus: document.querySelector("#major-error-status"),
    sourceText: document.querySelector("#source-text"),
    sourceCredit: document.querySelector("#source-credit"),
    candidateA: document.querySelector("#candidate-a"),
    candidateB: document.querySelector("#candidate-b"),
    scoreForm: document.querySelector("#score-form"),
    formError: document.querySelector("#form-error"),
    previousCase: document.querySelector("#previous-case"),
    saveNext: document.querySelector("#save-next"),
    finalize: document.querySelector("#finalize"),
    finalizeHelp: document.querySelector("#finalize-help"),
    metricGrid: document.querySelector("#metric-grid"),
    releaseGate: document.querySelector("#release-gate"),
    revealList: document.querySelector("#reveal-list"),
    exportDetailJSON: document.querySelector("#export-detail-json"),
    exportDetailCSV: document.querySelector("#export-detail-csv"),
    exportPublicJSON: document.querySelector("#export-public-json"),
  };

  let dataset = null;
  let session = null;
  let activeQuestion = null;

  function showNotice(message, isError = false) {
    elements.notice.textContent = message;
    elements.notice.classList.toggle("error", isError);
    elements.notice.hidden = false;
  }

  function hideNotice() {
    elements.notice.hidden = true;
    elements.notice.textContent = "";
    elements.notice.classList.remove("error");
  }

  function safeStorage(action, fallback = null) {
    try {
      return action();
    } catch (_error) {
      showNotice(
        "Browser-local storage is unavailable. You can continue, but reload recovery is disabled.",
        true,
      );
      return fallback;
    }
  }

  function persist() {
    if (!dataset || !session) return false;
    return safeStorage(() => {
      localStorage.setItem(LAST_DATASET_KEY, JSON.stringify(dataset));
      localStorage.setItem(Core.storageKey(dataset), JSON.stringify(session));
      return true;
    }, false);
  }

  function activateDataset(candidateDataset, restoredSession = null) {
    dataset = Core.validateDataset(candidateDataset);
    session = restoredSession || Core.createSession(dataset);
    hideNotice();
    const persisted = persist();
    elements.clearProgress.hidden = false;
    if (session.finalized) {
      renderResults();
    } else {
      renderCase();
    }
    return persisted;
  }

  function restoreLastSession() {
    const serializedDataset = safeStorage(() => localStorage.getItem(LAST_DATASET_KEY));
    if (!serializedDataset) return;
    try {
      const restoredDataset = Core.validateDataset(JSON.parse(serializedDataset));
      const serializedSession = safeStorage(() => localStorage.getItem(Core.storageKey(restoredDataset)));
      if (!serializedSession) return;
      const persisted = activateDataset(
        restoredDataset,
        Core.restoreSession(restoredDataset, serializedSession),
      );
      if (persisted) {
        showNotice(session.finalized ? "Finalized local session restored." : "Local progress restored.");
      }
    } catch (error) {
      showNotice(`Saved progress could not be restored: ${error.message}`, true);
    }
  }

  function setView(view) {
    elements.importView.hidden = view !== "import";
    elements.evaluationView.hidden = view !== "evaluation";
    elements.resultsView.hidden = view !== "results";
  }

  function completedCount() {
    return dataset.dataset.cases.filter((item) => session.responses[item.id]).length;
  }

  function updateProgress() {
    const completed = completedCount();
    const total = dataset.dataset.cases.length;
    const ratio = total === 0 ? 0 : completed / total;
    elements.railFill.style.height = `${ratio * 100}%`;
    elements.railFill.style.width = `${ratio * 100}%`;
    elements.railCount.textContent = session.finalized
      ? `${total} / ${total} · final`
      : `${completed} / ${total} scored`;
  }

  function clearForm() {
    elements.scoreForm.reset();
    elements.formError.hidden = true;
    elements.formError.textContent = "";
  }

  function populateResponse(response) {
    if (!response) return;
    for (const field of ["accuracy", "naturalness", "ambiguity", "preference"]) {
      const input = elements.scoreForm.querySelector(
        `input[name="${field}"][value="${response[field]}"]`,
      );
      if (input) input.checked = true;
    }
    for (const label of response.majorErrors) {
      const input = elements.scoreForm.querySelector(`input[name="majorErrors"][value="${label}"]`);
      if (input) input.checked = true;
    }
    elements.scoreForm.elements.note.value = response.note;
  }

  function setActiveQuestion(fieldset) {
    for (const question of elements.scoreForm.querySelectorAll("[data-question]")) {
      question.classList.toggle("is-active", question === fieldset);
    }
    activeQuestion = fieldset && fieldset.dataset.question ? fieldset : null;
  }

  function majorErrorDescription(labels) {
    if (labels.length === 0) return "No major semantic error marked";
    if (labels.length === 2) return "Major semantic error marked for A and B";
    return `Major semantic error marked for ${labels[0]}`;
  }

  function updateMajorErrorStatus() {
    const labels = [...elements.scoreForm.querySelectorAll('input[name="majorErrors"]:checked')]
      .map((input) => input.value);
    elements.majorErrorStatus.textContent = majorErrorDescription(labels);
  }

  function renderCase() {
    setView("evaluation");
    updateProgress();
    const total = dataset.dataset.cases.length;
    const index = Math.min(session.currentIndex, total - 1);
    const item = dataset.dataset.cases[index];
    const blind = Core.blindCase(dataset, session, item.id);
    const saved = session.responses[item.id];
    const draft = session.drafts[item.id];

    elements.caseCategory.textContent = item.category.replaceAll("-", " ");
    elements.casePosition.textContent = `Passage ${index + 1} of ${total}`;
    elements.savedStatus.textContent = saved
      ? "Score filed locally"
      : draft ? "Draft saved locally" : "Not scored";
    elements.sourceText.textContent = blind.source.text;
    const attribution = blind.source.attribution;
    elements.sourceCredit.textContent = [
      attribution.creator,
      attribution.title,
      attribution.license,
    ].filter(Boolean).join(" · ");
    elements.candidateA.textContent = blind.candidates.A;
    elements.candidateB.textContent = blind.candidates.B;

    clearForm();
    populateResponse(draft || saved);
    updateMajorErrorStatus();
    elements.previousCase.disabled = index === 0;
    elements.saveNext.textContent = index === total - 1 ? "Save score" : "Save & next";

    const complete = Core.isComplete(dataset, session);
    elements.finalize.disabled = !complete;
    elements.finalizeHelp.textContent = complete
      ? "All items are scored. Finalizing locks the session and reveals providers."
      : `${total - completedCount()} item${total - completedCount() === 1 ? " remains" : "s remain"}.`;
    const firstQuestion = elements.scoreForm.querySelector('[data-question="accuracy"]');
    setActiveQuestion(firstQuestion);
    firstQuestion.focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function selectedValue(name) {
    const input = elements.scoreForm.querySelector(`input[name="${name}"]:checked`);
    return input ? input.value : null;
  }

  function responseFromForm() {
    const response = {
      accuracy: selectedValue("accuracy"),
      naturalness: selectedValue("naturalness"),
      ambiguity: selectedValue("ambiguity"),
      preference: selectedValue("preference"),
      majorErrors: [...elements.scoreForm.querySelectorAll('input[name="majorErrors"]:checked')]
        .map((input) => input.value),
      note: elements.scoreForm.elements.note.value.trim(),
    };
    const missing = ["accuracy", "naturalness", "ambiguity", "preference"]
      .filter((field) => !response[field]);
    if (missing.length > 0) {
      throw new Error("Complete all four comparison questions before saving this passage.");
    }
    return response;
  }

  function draftFromForm() {
    return {
      accuracy: selectedValue("accuracy"),
      naturalness: selectedValue("naturalness"),
      ambiguity: selectedValue("ambiguity"),
      preference: selectedValue("preference"),
      majorErrors: [...elements.scoreForm.querySelectorAll('input[name="majorErrors"]:checked')]
        .map((input) => input.value),
      note: elements.scoreForm.elements.note.value,
    };
  }

  function autosaveDraft() {
    if (!dataset || !session || session.finalized) return;
    const item = dataset.dataset.cases[session.currentIndex];
    session = Core.recordDraft(session, item.id, draftFromForm());
    persist();
    elements.savedStatus.textContent = "Draft saved locally";
    elements.finalize.disabled = true;
    const remaining = dataset.dataset.cases.length - completedCount();
    elements.finalizeHelp.textContent = `${remaining} item${remaining === 1 ? " remains" : "s remain"}.`;
    updateProgress();
    updateMajorErrorStatus();
  }

  function cycleMajorErrors() {
    const boxes = [...elements.scoreForm.querySelectorAll('input[name="majorErrors"]')];
    const signature = boxes.filter((input) => input.checked).map((input) => input.value).join("");
    const next = { "": "A", A: "B", B: "AB", AB: "" }[signature] ?? "";
    for (const input of boxes) input.checked = next.includes(input.value);
    autosaveDraft();
  }

  function chooseByNumber(key) {
    if (!activeQuestion) return false;
    const values = { "1": "A", "2": "tie", "3": "B" };
    let value = values[key];
    if (key === "4" && activeQuestion.dataset.question === "ambiguity") {
      value = "not-applicable";
    }
    if (!value) return false;
    const input = activeQuestion.querySelector(`input[value="${value}"]`);
    if (!input) return false;
    input.checked = true;
    autosaveDraft();
    return true;
  }

  function handleScoreKeyboard(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    if (event.target instanceof HTMLTextAreaElement) return;
    if (event.target instanceof HTMLButtonElement) return;
    if (["1", "2", "3", "4"].includes(event.key) && chooseByNumber(event.key)) {
      event.preventDefault();
      return;
    }
    if (event.key.toLowerCase() === "m") {
      event.preventDefault();
      cycleMajorErrors();
      return;
    }
    if (event.key === "Enter") {
      event.preventDefault();
      elements.scoreForm.requestSubmit();
    }
  }

  function saveCurrentResponse(event) {
    event.preventDefault();
    try {
      const item = dataset.dataset.cases[session.currentIndex];
      session = Core.recordResponse(session, item.id, responseFromForm());
      if (session.currentIndex < dataset.dataset.cases.length - 1) {
        session = Core.setCurrentIndex(dataset, session, session.currentIndex + 1);
      }
      persist();
      renderCase();
    } catch (error) {
      elements.formError.textContent = error.message;
      elements.formError.hidden = false;
    }
  }

  function goPrevious() {
    if (session.currentIndex === 0) return;
    session = Core.setCurrentIndex(dataset, session, session.currentIndex - 1);
    persist();
    renderCase();
  }

  function formatPercent(rate) {
    return `${Math.round(rate * 100)}%`;
  }

  function addMetric(label, value, detail) {
    const article = document.createElement("article");
    article.className = "metric";
    const name = document.createElement("p");
    name.className = "card-label";
    name.textContent = label;
    const number = document.createElement("p");
    number.className = "metric-value";
    number.textContent = value;
    const explanation = document.createElement("p");
    explanation.className = "metric-detail";
    explanation.textContent = detail;
    article.append(name, number, explanation);
    elements.metricGrid.append(article);
  }

  function renderMetrics() {
    const summary = Core.computeSummary(dataset, session);
    const metrics = summary.metrics;
    elements.metricGrid.replaceChildren();
    if (!summary.officialEligibility.eligible) {
      elements.releaseGate.textContent = "UNOFFICIAL · demo or non-release evaluation set";
      elements.releaseGate.dataset.result = "unofficial";
    } else {
      elements.releaseGate.textContent = summary.releaseGate.passed
        ? "PASS · all three v0.1.0 thresholds met"
        : "FAIL · one or more v0.1.0 thresholds missed";
      elements.releaseGate.dataset.result = summary.releaseGate.passed ? "pass" : "fail";
    }
    addMetric(
      "DeepSeek naturalness",
      formatPercent(metrics.deepseekNaturalnessPreferred.rate),
      `${metrics.deepseekNaturalnessPreferred.count} of ${metrics.total} preferred`,
    );
    addMetric(
      "Accuracy ≥ Apple",
      formatPercent(metrics.deepseekAccuracyEqualOrBetter.rate),
      `${metrics.deepseekAccuracyEqualOrBetter.count} of ${metrics.total} equal or better`,
    );
    addMetric(
      "Reading preference",
      formatPercent(metrics.deepseekReadingPreferred.rate),
      `${metrics.deepseekReadingPreferred.count} of ${metrics.total} preferred`,
    );
    addMetric(
      "Major errors",
      String(metrics.deepseekMajorSemanticErrors),
      "DeepSeek candidates marked with a consequential meaning error",
    );
    if (summary.outputHygiene) {
      for (const provider of ["apple", "deepseek"]) {
        const hygiene = summary.outputHygiene[provider];
        addMetric(
          `${provider} raw formatting`,
          `${hygiene.scriptConvertedCases} + ${hygiene.outerQuoteAdjustedCases}`,
          "script conversions + source-controlled outer-quote adjustments; reported separately",
        );
      }
    }
  }

  function renderRevealList() {
    elements.revealList.replaceChildren();
    for (const item of dataset.dataset.cases) {
      const revealed = Core.revealCase(dataset, session, item.id);
      const details = document.createElement("details");
      details.className = "reveal-item";
      const summary = document.createElement("summary");
      const title = document.createElement("span");
      title.textContent = item.source.text.length > 92
        ? `${item.source.text.slice(0, 89)}…`
        : item.source.text;
      const key = document.createElement("span");
      key.className = "provider-key";
      key.textContent = `A · ${revealed.providers.A}   B · ${revealed.providers.B}`;
      summary.append(title, key);

      const body = document.createElement("div");
      body.className = "reveal-body";
      for (const label of ["A", "B"]) {
        const card = document.createElement("div");
        card.className = "revealed-candidate";
        const provider = document.createElement("span");
        provider.className = "provider-key";
        provider.textContent = `${label} · ${revealed.providers[label]}`;
        const translation = document.createElement("p");
        translation.lang = "zh-Hans";
        translation.textContent = revealed.candidates[label];
        card.append(provider, translation);
        if (revealed.rawCandidates[label] !== revealed.candidates[label]) {
          const rawDetails = document.createElement("details");
          rawDetails.className = "raw-output";
          const rawSummary = document.createElement("summary");
          rawSummary.textContent = "Original provider output";
          const rawTranslation = document.createElement("p");
          rawTranslation.lang = "zh";
          rawTranslation.textContent = revealed.rawCandidates[label];
          rawDetails.append(rawSummary, rawTranslation);
          card.append(rawDetails);
        }
        body.append(card);
      }
      details.append(summary, body);
      elements.revealList.append(details);
    }
  }

  function renderResults() {
    setView("results");
    updateProgress();
    renderMetrics();
    renderRevealList();
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function finalize() {
    if (!Core.isComplete(dataset, session)) return;
    const confirmed = window.confirm(
      "Finalize this session? Scores will be locked and provider identities revealed.",
    );
    if (!confirmed) return;
    session = Core.finalizeSession(dataset, session);
    persist();
    renderResults();
  }

  function filename(suffix) {
    const stamp = new Date().toISOString().slice(0, 10);
    return `margin-evaluation-${stamp}-${suffix}`;
  }

  function download(name, contents, type) {
    const blob = new Blob([contents], { type });
    const href = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = href;
    link.download = name;
    document.body.append(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(href);
  }

  function clearLocalData() {
    const confirmed = window.confirm(
      "Clear the imported dataset and all locally saved scores from this browser? Export anything you need first.",
    );
    if (!confirmed) return;
    safeStorage(() => {
      const evaluatorKeys = [];
      for (let index = 0; index < localStorage.length; index += 1) {
        const key = localStorage.key(index);
        if (key && key.startsWith("margin-evaluation:")) evaluatorKeys.push(key);
      }
      for (const key of evaluatorKeys) localStorage.removeItem(key);
    });
    dataset = null;
    session = null;
    elements.clearProgress.hidden = true;
    elements.datasetFile.value = "";
    elements.railFill.style.height = "0%";
    elements.railFill.style.width = "0%";
    elements.railCount.textContent = "No set loaded";
    hideNotice();
    setView("import");
  }

  elements.datasetFile.addEventListener("change", () => {
    const file = elements.datasetFile.files && elements.datasetFile.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.addEventListener("load", () => {
      try {
        const imported = Core.validateDataset(JSON.parse(reader.result));
        const saved = safeStorage(() => localStorage.getItem(Core.storageKey(imported)));
        const restored = saved ? Core.restoreSession(imported, saved) : Core.createSession(imported);
        const persisted = activateDataset(imported, restored);
        if (persisted) {
          showNotice(saved ? "Existing local progress restored for this set." : "Evaluation set loaded locally.");
        }
      } catch (error) {
        showNotice(`The evaluation file could not be loaded: ${error.message}`, true);
      }
    });
    reader.addEventListener("error", () => {
      showNotice("The selected file could not be read.", true);
    });
    reader.readAsText(file);
  });

  elements.scoreForm.addEventListener("submit", saveCurrentResponse);
  elements.scoreForm.addEventListener("input", autosaveDraft);
  elements.scoreForm.addEventListener("keydown", handleScoreKeyboard);
  elements.scoreForm.addEventListener("focusin", (event) => {
    setActiveQuestion(event.target.closest("[data-question]"));
  });
  elements.scoreForm.addEventListener("click", (event) => {
    setActiveQuestion(event.target.closest("[data-question]"));
  });
  elements.previousCase.addEventListener("click", goPrevious);
  elements.finalize.addEventListener("click", finalize);
  elements.clearProgress.addEventListener("click", clearLocalData);
  elements.exportDetailJSON.addEventListener("click", () => {
    download(
      filename("detailed.json"),
      `${JSON.stringify(Core.createDetailedExport(dataset, session), null, 2)}\n`,
      "application/json",
    );
  });
  elements.exportDetailCSV.addEventListener("click", () => {
    download(filename("detailed.csv"), Core.toDetailedCSV(dataset, session), "text/csv");
  });
  elements.exportPublicJSON.addEventListener("click", () => {
    download(
      filename("public-summary.json"),
      `${JSON.stringify(Core.createPublicSummary(dataset, session), null, 2)}\n`,
      "application/json",
    );
  });

  restoreLastSession();
})();
