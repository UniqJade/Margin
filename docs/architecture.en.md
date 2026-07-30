# Margin Architecture

[简体中文](architecture.md) · English (current)

This document describes the durable architectural constraints in the current
source tree. Source and tests are authoritative for behavior. See
[building.md](building.md), [evaluation.md](evaluation.md), and
[compatibility-spike.md](compatibility-spike.md) for building, evaluation, and
platform-support details.

## Goals and boundaries

Margin is an Apple Books English-reading companion with macOS as its primary
platform. It handles only text that the user explicitly selects and turns an
English word or short passage into Simplified Chinese that supports continued
reading.

Its core boundaries are:

- The only book content sent to the cloud provider is the user's cleaned,
  normalized selection. Requests also contain the fixed translation
  instructions and control fields such as model, language, and style.
- Apple Books may append source metadata such as a title and author to copied
  text. Margin removes a complete recognized attribution footer locally and
  does not separately collect the page number or surrounding text.
- Use the user's own cloud-provider API key; Margin is not an offline
  translation tool.
- Send words and passages through one lookup pipeline while using different
  models, validation rules, and presentation.
- Treat macOS as the verified primary path; the iOS app and Action Extension
  remain experimental shells.
- Do not add OCR, screenshot recognition, whole-book translation, accounts, or
  cloud history.

## Module map

| Path | Responsibility |
|---|---|
| `Apps/macOS/` | Global shortcut, Accessibility-assisted selection capture, AppKit panel, and macOS lifecycle |
| `Apps/iOS/`, `Apps/ActionExtension/` | iOS container, App Intent, and text Action Extension |
| `Apps/SharedUI/` | Lookup session, first run, settings, history, and cross-platform SwiftUI result views |
| `Sources/LookupCore/` | Input normalization, request/result models, provider protocol, validation, cache, and saved-item storage |
| `Sources/ApplePlatformSupport/` | Apple-platform security facilities such as Keychain |
| `Evaluation/` | Local, no-network blind evaluator; not part of app runtime |
| `Tests/` | Behavioral coverage for core packages, the macOS host, storage, providers, and UI state |

`Package.swift` defines the independently testable `LookupCore` and
`ApplePlatformSupport` libraries. `project.yml` is the XcodeGen source for the
macOS app, iOS app, and Action Extension; the generated
`BooksTranslator.xcodeproj` should not be maintained by hand.

## macOS lookup flow

```mermaid
flowchart LR
    A["Selection in Apple Books"] --> B["⌃⌥M"]
    B --> C["Accessibility-assisted Copy"]
    C --> D["LookupSession"]
    D --> E["LookupRequest: clean, normalize, classify"]
    E --> F{"Cache hit?"}
    F -- "yes" --> K["Complete LookupOutcome"]
    F -- "no" --> G["Provider structured request"]
    G --> I["Obtain and validate complete result"]
    I --> L["Best-effort bounded cache write"]
    L --> K
    K --> M["Word card or passage reader"]
```

`SelectionShortcutController` registers `⌃⌥M`. After the user grants
Accessibility permission, `SelectedTextCapture` posts one `⌘C` and reads a new
selection only when the system pasteboard actually changes. The result goes to
`LookupSession`; generation tokens prevent an older asynchronous capture from
overwriting a newer lookup.

`LookupSession` is the main-thread UI orchestration boundary and the single
source of truth for lookup state. State advances through
`idle → loading → result/failure`; every new lookup cancels the old task and
advances a generation, and only the current generation may publish later state.

The lookup surface is one lazily created, reusable AppKit `NSPanel`. It can join
all Spaces and appear beside full-screen Apple Books; closing hides it instead
of destroying it. Settings and saved items use independent windows.

## Input, models, and translation contract

Before a network request, `LookupRequest`:

1. Removes an Apple Books source/copyright footer only when the complete footer
   pattern matches.
2. Collapses excess whitespace, rejects empty input, and enforces a 2,000
   character limit.
3. Classifies a single word form as `word` and everything else as `passage`.
4. Fixes the source to English, the target to Simplified Chinese, and the style
   to natural published prose.

A word result contains pronunciations, parts of speech, senses, and bilingual
examples. Decoding remains compatible with the older flat cache representation.

A passage is first segmented locally into numbered English sentences. Every
alignment block returned by the provider must cover all sentences exactly once,
in order, without overlap. Natural prose is the concatenation of those Chinese
blocks, so Natural Translation and Bilingual View never generate contradictory
translations. With fewer than two usable blocks, the UI exposes only Natural
Translation.

`TranslationContract.version` participates in both the provider identity and
cache key. Any prompt, structured-output, or validation change that can affect a
result must increment the version and trigger a review of whether the existing
evaluation is still applicable.

## Provider and validation

`TranslationProvider` isolates provider behavior. The default configuration
uses DeepSeek while retaining a best-effort OpenAI-compatible interface.

- The selection is placed in the user message as JSON data; the system message
  explicitly treats book text as untrusted input.
- Word and passage responses must pass strict structural, cardinality, and
  nonempty-field validation.
- Passages additionally require exact sentence coverage and usable Chinese.
- When DeepSeek's structured passage fails, one natural-translation fallback is
  allowed; generic compatible providers use one structured repair request.
- Provider response bodies and API keys never enter diagnostic records.

## Panel and reading presentation

- The current UI policy targets a 540 pt panel width. Passage height adapts
  within roughly 280–620 pt; the word card uses an approximately 620 pt reading
  height.
- Content-driven resizing preserves the panel's top edge and keeps the complete
  window inside the current screen's visible frame.
- A word result shows all common parts of speech in one scrollable document.
  Part-of-speech controls are scroll anchors, not content replacements.
- Passages lead with complete natural Chinese and keep the English original
  collapsed. Bilingual View is available only with at least two alignment
  blocks.
- Both passage views share one `PassageLookupResult`. Copy and Speak always
  follow the currently visible mode.
- System, Light, and Dark are device-local preferences. Orange is reserved for
  markers, navigation, and limited interaction feedback.

## Local data and privacy

- The API key lives in a nonsynchronizing, device-only Keychain item.
- Cache keys SHA-256 hash the normalized request, provider identity, and
  translation-contract namespace; source text is not exposed in the key.
- The current response cache is an approximately 10 MB local LRU JSON store.
  Cache persistence failure must not fail an otherwise successful lookup.
- A lookup never writes history automatically. A result enters saved-item
  storage only when the user explicitly presses Save.
- The response cache and saved-item JSON stores use sidecar file locks and
  atomic replacement to prevent concurrent instances from overwriting one
  another.
- Current local diagnostics are actor-isolated and written through temporary
  file replacement. They retain at most 50 structured events and contain
  metadata such as stage, error class, status code, and token counts.
- macOS data lives in Application Support. The iOS container and Action
  Extension share local data through an App Group.

Selected text still goes to the cloud provider configured by the user. These
properties express data minimization, not offline operation or zero disclosure.

## Sources of truth and change discipline

- Input, models, and storage: `Sources/LookupCore/`
- macOS capture and panel: `Apps/macOS/`
- Session and presentation: `Apps/SharedUI/`
- Keychain: `Sources/ApplePlatformSupport/`
- Core tests: `Tests/LookupCoreTests/`
- macOS host tests: `Tests/MacAppTests/`

When an architectural invariant changes, update its tests and this document in
the same change. Common validation commands are:

```bash
swift test
./scripts/test-mac.sh
./scripts/verify-xcodegen-determinism.sh
./scripts/audit-public-repo.sh
```
