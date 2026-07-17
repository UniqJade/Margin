# Margin blind translation evaluation

This directory contains a local, static A/B evaluator for comparing Apple and
DeepSeek translations without showing which provider produced candidate A or B.
It is an author tool, not part of the Margin app and not a scientific user study.

## Run it

Open `index.html` directly in Safari, Chrome, or another current browser. No web
server is required. Choose a prepared JSON file when prompted.

The page has a restrictive Content Security Policy and contains no network-call
code, analytics, external fonts, or remote assets. Imported text, candidate
translations, assignments, and scores are stored only in that browser's local
storage. Use **Clear local data** when the session is no longer needed.

Browser storage is local, not encrypted archival storage. Anyone with access to
the same macOS account and browser profile may be able to inspect it.

## Prepare a dataset

The checked-in `fixtures/demo-session.json` remains a valid schema v1 example.
Formal runs use schema v3 in `schema/session.schema.json`. Every case requires:

- a unique ID and category;
- English source text with title, creator, source URL, and license metadata;
- one Apple candidate and one DeepSeek candidate.

Schema v3 also requires `dataset.metadata` with the locked corpus hash, Margin
commit, provider model, prompt-contract version, Apple baseline OS/Books/locale,
private/public-domain/total case counts, and the blind-display normalization
contract. Each candidate keeps a private `rawText`, a normalized `displayText`,
and transformation flags. The evaluator verifies that the counts equal the
number of cases. The corpus hash remains private and never enters the public
summary.

Do not open the prepared file while scoring: provider names necessarily remain
inside the local JSON so the evaluator can reveal them after finalization.
Margin randomizes their presentation when a new session begins and saves that
assignment with the progress record.

The checked-in demo uses self-authored English and Chinese text. Its provider
labels are synthetic placeholders for exercising the interface; its scores are
not evidence about either translation service.

`corpora/public-domain.json` supplies the 28 locked, source-only public-domain
cases for the formal held-out run. It does not include provider output. Private
selections from books you are currently reading belong in `private/` with a
`.local.json` or `.private.json` suffix.

### 2026-07-16 source-only capture amendment

The first formal collection run exposed two Apple Books constraints that were
not visible during corpus validation: long selections can cross internal page
fragments, and the built-in Translate sheet accepts at most 512 source
characters. Before candidate collection, `pd-darwin-04` was replaced with two
consecutive sentences from the same Project Gutenberg chapter (360 characters).

After the 512-character boundary was reproduced on the next untested case, all
remaining untested passages longer than 450 characters were shortened as one
batch. Each replacement contains two to four consecutive sentences from the
same work; selection used only source coherence, proximity, and character
length. No Apple or DeepSeek translation was inspected. The eight completed
cases remain byte-for-byte unchanged, and the migration command rejects any
amended ID already present in the collection journal.

The corpus hash and source-only EPUB were regenerated. The 40-case composition,
work/category balance, scoring thresholds, and request limits remain unchanged.
This is a collection-compatibility amendment, not a performance-based sample
substitution.

### Margin-first collection

The private journal supports collecting Margin before Apple Books. A reserved
case moves to `deepseekCollected` as soon as its Margin result and actual HTTP
request count are atomically saved. It becomes `complete` only after the matching
Apple workbook row is imported. Existing Apple-first `complete` records remain
compatible, and a case can never consume a second formal lookup attempt.

```bash
node Evaluation/tools/prepare-evaluation.cjs journal-reserve \
  --corpus Evaluation/corpora/public-domain.json \
  --corpus Evaluation/private/apple-books-source.private.json \
  --journal Evaluation/private/collection-journal.private.json \
  --case-id CASE_ID

node Evaluation/tools/prepare-evaluation.cjs journal-stage-deepseek \
  --corpus Evaluation/corpora/public-domain.json \
  --corpus Evaluation/private/apple-books-source.private.json \
  --journal Evaluation/private/collection-journal.private.json \
  --case-id CASE_ID --deepseek-file PRIVATE_TEXT_FILE --http-requests 0
```

After the Apple workbook is filled, convert the controlled template and import
all 40 rows. The converter uses the system ZIP reader, validates that Case and
Case ID columns were not reordered, and writes a mode-0600 private JSON file.

```bash
node Evaluation/tools/prepare-evaluation.cjs xlsx-to-apple-json \
  --corpus Evaluation/corpora/public-domain.json \
  --corpus Evaluation/private/apple-books-source.private.json \
  --xlsx "Evaluation/private/outputs/apple-capture-20260716/Margin Apple Translations.private.xlsx" \
  --output Evaluation/private/apple-translations.private.json

node Evaluation/tools/prepare-evaluation.cjs journal-import-apple \
  --corpus Evaluation/corpora/public-domain.json \
  --corpus Evaluation/private/apple-books-source.private.json \
  --journal Evaluation/private/collection-journal.private.json \
  --apple-json Evaluation/private/apple-translations.private.json
```

