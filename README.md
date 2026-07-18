# Margin — Contextual Reading for Apple Books

> **Read English. Stay in the book.**

[简体中文](README.zh-CN.md)

Margin is a personal, open-source English → Simplified Chinese reading companion.
Select a word or a short passage in Apple Books, press one shortcut, and read the
result beside the page instead of switching to a general-purpose translator.

Margin is deliberately narrow. It is not trying to replace a comprehensive
dictionary, OCR tool, document translator, or language-learning platform. It is
trying to make one interruption in English reading smaller.

## Status

| Platform | v0.1.0 status | Apple Books path |
|---|---|---|
| macOS | **Verified** | Select text, then press `Control–Option–M` (`⌃⌥M`) |
| iPhone / iPad | **Experimental** | Action Extension and Shortcut fallback exist, but Books handoff still needs physical-device verification |

The verified Mac configuration is macOS 26.5 with Apple Books 8.5. Direct macOS
Services delivery was not exposed by that Books reading view; the supported path
uses the explicit shortcut and user-approved Accessibility access. See the
[compatibility record](docs/compatibility-spike.md) for the exact boundary.

This repository distributes **source only**. It does not provide a public `.app`,
DMG, TestFlight build, hosted service, or end-user installation support. The
credential design is personal BYOK: you build Margin yourself and supply your own
provider key.

## What makes Margin different

- **Stay on the page.** One shortcut opens one reusable panel over Apple Books;
  dismissing it returns immediately to reading.
- **Designed for prose.** Passage output aims for natural published Chinese,
  especially for the two-to-four-sentence selections common in novels,
  biography, history, and nonfiction.
- **One translation, two views.** Natural Translation presents the coherent
  Chinese passage. Semantic Alignment reorganizes that same translation beside
  its source sentences; it does not generate a conflicting second translation.
- **Material nuance only.** A nuance note is requested only when ambiguity could
  change meaning, tone, reference, or relationship.
- **Compact dictionary-style words.** Word results provide pronunciations,
  part-of-speech navigation, bounded senses, and bilingual examples without
  turning the reading panel into a full dictionary application.
- **Inspectable and personal.** The source, request boundary, storage behavior,
  and provider configuration can all be audited and adapted.

Margin complements rather than replaces tools such as Apple Look Up, Youdao, or
Eudic. Those products have stronger system integration, mature lexical sources,
OCR, offline dictionaries, document workflows, and learning features. Margin's
advantage is a quieter Apple Books workflow and a translation prompt focused on
natural Chinese prose. Its AI-generated dictionary content is not an
authoritative lexical source.

## Reading experience

### Passage lookup

Passage results default to **Natural Translation**. When structured alignment is
available, switch to **Semantic Alignment** to inspect which adjacent English
sentence or sentences correspond to each Chinese segment. The complete
translation is derived from those ordered segments, so both views use the same
Chinese wording. Margin only shows the mode switch when the result contains at
least two alignment blocks; a single block stays in Natural Translation because
the two presentations would otherwise be effectively identical.

Long original text folds automatically. Short results keep the panel compact;
long results scroll within the 280–620 pt Mac panel while Copy, Speak, Save, and
Retry remain available. The existing icons keep their native Apple appearance.

### Word lookup

Word results group common senses by provider-returned part of speech, with
available regional pronunciations and bilingual examples. Part-of-speech anchors
are clickable and keyboard accessible. v0.1.0 intentionally freezes this scope:
phrase lookup, bundled dictionaries, and vocabulary-study systems are not part of
this release.

### Appearance and language

Margin supports **Follow System**, **Light**, and **Dark**, using a restrained
warm-orange accent. The interface is localized in English and Simplified Chinese
and follows the device language. Translation remains English → Simplified
Chinese.

## Provider policy

`deepseek-v4-flash` is the only provider/model in Margin's v0.1.0 certification
scope. It is the supported configuration for the prompt, structured result, and
quality-evaluation path, so first-run setup and Settings make DeepSeek the primary
choice. It passed the locked v0.1.0 blind quality gate described below.
“Certified” still identifies a narrowly supported configuration, not universal
superiority across books, readers, models, or languages.

An Advanced section retains a configurable OpenAI-compatible endpoint and model
ID for future experimentation. Custom providers are **unverified, best effort**:
Margin does not promise equivalent JSON behavior or translation quality. It never
silently falls back to another provider and never sends one selection to multiple
providers.

## Privacy and local data

- A request contains only the text you explicitly selected, fixed language
  identifiers, lookup type, and translation style.
- Margin does not collect the book title, author, page number, or surrounding
  book text.
- On Mac, `⌃⌥M` synthesizes Copy only after you invoke it and accepts the
  selection only when that Copy operation changes the clipboard. Unrelated
  clipboard content is not retained.
- The API key is stored as a non-synchronizing, device-only Keychain item and is
  cached only in process memory after its first read in a launch.
- Successful results use a local, approximately **10 MB** least-recently-used
  response cache. Cache entries are technical acceleration data, not browsing
  history, and can be cleared.
- A lookup appears in Saved only after you explicitly press Save. Unsave removes
  it from the visible saved collection; unsaved lookups are not accumulated as
  history.
- Provider response bodies are not logged or shown as raw errors.

