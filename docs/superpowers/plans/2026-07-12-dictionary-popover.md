# Dictionary Popover and Single-Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Margin’s duplicate lookup windows and minimal word card with one reusable Apple-inspired dictionary panel containing grouped parts of speech, inline bilingual definitions, examples, and anchor navigation.

**Architecture:** `LookupCore` gains a backward-compatible structured word model and provider validation. Shared SwiftUI receives focused dictionary components while passage presentation remains unchanged. The macOS target removes its automatic lookup `Window` and routes every trigger through one reusable `NSPanel` with deterministic positioning and dismissal behavior.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, XCTest, XcodeGen, Foundation Codable, OpenAI-compatible Chat Completions JSON schema.

---

## File Map

**Create:**

- `Sources/LookupCore/WordPresentation.swift` — safe part-of-speech labels, anchor IDs, validated example emphasis.
- `Apps/SharedUI/WordDictionaryView.swift` — fixed header/navigation/footer and scrollable senses.
- `Apps/SharedUI/LookupActionBar.swift` — copy, speak, save, and retry controls.
- `Apps/macOS/LookupPanel.swift` — reusable panel, placement, and Escape handling.
- `Tests/MacAppTests/LookupPanelTests.swift` — hosted AppKit tests.

**Modify:**

- `Sources/LookupCore/LookupModels.swift`
- `Sources/LookupCore/OpenAICompatibleProvider.swift`
- `Apps/SharedUI/ResultCardView.swift`
- `Apps/SharedUI/LookupPanelView.swift`
- `Apps/SharedUI/HistoryView.swift`
- `Apps/macOS/MacAppDelegate.swift`
- `Apps/macOS/MarginMacApp.swift`
- `project.yml` and `BooksTranslator.xcodeproj/project.pbxproj`
- `Tests/LookupCoreTests/LookupModelsTests.swift`
- `Tests/LookupCoreTests/OpenAICompatibleProviderTests.swift`
- `Tests/LookupCoreTests/StorageTests.swift`
- `Fixtures/evaluation-corpus.json`
- `README.md` and `docs/compatibility-spike.md`

---

### Task 1: Rich Word Model and Legacy Decoding

**Files:**
- Modify: `Tests/LookupCoreTests/LookupModelsTests.swift`
- Modify: `Sources/LookupCore/LookupModels.swift`

- [ ] **Step 1: Write failing rich-model and legacy tests**

Add a `richWord` fixture containing two pronunciations, adjective and noun groups, bilingual senses, and a highlighted example. Add:

```swift
func testRichWordResultRoundTripsThroughJSON() throws {
    let result = LookupResult.word(richWord)
    let data = try JSONEncoder().encode(result)
    XCTAssertEqual(try JSONDecoder().decode(LookupResult.self, from: data), result)
}

func testLegacyWordResultDecodesIntoOnePartOfSpeech() throws {
    let legacy = #"{"headword":"exchange","ipa":"/ɪksˈtʃeɪndʒ/","partOfSpeech":"noun","senses":["交流","交换"],"example":"That started an exchange.","exampleTranslation":"这开启了一场交流。","alternatives":["交锋"]}"#
    let word = try JSONDecoder().decode(WordLookupResult.self, from: Data(legacy.utf8))
    XCTAssertEqual(word.pronunciations, [.init(region: nil, ipa: "/ɪksˈtʃeɪndʒ/")])
    XCTAssertEqual(word.partsOfSpeech.map(\.name), ["noun"])
    XCTAssertEqual(word.partsOfSpeech[0].senses.map(\.chineseDefinition), ["交流", "交换"])
    XCTAssertNil(word.partsOfSpeech[0].senses[0].englishDefinition)
    XCTAssertEqual(word.partsOfSpeech[0].senses[0].examples.first?.english, "That started an exchange.")
}
```

- [ ] **Step 2: Verify RED**

Run `swift test --filter LookupModelsTests`.

Expected: compilation fails because the rich word types and grouped properties do not exist.