The import removes only the recognized Apple Books source/copyright footer.
Already completed Apple candidates must otherwise match exactly; blank,
non-Chinese, reordered, or visibly truncated candidates stop the import.
Before replacing the journal, the command creates a mode-0600 sibling backup.

The schema v3 merge applies `blind-display-v1` equally to both providers. It
normalizes whitespace, converts both candidates to Simplified Chinese with the
local macOS Foundation transform, canonicalizes paired Chinese quote glyphs,
and makes the whole-text outer quote follow the English source. It does not
change wording, sentence order, or other punctuation choices. The raw candidate
remains available only after finalization; output-hygiene counts are reported
separately and do not change the content-quality release gate.

Before collecting the formal 40 cases, run the adaptive passage workflow over
`corpora/development-public-domain.json`. This is a separate 10-case development
set drawn from five works absent from the public held-out corpus. It is not an
Apple-versus-DeepSeek comparison and must never be merged into the formal set.
The development gate requires 10/10 usable final natural translations and at
least 8/10 first-attempt semantic alignments. At most three complete rounds and
60 HTTP requests are permitted. Outcome metadata belongs in `private/`; it
contains booleans and request counts, not source text or translations.

Validate the separation and report a completed private run with:

```bash
node Evaluation/tools/development-gate.cjs validate \
  --corpus Evaluation/corpora/development-public-domain.json \
  --held-out Evaluation/corpora/public-domain.json

node Evaluation/tools/development-gate.cjs report \
  --corpus Evaluation/corpora/development-public-domain.json \
  --held-out Evaluation/corpora/public-domain.json \
  --results Evaluation/private/development-gate.private.json
```

## Score and reveal

For each case, record:

1. accuracy;
2. naturalness as published Chinese prose;
3. handling of material ambiguity, or not applicable;
4. overall reading preference;
5. any major semantic error.

The proofreader key ledger makes the 40-case run faster:

- `1`, `2`, `3` choose A, Equal, or B for the focused judgment;
- `4` chooses N/A while material ambiguity is focused;
- `Tab` moves between judgments;
- `M` cycles major-error marks through none, A, B, and both;
- `Enter` files the complete score and moves to the next passage.

Every choice and note edit is autosaved as a draft. Reimporting the unchanged
file restores the current passage, draft, completed scores, and the original A/B
assignment. Editing a filed score converts it back to a draft so it cannot be
finalized accidentally.

Progress is keyed by a fingerprint of the complete dataset. Reimporting the
unchanged file restores the same A/B order and saved scores. Changing any source
or candidate creates a different session.

**Finalize & reveal** is one-way. It is enabled only when every case has a valid
score. Finalization locks all answers, reveals providers, and enables:

- detailed JSON, including source text plus raw and blind-display translations;
- detailed CSV, including source text plus raw and blind-display translations;
- public summary JSON, containing aggregates and limitations but no source or
  candidate text.

Keep detailed exports in `results/`, which is ignored by Git.

## Metrics

The summary reports:

- DeepSeek naturalness preference: cases where DeepSeek wins naturalness divided
  by all scored cases; ties remain in the denominator;
- DeepSeek accuracy equal to or better than Apple: DeepSeek wins plus ties,
  divided by all cases;
- DeepSeek overall reading preference, with ties in the denominator;
- count of DeepSeek candidates marked with a major semantic error.

After reveal, schema v3 also reports per-provider counts for whitespace,
Traditional-to-Simplified conversion, quote-glyph normalization, and
source-controlled outer-quote adjustment. These are descriptive output-hygiene
metrics and are not added post hoc to the release gate.

For the locked 40-case v0.1.0 run, the release gate is at least 24 naturalness
wins, at least 36 cases where accuracy is equal to or better than Apple, and at
most one major semantic error. The results view calculates PASS or FAIL without
rounding down. A single author-evaluator remains an important limitation even
when the procedure is blind.

PASS/FAIL is available only to a schema v3 dataset containing exactly 40 cases
whose metadata records 12 private and 28 public-domain cases. Schema v1 demos,
short practice sets, and any differently composed dataset are labeled
**UNOFFICIAL** even when their aggregate percentages exceed the thresholds.

## Test

The logic has no package dependencies and uses Node's built-in test runner:

```bash
node --test Evaluation/tests/*.test.cjs
```

The tests cover v1/v2/v3 schema checks, blind/raw isolation, idempotent display
normalization, stable assignment, draft and legacy-session
restoration, locked finalization, revealed metrics and gate calculation, CSV
escaping, source-free public export, keyboard hooks, and the no-network CSP
boundary.