Selected text is still sent to the provider you configure. Margin is
data-minimizing, not offline. Direct client-side BYOK is suitable only for a
locally built personal prototype; a public binary would require an authenticated
backend relay. See [SECURITY.md](SECURITY.md).

## Quick start on Mac

1. Install Xcode, XcodeGen, and a valid Apple Development certificate with its
   private key.
2. Create your ignored `Local.xcconfig` from the checked-in example.
3. Run `./scripts/install-mac.sh` to build and install the fixed signed copy at
   `~/Applications/Margin.app`.
4. Complete first-run setup with your DeepSeek API key. The harmless word `book`
   is used to test the connection.
5. In Apple Books, select text and press `⌃⌥M`. On first use, allow that fixed
   Margin installation under **Privacy & Security → Accessibility**, return to
   Books, and press the shortcut again.

Opening Margin from Spotlight or the Dock does not inspect the selection or ask
for Accessibility access. The permission path begins only when you invoke the
capture shortcut.

Full prerequisites, unsigned test commands, signing configuration, stable Mac
installation, iOS builds, and cleanup are documented in
[Building Margin](docs/building.md).

## iPhone and iPad

The repository includes an iOS/iPadOS container app, Action Extension, and a
`Look Up English Text` App Intent. Their structure and simulator build are part of
the project, but Apple Books selection delivery has not yet been verified on a
physical iPhone or iPad.

Do not describe mobile Apple Books integration as working until the matrix in
[compatibility-spike.md](docs/compatibility-spike.md) has a recorded device result.
If Books opens the Action Extension without text, the intended fallback is a
pinned Share Sheet Shortcut that passes Shortcut Input to the App Intent. OCR and
screenshot capture remain out of scope.

## Translation evaluation

Margin includes a local, no-network blind A/B evaluator under `Evaluation/`. The
formal v0.1.0 run used 40 passages with its work/category composition locked
before candidate collection: ten each from biography/history, fiction/dialogue,
general nonfiction, and idiom/ambiguity/complex syntax. Twelve passages came
from the author's private Apple Books library and 28 from documented
public-domain sources. Source-only length amendments made for Apple Books
selection limits are documented in [Evaluation/README.md](Evaluation/README.md);
they were applied without inspecting candidate performance.

The predeclared v0.1.0 gate was:

- DeepSeek preferred for naturalness on at least 60% of cases;
- DeepSeek accuracy equal to or better than Apple on at least 90%;
- no more than one major DeepSeek semantic error.

The run was finalized on 17 July 2026 against Apple Books 8.5 on macOS 26.5:

| Measure | Result | Gate |
|---|---:|---:|
| DeepSeek preferred for naturalness | **37/40 (92.5%)** | ≥ 24/40 |
| DeepSeek accuracy equal to or better than Apple | **37/40 (92.5%)** | ≥ 36/40 |
| DeepSeek preferred while reading | **37/40 (92.5%)** | descriptive |
| Major DeepSeek semantic errors | **0** | ≤ 1 |

All three release thresholds passed. Results were strongest on
idiom/ambiguity/complex syntax and general nonfiction (10/10 on all three
comparison measures). Biography/history was the relative weak point, with 7/10
naturalness wins, 8/10 accuracy-equal-or-better cases, and 7/10 reading
preferences.

To preserve the blind, both candidates were displayed through the same
`blind-display-v1` Simplified Chinese typography contract while raw provider
output remained sealed until finalization. The separate raw-output audit found
that Apple required Simplified-script conversion in 4 cases, quote-glyph
normalization in 1, and source-controlled outer-quote adjustment in 24; DeepSeek
required one whitespace adjustment. These formatting counts did not affect the
content-quality gate.

This is a **single-evaluator, author-conducted test**, not a general user study.
The defensible claim is limited to this pre-locked 40-passage run; it does not
establish that Margin is always better than Apple for every book or reader. The
full method, copyright boundary, and limitations are in
[docs/evaluation.md](docs/evaluation.md).

## Development

The repository contains:

- native macOS, iOS/iPadOS, and Action Extension shells under `Apps/`;
- shared lookup, validation, provider, cache, and saved-item logic under
  `Sources/`;
- deterministic Swift and hosted Mac tests under `Tests/`;
- the local static evaluator under `Evaluation/`.

Live API calls are opt-in and excluded from normal tests. Start with
[docs/building.md](docs/building.md), then read [CONTRIBUTING.md](CONTRIBUTING.md).

## Known limitations

- English → Simplified Chinese only.
- Cloud provider and network required; no local model or offline dictionary.
- AI output can mistranslate, omit nuance, invent lexical detail, or return
  malformed structure.
- Semantic Alignment is sentence-level. A long selection containing one
  grammatical sentence can produce one block that looks similar to Natural
  Translation.
- Word entries do not cite a licensed authoritative dictionary.
- Accessibility permission is required for the verified Apple Books Mac shortcut.
- iPhone/iPad Apple Books handoff is experimental and unverified on a physical
  device.
- Personal source build only; no public binary, account sync, OCR, document
  translation, or support guarantee.

## License

Margin source code is available under the [MIT License](LICENSE). Evaluation
corpora retain their own provenance and licensing notes.
