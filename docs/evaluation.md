# Translation evaluation

## Current status: completed

The v0.1.0 blind comparison was finalized on **17 July 2026**. All three
predeclared release thresholds passed:

- DeepSeek preferred for naturalness: **37/40 (92.5%)**;
- DeepSeek accuracy equal to or better than Apple: **37/40 (92.5%)**;
- DeepSeek major semantic errors: **0**.

The Apple baseline was Apple Books 8.5 on macOS 26.5. The certified Margin
configuration used `deepseek-v4-flash` and prompt contract
`margin-v0.1.0-adaptive-passage-v2`.

This document preserves the method that was fixed before the results were known
and records the completed outcome. The result supports only the bounded claim
described under [Limitations](#limitations), not universal superiority.

## Question

For short English reading selections, does the certified Margin configuration
(`deepseek-v4-flash` with the versioned v0.1.0 prompt) produce Simplified Chinese
that the project author judges:

1. at least as accurate as Apple translation;
2. more natural as careful published Chinese;
3. no more likely to erase a material ambiguity;
4. preferable for continuing to read?

The evaluation compares translation output, not installation, latency, privacy,
offline availability, dictionary authority, or system integration.

## Corpus

The locked v0.1.0 held-out set contains **40 passages from 10 books**, with four
passages per book and ten passages in each fixed category. Each passage normally
contains two to four sentences and never exceeds 2,000 Unicode characters:

- `biography-history`
- `fiction-dialogue`
- `news-general-nonfiction`
- `idiom-ambiguity-complex-syntax`

Each category should include straightforward, moderate, and difficult material.
Include dialogue punctuation, reference resolution, negation, time and causal
relations, restrained historical prose, idioms, and ambiguity that could change
meaning or tone.

Separate the corpus before prompt tuning:

- **development subset:** may be used to diagnose and adjust the prompt or parser;
- **held-out subset:** remains unseen during tuning and decides the release gate.

A passage that influenced prompt wording is not held out. Replacing a failed
held-out item after seeing its result is not allowed unless the source itself was
invalid, duplicated, or illegally included, and the replacement is documented.

The formal run preserved the locked work/category composition. During source
collection, Apple Books exposed a 512-character translation boundary and
cross-page selection failures. Untested overlength passages were shortened as a
single source-only batch, using consecutive sentences from the same work and
without inspecting Apple or DeepSeek output. The completed cases were unchanged;
the exact amendment and migration guard are documented in
`Evaluation/README.md`.

## Copyright and private reading data

The repository may contain only:

- public-domain text with provenance;
- project-authored text with an explicit license;
- text distributed under a compatible explicit license.

`Evaluation/corpora/public-domain.json` contains the 28 source-only public-domain
passages used in the formal run. Its notice records each source and
public-domain basis. The remaining 12 passages were private Apple Books
selections and remain untracked.

Selections from modern books or other copyrighted reading material remain local.
Store prepared files under `Evaluation/private/` with a `.local.json` or
`.private.json` suffix. Detailed exports belong under `Evaluation/results/`.
Both directories are ignored, but `git status --short` must still be reviewed
before every commit.

Do not publish private source text, its candidate translations, item-level notes,
or scores that make the source identifiable. The evaluator's Public summary JSON
omits source text, candidate text, dataset title/ID, and dataset fingerprint.

## Candidate preparation

For every item, capture:

- the English source and provenance;
- Apple's translation baseline from the tested OS/Books configuration;
- Margin's DeepSeek result from the certified endpoint, model, prompt version,
  and app revision.

Do not manually improve either candidate. Preserve the raw provider output after
removing only recognized Apple Books interface footers. Formal schema v3 files
record:

- the raw provider output;
- the blind-display text shown to the evaluator;
- per-candidate normalization flags;
- a corpus hash, Margin revision, provider model, prompt-contract version, and
  Apple baseline OS/Books/locale;
- private, public-domain, and total case counts;
- the versioned blind-display normalization contract.

`blind-display-v1` applies the same local, deterministic rules to both
candidates: whitespace normalization, Traditional-to-Simplified conversion,
paired Chinese quote-glyph normalization, and source-controlled whole-text outer
quotes. It does not rewrite wording, sentence order, or other punctuation
choices. Raw output remains sealed until finalization, then contributes only to
the separate output-hygiene audit. Schema v1 and v2 remain import-compatible for
the self-authored demo and older local sessions but are ineligible for the
official v0.1.0 gate.

### Revision provenance

The finalized dataset's `marginCommit` field contains `264261e`, which was the
clean base revision when collection began. The evaluated app was actually built
from that revision plus the then-uncommitted adaptive-passage changes identified
by prompt contract `margin-v0.1.0-adaptive-passage-v2`. Recording only the base
revision was a metadata mistake; the finalized session is intentionally not
rewritten because doing so would change its fingerprint after scoring.

The runtime source files did not change between candidate collection and the
release audit. Their exact state is committed in `575f593` (“Improve DeepSeek
passage recovery”). A private mode-0600 evidence manifest records checksums for
the runtime-source snapshot and finalized artifacts. It remains outside Git
because artifact hashes could fingerprint the private corpus.

The local JSON necessarily contains provider keys so the evaluator can reveal
them later. The procedural blind therefore relies on the evaluator not opening or
inspecting that file while scoring; it is not a tamper-proof double-blind study.

## Local evaluator

Open `Evaluation/index.html` directly in a current browser and import the prepared
JSON. The tool:

- contains a restrictive Content Security Policy and no network-call code;
- validates the versioned data shape and four category names;
- assigns Apple and DeepSeek to A/B independently for each case;
- stores that assignment and progress under a fingerprint of the complete
  dataset, so reload and reimport preserve the blind order;
- autosaves every partial judgment and note as a draft, together with the current
  passage; editing a previously filed score makes that passage incomplete again;
- requires all four judgments before saving a case;
- enables Finalize only after every case is scored;
- permanently locks that session before revealing provider names.

Imported text and candidates are stored in browser-local storage so reload can
recover the session. That storage is local but not encrypted archival storage.
Use **Clear local data** after exporting what is needed.

For fast keyboard scoring, focus a judgment with `Tab`, use `1`/`2`/`3` for
A/Equal/B, and use `4` for Not applicable while ambiguity is focused. `M` cycles
the major-error mark through none/A/B/both. `Enter` files a complete score and
moves to the next passage. The on-page proofreader ledger repeats these keys.

Run the evaluator tests with:

```bash
node --test Evaluation/tests/*.test.cjs
```

## Per-item judgments

### Accuracy

Choose A, Equal, or B. Consider factual content, negation, time, causality,
reference, relationship, and whether information was added or omitted.

### Naturalness

Choose A, Equal, or B based on which Chinese reads more like careful published
prose. Do not reward elegance that changes the original meaning.

### Material ambiguity

Choose A, Equal, B, or Not applicable. Judge only ambiguity whose resolution can
change meaning, tone, reference, or relationship; ordinary wording alternatives
do not require a nuance note.

### Reading preference

Choose A, Equal, or B for the version preferred during actual reading. This is a
separate overall judgment, not a replacement for accuracy.

### Major semantic error

Mark A and/or B only for a consequential error, such as reversed negation,
incorrect actor, changed fact, wrong temporal or causal relation, or materially
different attitude. Stylistic awkwardness alone is not a major semantic error.

## Metrics

Ties remain in the denominator.

### DeepSeek naturalness preference

```text
cases where DeepSeek wins naturalness / all scored cases
```

### DeepSeek accuracy equal to or better than Apple

```text
cases where DeepSeek wins accuracy or accuracy is equal / all scored cases
```

### DeepSeek reading preference

```text
cases where DeepSeek wins overall reading preference / all scored cases
```

### Major semantic errors

Count cases where the DeepSeek-labelled candidate was marked with a major error.
Report category totals as diagnostics, but the locked release gate uses the whole
held-out set.

## v0.1.0 release gate

All conditions must pass on the finalized held-out set:

- DeepSeek naturalness preference ≥ **60%**;
- DeepSeek accuracy equal to or better than Apple ≥ **90%**;
- DeepSeek major semantic errors ≤ **1**.

No threshold is rounded down to manufacture a pass. The exact integer counts and
denominators must accompany percentages. If the gate fails, adjust only against
the development subset, prepare a new untouched held-out evaluation, and keep the
failed aggregate as part of the local development record.

For 40 cases, the thresholds resolve to at least **24** DeepSeek naturalness
wins, at least **36** accuracy outcomes equal to or better than Apple, and no
more than **1** DeepSeek major semantic error. The evaluator reports PASS only
when all three conditions hold and the dataset is eligible: schema v3, exactly
40 cases, and metadata counts of 12 private plus 28 public-domain cases. All v1,
v2, demo, non-40, or differently composed runs are explicitly reported as
**UNOFFICIAL**, never PASS.

## Exports

After Finalize, the tool produces:

- **Detailed JSON:** source, raw and blind-display candidates, normalization
  flags, assignments, per-item responses, notes, and aggregate summary;
- **Detailed CSV:** the same item-level content in spreadsheet form, with
  formula-injection protection;
- **Public summary JSON:** aggregate counts, category aggregates, finalization
  time, non-identifying run configuration, aggregate output-hygiene counts, and
  methodological limitations. It excludes titles, creators, source and
  candidate text, dataset ID, dataset fingerprint, and corpus hash.

Detailed exports are private by default. Review the Public summary manually
before adding it to documentation.

## v0.1.0 report

```text
Status: PASS
Evaluation date: 2026-07-17
Evaluator count: 1 (project author)
DeepSeek model: deepseek-v4-flash
Prompt version: margin-v0.1.0-adaptive-passage-v2
Apple baseline: macOS 26.5 / Apple Books 8.5 / zh-Hans-CN
Held-out sample count: 40 (12 private, 28 public domain)

DeepSeek naturalness preferred: 37/40 (92.5%)
DeepSeek accuracy equal or better: 37/40 (92.5%)
DeepSeek reading preference: 37/40 (92.5%)
DeepSeek major semantic errors: 0
Release gate: PASS
```

Category results and the raw-output hygiene audit are summarized in the main
README. Detailed item-level exports remain private because they contain
copyrighted reading selections and both providers' translations.

## Limitations

- One evaluator is not representative of all Chinese readers.
- The evaluator is also the project author and has an interest in the outcome.
- A/B order is blinded, but candidate style may still reveal likely provenance.
- Provider labels remain in the local preparation file.
- Apple translation behavior can change with OS, Books, language resources, and
  network state.
- DeepSeek behavior can change even when a public model name remains the same.
- Forty passages from ten books can guide a personal reading tool but cannot establish
  universal superiority, domain coverage, or statistical generalization.

Any public claim must therefore use wording such as “in the author's personal
blind evaluation” and name the tested configuration and date.