- [ ] **Step 3: Implement the data structures**

Replace the flat word model with these public Codable/Equatable/Sendable values:

```swift
public struct WordPronunciation: Codable, Equatable, Sendable {
    public let region: String?
    public let ipa: String
}

public struct WordExample: Codable, Equatable, Sendable {
    public let english: String
    public let chinese: String
    public let highlightedPhrase: String?
}

public struct WordSense: Codable, Equatable, Sendable {
    public let contextLabel: String?
    public let englishDefinition: String?
    public let chineseDefinition: String
    public let examples: [WordExample]
}

public struct WordPartOfSpeech: Codable, Equatable, Sendable {
    public let name: String
    public let senses: [WordSense]
}

public struct WordLookupResult: Codable, Equatable, Sendable {
    public let headword: String
    public let pronunciations: [WordPronunciation]
    public let partsOfSpeech: [WordPartOfSpeech]
    public let alternatives: [String]
}
```

Give each struct a public memberwise initializer. Give `WordLookupResult` custom `CodingKeys` containing the new fields and legacy `ipa`, `partOfSpeech`, `senses`, `example`, and `exampleTranslation`. Decode new records when `partsOfSpeech` exists. Otherwise map legacy IPA to one pronunciation, legacy senses to one group named by `partOfSpeech` (or `word` when absent), omit the unavailable English definition, and attach the legacy bilingual example only to the first sense. Encode only the new representation.

- [ ] **Step 4: Verify GREEN and commit**

```bash
swift test --filter LookupModelsTests
git add Sources/LookupCore/LookupModels.swift Tests/LookupCoreTests/LookupModelsTests.swift
git commit -m "feat: structure word results by part of speech"
```

Expected: model tests pass and legacy JSON remains decodable.

---

### Task 2: Presentation Metadata and Persisted Migration

**Files:**
- Create: `Sources/LookupCore/WordPresentation.swift`
- Modify: `Tests/LookupCoreTests/LookupModelsTests.swift`
- Modify: `Tests/LookupCoreTests/StorageTests.swift`
- Modify: `Apps/SharedUI/HistoryView.swift`

- [ ] **Step 1: Write failing presentation tests**

```swift
func testPartOfSpeechPresentationIsStableAndSanitized() {
    XCTAssertEqual(WordPartOfSpeech(name: "adjective", senses: []).abbreviation, "adj.")
    XCTAssertEqual(WordPartOfSpeech(name: "noun", senses: []).abbreviation, "n.")
    XCTAssertEqual(WordPartOfSpeech(name: "verb", senses: []).abbreviation, "v.")
    XCTAssertEqual(WordPartOfSpeech(name: "phrasal verb", senses: []).anchorID, "pos-phrasal-verb")
}

func testHighlightedPhraseMustExistInsideEnglishExample() {
    let valid = WordExample(english: "We are on intimate terms.", chinese: "我们关系密切。", highlightedPhrase: "intimate terms")
    let invalid = WordExample(english: "We are close friends.", chinese: "我们是密友。", highlightedPhrase: "intimate terms")
    XCTAssertEqual(valid.validatedHighlightedPhrase, "intimate terms")
    XCTAssertNil(invalid.validatedHighlightedPhrase)
}
```

In `StorageTests`, write a literal legacy cache dictionary to `cache.json`, create `LookupCache`, and assert the recovered word contains one migrated group instead of the cache becoming empty.

- [ ] **Step 2: Verify RED**

Run `swift test --filter LookupModelsTests` and `swift test --filter StorageTests`.

Expected: presentation properties are missing.

- [ ] **Step 3: Create `WordPresentation.swift`**

```swift
import Foundation

public extension WordPartOfSpeech {
    var abbreviation: String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "adjective": "adj."
        case "noun": "n."
        case "verb": "v."
        case "adverb": "adv."
        case "preposition": "prep."
        case "pronoun": "pron."
        case "conjunction": "conj."
        case "interjection": "interj."
        case "phrasal verb": "phr. v."
        default: String(name.prefix(8))
        }
    }

    var anchorID: String {
        let pieces = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = pieces.filter { !$0.isEmpty }.joined(separator: "-")
        return "pos-\(slug.isEmpty ? "word" : slug)"
    }
}

public extension WordExample {
    var validatedHighlightedPhrase: String? {
        guard let highlightedPhrase,
              english.range(of: highlightedPhrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
            return nil
        }
        return highlightedPhrase
    }
}
```

- [ ] **Step 4: Update history summaries**

Replace the word summary branch with:

```swift
case let .word(word):
    word.partsOfSpeech.flatMap(\.senses).map(\.chineseDefinition).prefix(3).joined(separator: " · ")
```

- [ ] **Step 5: Verify GREEN and commit**

```bash
swift test --filter LookupModelsTests
swift test --filter StorageTests
git add Sources/LookupCore/WordPresentation.swift Tests/LookupCoreTests/LookupModelsTests.swift Tests/LookupCoreTests/StorageTests.swift Apps/SharedUI/HistoryView.swift
git commit -m "feat: migrate and present structured word entries"
```

---

### Task 3: Provider Contract and Validation

**Files:**
- Modify: `Tests/LookupCoreTests/OpenAICompatibleProviderTests.swift`
- Modify: `Sources/LookupCore/OpenAICompatibleProvider.swift`

- [ ] **Step 1: Write failing rich-provider tests**

Use this exact word payload in decode, repair, DeepSeek, and OpenAI schema tests:

```swift
let richPayload = #"{"kind":"word","headword":"intimate","pronunciations":[{"region":"BrE","ipa":"/ˈɪntɪmət/"}],"parts_of_speech":[{"name":"adjective","senses":[{"context_label":"of people 人","english_definition":"having a close and friendly relationship","chinese_definition":"亲密的；密切的","examples":[{"english":"We are on intimate terms.","chinese":"我们关系密切。","highlighted_phrase":"intimate terms"}]}]},{"name":"noun","senses":[{"context_label":null,"english_definition":"a very close friend","chinese_definition":"密友；知己","examples":[]}]}],"alternatives":[]}"#
```

Assert provider order, bilingual definitions, and the highlighted phrase. Add payloads with four parts of speech, four senses, three examples, and an empty Chinese definition; each must produce `.invalidResponse` after one repair attempt. Add one invalid highlighted phrase and assert the result keeps the example but clears its highlight.

- [ ] **Step 2: Verify RED**

Run `swift test --filter OpenAICompatibleProviderTests`.

Expected: rich payload decoding fails under the flat provider DTO.

- [ ] **Step 3: Replace the word instruction**

```swift
resultContract = """
Return exactly one JSON object with kind "word", a headword, 1–2 pronunciations, 1–3 common parts_of_speech, 1–3 senses per part of speech, and 0–2 bilingual examples per sense. Each new sense must include a concise English definition and a natural Simplified Chinese definition. context_label and highlighted_phrase may be null. highlighted_phrase must be copied exactly from its English example. Keep parts of speech in common dictionary order. Do not return surrounding book text.
"""
```

- [ ] **Step 4: Add nested provider DTOs**

`ProviderPayload` keeps passage fields and replaces flat word fields with:

```swift
let headword: String?
let pronunciations: [ProviderPronunciation]?
let partsOfSpeech: [ProviderPartOfSpeech]?
let alternatives: [String]?
```

Add private Decodable DTOs for pronunciation (`region`, `ipa`), part of speech (`name`, `senses`), sense (`context_label`, `english_definition`, `chinese_definition`, `examples`), and example (`english`, `chinese`, `highlighted_phrase`). Map their snake-case keys explicitly.

- [ ] **Step 5: Implement exact validation**

Require 1–3 groups, 1–3 senses per group, no more than two pronunciations, and no more than two examples per sense. Trim all strings. Require headword, group name, English definition, Chinese definition, and both sides of each example. Validate highlights with a case/diacritic-insensitive substring search and replace invalid highlights with `nil` rather than rejecting the example.

Return:

```swift
.word(WordLookupResult(
    headword: headword,
    pronunciations: mappedPronunciations,
    partsOfSpeech: mappedGroups,
    alternatives: payload.alternatives?.compactMap(\.nonEmpty) ?? []
))
```

- [ ] **Step 6: Update strict schema and token limits**

The word JSON-schema branch must mirror the nested DTOs, set `additionalProperties: false` at every object level, and use matching `minItems`/`maxItems`. Keep passage schema unchanged. Change the body field to:

```swift
"max_tokens": request.kind == .word ? 1_600 : 800,
```

- [ ] **Step 7: Verify GREEN and commit**

```bash
swift test --filter OpenAICompatibleProviderTests
git add Sources/LookupCore/OpenAICompatibleProvider.swift Tests/LookupCoreTests/OpenAICompatibleProviderTests.swift
git commit -m "feat: request rich bilingual dictionary entries"
```

Expected: OpenAI schema mode, DeepSeek JSON-object mode, repair, validation bounds, and injection-resistance tests pass.

---

### Task 4: Dictionary Presentation Components

**Files:**
- Create: `Apps/SharedUI/LookupActionBar.swift`
- Create: `Apps/SharedUI/WordDictionaryView.swift`
- Modify: `Apps/SharedUI/ResultCardView.swift`
- Modify: `Apps/SharedUI/LookupPanelView.swift`

- [ ] **Step 1: Extract the action bar without changing behavior**

Create `LookupActionBar` with `primaryText`, `isSaved`, `onToggleSaved`, and `onRetry`. Move the current platform-specific pasteboard copy and `SpeechController` behavior from `ResultCardView`. Preserve icon-only buttons, help text, and Chinese speech voice.

- [ ] **Step 2: Build the fixed header and anchor bar**

Create:

```swift
struct WordDictionaryView: View {
    let outcome: LookupOutcome
    let isSaved: Bool
    let onToggleSaved: () -> Void
    let onRetry: () -> Void
    let onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeAnchorID = ""
    @State private var sectionOffsets: [String: CGFloat] = [:]
}
```

The fixed header renders the serif headword, each pronunciation as `BrE /…/`, and dismiss. The anchor bar renders every group abbreviation in provider order and exposes the full group name to VoiceOver. Inside `ScrollViewReader`, anchor actions use:

```swift
if reduceMotion {
    proxy.scrollTo(group.anchorID, anchor: .top)
} else {
    withAnimation(.easeOut(duration: 0.22)) {
        proxy.scrollTo(group.anchorID, anchor: .top)
    }
}
activeAnchorID = group.anchorID
```

- [ ] **Step 3: Build the scrolling dictionary body**

Use a named coordinate space and this preference key:

```swift
private struct PartOfSpeechOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
```

Each full part-of-speech heading has `.id(group.anchorID)` and reports `minY`. On offset changes, mark the section nearest the scroll top active. Each sense uses a 30-point number column. Its paragraph concatenates muted context, optional English definition, and semibold Chinese definition. Examples render as bullets; split the English string around `validatedHighlightedPhrase`, bold the exact matching substring, and append the Chinese sentence in secondary color.

- [ ] **Step 4: Fix header/navigation/footer while only the body scrolls**

Place the header and anchor bar above the `ScrollView`, and `LookupActionBar` below it. Join all Chinese definitions with Chinese semicolons for the copy/speak primary text. Use system background/material, label colors, a thin blue active underline, system serif for the headword, and system/PingFang for body text.

- [ ] **Step 5: Route word and passage results separately**

In `LookupPanelView`, route `.result(.word)` directly to `WordDictionaryView`. Retain the existing branded idle, loading, failure, and passage structure. Remove the word branch from `ResultCardView`; keep passage translation, nuance note, literal disclosure, and the extracted action bar.

- [ ] **Step 6: Build both platforms and commit**

```bash
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorMac -configuration Debug -derivedDataPath .build/XcodeDerivedData-Mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorIOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/XcodeDerivedData-iOS CODE_SIGNING_ALLOWED=NO build
git add Apps/SharedUI/LookupActionBar.swift Apps/SharedUI/WordDictionaryView.swift Apps/SharedUI/ResultCardView.swift Apps/SharedUI/LookupPanelView.swift
git commit -m "feat: add bilingual dictionary word view"
```

Expected: both Apple targets build and passage presentation remains available.

---

### Task 5: Single Reusable Lookup Panel

**Files:**
- Create: `Apps/macOS/LookupPanel.swift`
- Create: `Tests/MacAppTests/LookupPanelTests.swift`
- Modify: `Apps/macOS/MacAppDelegate.swift`
- Modify: `Apps/macOS/MarginMacApp.swift`
- Modify: `project.yml`
- Regenerate: `BooksTranslator.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add a hosted macOS test target**

In `project.yml`, add `BooksTranslatorMacTests` as `bundle.unit-test`, platform macOS, source `Tests/MacAppTests`, and dependency `BooksTranslatorMac`. Set:

```yaml
TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Margin.app/Contents/MacOS/Margin"
BUNDLE_LOADER: "$(TEST_HOST)"
```

Add the test target to the `BooksTranslatorMac` scheme test action.

- [ ] **Step 2: Write failing identity and placement tests**

```swift
import AppKit
import XCTest
@testable import Margin

@MainActor
final class LookupPanelTests: XCTestCase {
    func testControllerReusesOnePanelInstance() {
        let controller = LookupPanelController()
        let session = LookupSession()
        XCTAssertTrue(controller.panel(session: session) === controller.panel(session: session))
    }

    func testFrameStaysInsideVisibleScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let frame = LookupPanelPlacement.frame(
            near: NSPoint(x: 1_430, y: 20),
            panelSize: NSSize(width: 540, height: 620),
            visibleFrame: visible
        )
        XCTAssertTrue(visible.contains(frame))
    }

    func testPanelHidesOnDeactivateAndEscape() {
        let panel = LookupPanelController().panel(session: LookupSession())
        XCTAssertTrue(panel.hidesOnDeactivate)
        panel.orderFront(nil)
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
    }
}
```

- [ ] **Step 3: Generate and verify RED**

```bash
xcodegen generate
xcodebuild test -project BooksTranslator.xcodeproj -scheme BooksTranslatorMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because the internal panel factory and placement policy do not exist.

- [ ] **Step 4: Implement panel Escape and placement behavior**

Create:

```swift
final class LookupPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

enum LookupPanelPlacement {
    static func frame(near point: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let gap: CGFloat = 14
        let preferredY = point.y - panelSize.height - gap
        let alternateY = point.y + gap
        let candidateY = preferredY >= visibleFrame.minY ? preferredY : alternateY
        let x = min(max(point.x + gap, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
        let y = min(max(candidateY, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
    }
}
```

- [ ] **Step 5: Move and expose the reusable controller**

Move `LookupPanelController` from `MacAppDelegate.swift` into `LookupPanel.swift`. Its internal `panel(session:)` lazily creates one 540 × 620 `LookupPanel`, stores it, and returns the same instance thereafter. Configure `hidesOnDeactivate = true`, `isReleasedWhenClosed = false`, floating level, `canJoinAllSpaces`, and `fullScreenAuxiliary`. `show(session:)` selects the screen containing `NSEvent.mouseLocation`, applies `LookupPanelPlacement`, makes the panel key, and activates Margin. If no screen contains the pointer, center the panel in `NSScreen.main?.visibleFrame` before falling back to the first available screen.

- [ ] **Step 6: Remove the duplicate SwiftUI lookup scene**

Delete the complete `Window("Margin", id: "lookup")` scene from `MarginMacApp`. Retain `MenuBarExtra`, Settings, and History. Route menu-bar, shortcut, Service, initial Dock launch, and `applicationShouldHandleReopen` through `showLookupPanel()`.

- [ ] **Step 7: Verify GREEN and commit**

```bash
xcodegen generate
xcodebuild test -project BooksTranslator.xcodeproj -scheme BooksTranslatorMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
! rg -n 'Window\("Margin"' Apps/macOS/MarginMacApp.swift
git add Apps/macOS/LookupPanel.swift Apps/macOS/MacAppDelegate.swift Apps/macOS/MarginMacApp.swift Tests/MacAppTests/LookupPanelTests.swift project.yml BooksTranslator.xcodeproj/project.pbxproj
git commit -m "fix: reuse one dismissible lookup panel"
```

Expected: hosted tests pass, repeated presentations use object identity, and no automatic lookup window remains.

---

### Task 6: Final Integration, Documentation, and Local Installation

**Files:**
- Modify: `Fixtures/evaluation-corpus.json`
- Modify: `README.md`
- Modify: `docs/compatibility-spike.md`

- [ ] **Step 1: Expand the deterministic evaluation corpus**

Add the ambiguous words `intimate`, `record`, and `close`. Each fixture must require ordered part-of-speech groups, numbered bilingual senses, and at least one bilingual example. Include one fixture whose highlighted phrase occurs more than once so the renderer proves it bolds only the explicit validated phrase rather than performing broad substring styling.

- [ ] **Step 2: Run the complete automated verification suite**

```bash
swift test
xcodegen generate
xcodebuild test -project BooksTranslator.xcodeproj -scheme BooksTranslatorMac -destination 'platform=macOS' -derivedDataPath .build/XcodeDerivedData-Mac CODE_SIGNING_ALLOWED=NO
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorIOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/XcodeDerivedData-iOS CODE_SIGNING_ALLOWED=NO build
```

Expected: all package tests and hosted macOS tests pass, and the iOS app plus Action Extension build successfully.

- [ ] **Step 3: Update user and compatibility documentation**

Update `README.md` with the new word-result anatomy, part-of-speech anchor behavior, Escape/deactivation dismissal, and the fact that passages retain the compact translation card. Update `docs/compatibility-spike.md` with the tested macOS/Xcode/Books version and the confirmed Control–Option–M path. Do not claim direct Apple Books Services or Action Extension compatibility unless it was manually observed.

- [ ] **Step 4: Build and install the verified local app**

```bash
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorMac -configuration Debug -derivedDataPath .build/XcodeDerivedData-Mac build
killall Margin
ditto .build/XcodeDerivedData-Mac/Build/Products/Debug/Margin.app "$HOME/Applications/Margin.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Margin.app"
open "$HOME/Applications/Margin.app"
```

Expected: one installed Margin process launches from `~/Applications/Margin.app`. If local signing fails, inspect the exact signing error rather than changing entitlements or Keychain access groups without a dedicated test.

- [ ] **Step 5: Perform manual acceptance checks**

Use deterministic mock/cached results unless the user explicitly approves a live cloud request. In Apple Books, verify:

1. Select a multi-part-of-speech word and press Control–Option–M.
2. Exactly one 540 × 620 panel appears near the pointer and remains within the visible screen.
3. The header shows pronunciations and POS anchors; clicking `adj.`, `n.`, or `v.` scrolls to the correct section.
4. Senses are numbered, English and Chinese definitions are inline, examples are bilingual, and the intended phrase alone is bold.
5. Footer copy, speak, save, and retry actions remain fixed and work.
6. Escape hides the panel; returning focus to Books hides it; the next shortcut reuses the same panel.
7. A passage selection still shows the natural translation card and optional nuance/literal details.
8. No additional Keychain prompt appears after the key has been authorized for the current signed app.

- [ ] **Step 6: Review the final diff and commit integration changes**

```bash
git diff --check
git status --short
git diff --stat
git add Fixtures/evaluation-corpus.json README.md docs/compatibility-spike.md
git commit -m "docs: document dictionary lookup experience"
```

Expected: no whitespace errors, no generated credentials or raw API responses, and only the intended feature files are changed.
