# Passage Panel and Universal Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved compact bilingual passage surface, adaptive macOS panel height, restrained orange visual system, and System/Light/Dark appearance preference across Margin's Mac, iPhone, iPad, and Action Extension surfaces without changing the four lookup action icons.

**Architecture:** Keep appearance as a small UI-layer value stored through the already injected `UserDefaults`, with `LookupSession` publishing changes to every scene. Replace the passage-only result card with a dedicated bilingual view, measure its natural SwiftUI content height, and let `LookupPanelController` clamp and animate a pure, unit-tested AppKit frame calculation while leaving the word dictionary at 540 × 620 points.

**Tech Stack:** Swift 6, SwiftUI, AppKit, UIKit, Combine, XCTest, XcodeGen 2.45.4, Xcode 26.6.

---

## File Map

- Create `Apps/SharedUI/MarginAppearance.swift`: appearance values, persistence key, semantic orange palette, and the reusable root view modifier.
- Create `Apps/SharedUI/CollapsibleOriginalText.swift`: four-line English source view and overflow measurement.
- Create `Apps/SharedUI/PassageResultView.swift`: approved bilingual passage hierarchy, optional details, and fixed action row.
- Create `Apps/SharedUI/NaturalHeightReader.swift`: small SwiftUI geometry callback used by compact and passage layouts.
- Modify `Apps/SharedUI/LookupSession.swift`: publish and persist appearance through the session's injected defaults.
- Modify `Apps/SharedUI/SettingsView.swift`: add the three-choice Appearance section.
- Modify `Apps/SharedUI/LookupPanelView.swift`: route passage outcomes to the new view and report natural panel height.
- Modify `Apps/SharedUI/WordDictionaryView.swift`: use the shared orange accent and report the fixed word height.
- Delete `Apps/SharedUI/ResultCardView.swift`: its passage card is replaced; no word code uses it.
- Modify `Apps/macOS/LookupPanel.swift`: clamp and animate reported heights while preserving the top edge.
- Modify `Apps/macOS/MarginMacApp.swift`: apply appearance to menu, Settings, and History roots.
- Modify `Apps/iOS/MarginIOSApp.swift`: apply appearance to the complete tab hierarchy.
- Modify `Apps/ActionExtension/ActionViewController.swift`: apply the shared appearance at the extension root.
- Modify `Tests/MacAppTests/LookupSessionTests.swift`: appearance default, load, save, and invalid-value coverage.
- Modify `Tests/MacAppTests/LookupPanelTests.swift`: adaptive height, fixed word height, bounds, and top-edge coverage.
- Create `Tests/MacAppTests/OriginalTextFoldPolicyTests.swift`: four-line overflow decision coverage.
- Modify `README.md`: document the bilingual layout and appearance controls.

`Apps/SharedUI/LookupActionBar.swift` is intentionally not modified. Its `doc.on.doc`, `speaker.wave.2`, `bookmark`/`bookmark.fill`, and `arrow.clockwise` symbols, order, labels, and handlers remain byte-for-byte unchanged.

### Task 1: Add test-driven appearance state and persistence

**Files:**
- Create: `Apps/SharedUI/MarginAppearance.swift`
- Modify: `Apps/SharedUI/LookupSession.swift`
- Test: `Tests/MacAppTests/LookupSessionTests.swift`

- [ ] **Step 1: Write failing tests for appearance loading and persistence**

Add these tests to `LookupSessionTests`:

```swift
func testAppearanceDefaultsToSystem() {
    let defaults = makeTemporaryDefaults()
    let session = LookupSession(
        defaults: defaults,
        vault: APIKeyVault(store: TestSecretStore()),
        loadInitialHistory: false,
        storageDirectory: makeTemporaryStorageDirectory()
    )

    XCTAssertEqual(session.appearance, .system)
}

func testAppearanceLoadsFromInjectedDefaults() {
    let defaults = makeTemporaryDefaults()
    defaults.set("dark", forKey: MarginAppearance.defaultsKey)

    let session = LookupSession(
        defaults: defaults,
        vault: APIKeyVault(store: TestSecretStore()),
        loadInitialHistory: false,
        storageDirectory: makeTemporaryStorageDirectory()
    )

    XCTAssertEqual(session.appearance, .dark)
}

func testInvalidAppearanceFallsBackToSystem() {
    let defaults = makeTemporaryDefaults()
    defaults.set("sepia", forKey: MarginAppearance.defaultsKey)

    let session = LookupSession(
        defaults: defaults,
        vault: APIKeyVault(store: TestSecretStore()),
        loadInitialHistory: false,
        storageDirectory: makeTemporaryStorageDirectory()
    )

    XCTAssertEqual(session.appearance, .system)
}

func testSetAppearancePublishesAndPersistsToInjectedDefaults() {
    let defaults = makeTemporaryDefaults()
    let session = LookupSession(
        defaults: defaults,
        vault: APIKeyVault(store: TestSecretStore()),
        loadInitialHistory: false,
        storageDirectory: makeTemporaryStorageDirectory()
    )

    session.setAppearance(.light)

    XCTAssertEqual(session.appearance, .light)
    XCTAssertEqual(defaults.string(forKey: MarginAppearance.defaultsKey), "light")
}
```

- [ ] **Step 2: Run the hosted tests and verify the new tests fail**

Run:

```bash
./scripts/test-mac.sh
```

Expected: compilation fails because `MarginAppearance`, `LookupSession.appearance`, and `setAppearance` do not exist.

- [ ] **Step 3: Create the appearance model, semantic palette, and root modifier**

Create `Apps/SharedUI/MarginAppearance.swift` with:

```swift
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum MarginAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "margin.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MarginTheme {
    static let accent = adaptiveColor(
        light: RGB(red: 0xD9, green: 0x77, blue: 0x45),
        dark: RGB(red: 0xE7, green: 0x89, blue: 0x58)
    )
    static let canvas = adaptiveColor(
        light: RGB(red: 0xFA, green: 0xF9, blue: 0xF7),
        dark: RGB(red: 0x17, green: 0x16, blue: 0x14)
    )
    static let elevatedSurface = adaptiveColor(
        light: RGB(red: 0xF1, green: 0xF0, blue: 0xED),
        dark: RGB(red: 0x22, green: 0x20, blue: 0x1D)
    )

    private struct RGB {
        let red: Int
        let green: Int
        let blue: Int

        var components: (CGFloat, CGFloat, CGFloat) {
            (CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255)
        }
    }

    private static func adaptiveColor(light: RGB, dark: RGB) -> Color {
        #if os(macOS)
        let color = NSColor(name: nil) { appearance in
            nativeColor(
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            )
        }
        return Color(nsColor: color)
        #else
        return Color(uiColor: UIColor { traits in
            nativeColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
        #endif
    }

    #if os(macOS)
    private static func nativeColor(_ rgb: RGB) -> NSColor {
        let value = rgb.components
        return NSColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
    }
    #else
    private static func nativeColor(_ rgb: RGB) -> UIColor {
        let value = rgb.components
        return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
    }
    #endif
}

private struct MarginAppearanceModifier: ViewModifier {
    @ObservedObject var session: LookupSession

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(session.appearance.preferredColorScheme)
            .tint(MarginTheme.accent)
    }
}

extension View {
    func marginAppearance(session: LookupSession) -> some View {
        modifier(MarginAppearanceModifier(session: session))
    }
}
```

- [ ] **Step 4: Publish appearance from `LookupSession`**

Add the property beside the other published state:

```swift
@Published private(set) var appearance: MarginAppearance
```

Initialize it before the rest of the injected resources in `LookupSession.init`:

```swift
appearance = MarginAppearance(
    rawValue: defaults.string(forKey: MarginAppearance.defaultsKey) ?? ""
) ?? .system
```

Add this public mutation beside the settings methods:

```swift
func setAppearance(_ appearance: MarginAppearance) {
    self.appearance = appearance
    defaults.set(appearance.rawValue, forKey: MarginAppearance.defaultsKey)
}
```

- [ ] **Step 5: Run hosted tests and verify appearance tests pass**

Run:

```bash
./scripts/test-mac.sh
```

Expected: all hosted Mac tests pass, including the four new appearance tests.

- [ ] **Step 6: Commit appearance state**

```bash
git add Apps/SharedUI/MarginAppearance.swift Apps/SharedUI/LookupSession.swift Tests/MacAppTests/LookupSessionTests.swift
git commit -m "Add universal Margin appearance preference"
```

### Task 2: Expose and apply appearance on every platform

**Files:**
- Modify: `Apps/SharedUI/SettingsView.swift`
- Modify: `Apps/macOS/MarginMacApp.swift`
- Modify: `Apps/macOS/LookupPanel.swift`
- Modify: `Apps/iOS/MarginIOSApp.swift`
- Modify: `Apps/ActionExtension/ActionViewController.swift`

- [ ] **Step 1: Add the native three-choice Appearance section**

Insert this as the first section in `SettingsView`'s `Form`:

```swift
Section("Appearance") {
    Picker("Appearance", selection: Binding(
        get: { session.appearance },
        set: { session.setAppearance($0) }
    )) {
        ForEach(MarginAppearance.allCases) { appearance in
            Text(appearance.title).tag(appearance)
        }
    }
    .pickerStyle(.segmented)

    Text("Follow System changes automatically with this device. Light and Dark affect Margin only.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Apply the preference to all macOS-owned roots**

In `MarginMacApp`, apply the modifier to each root view:

```swift
MenuBarContent(session: appDelegate.session) {
    appDelegate.showLookupPanel()
}
.marginAppearance(session: appDelegate.session)
```

```swift
SettingsView(session: appDelegate.session)
    .marginAppearance(session: appDelegate.session)
```

```swift
HistoryView(session: appDelegate.session)
    .marginAppearance(session: appDelegate.session)
```

In `LookupPanelController.panel(session:)`, wrap the hosted root before constructing the hosting controller:

```swift
let rootView = LookupPanelView(
    session: session,
    onDismiss: { [weak self, weak panel] in
        self?.onDismiss()
        panel?.orderOut(nil)
    }
)
.marginAppearance(session: session)
panel.contentViewController = NSHostingController(rootView: rootView)
```

- [ ] **Step 3: Apply the preference to the complete iPhone/iPad hierarchy**

In `MarginIOSApp`, add the modifier to the `TabView` after its tabs:

```swift
TabView {
    // Keep the existing Lookup, History, and Settings tabs unchanged.
}
.marginAppearance(session: session)
```

The existing `@StateObject private var session = LookupSession()` continues to use `SharedConfiguration.defaults`, which is the iOS App Group suite.

- [ ] **Step 4: Apply the same preference to the Action Extension root**

Change the root construction in `ActionViewController.viewDidLoad` to:

```swift
let root = ActionExtensionRootView(session: session) { [weak self] in self?.done() }
    .marginAppearance(session: session)
let host = UIHostingController(rootView: root)
```

Because both targets compile `SharedConfiguration.swift` under iOS, they read the locally configured App Group identifier and therefore share the appearance value without cloud synchronization.

- [ ] **Step 5: Regenerate and compile both platform targets**

Run:

```bash
xcodegen generate
./scripts/test-mac.sh
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorIOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: Mac tests pass and the iOS app plus embedded Action Extension build successfully.

- [ ] **Step 6: Commit cross-platform appearance wiring**

```bash
git add Apps/SharedUI/SettingsView.swift Apps/macOS/MarginMacApp.swift Apps/macOS/LookupPanel.swift Apps/iOS/MarginIOSApp.swift Apps/ActionExtension/ActionViewController.swift
git commit -m "Apply Margin appearance across Apple platforms"
```

### Task 3: Replace the passage card with the approved bilingual page

**Files:**
- Create: `Apps/SharedUI/CollapsibleOriginalText.swift`
- Create: `Apps/SharedUI/PassageResultView.swift`
- Modify: `Apps/SharedUI/LookupPanelView.swift`
- Modify: `Apps/SharedUI/WordDictionaryView.swift`
- Delete: `Apps/SharedUI/ResultCardView.swift`
- Test: `Tests/MacAppTests/OriginalTextFoldPolicyTests.swift`

- [ ] **Step 1: Write a failing unit test for actual-height overflow decisions**

Create `Tests/MacAppTests/OriginalTextFoldPolicyTests.swift`:

```swift
import XCTest
@testable import Margin

final class OriginalTextFoldPolicyTests: XCTestCase {
    func testEqualHeightsDoNotOfferExpansion() {
        XCTAssertFalse(OriginalTextFoldPolicy.isTruncated(fullHeight: 80, collapsedHeight: 80))
    }

    func testFullTextTallerThanFourLineMeasurementOffersExpansion() {
        XCTAssertTrue(OriginalTextFoldPolicy.isTruncated(fullHeight: 120, collapsedHeight: 80))
    }

    func testSubpixelMeasurementNoiseDoesNotOfferExpansion() {
        XCTAssertFalse(OriginalTextFoldPolicy.isTruncated(fullHeight: 80.4, collapsedHeight: 80))
    }
}
```

- [ ] **Step 2: Run hosted tests and verify the fold-policy test fails**

Run:

```bash
./scripts/test-mac.sh
```

Expected: compilation fails because `OriginalTextFoldPolicy` does not exist.

- [ ] **Step 3: Build the four-line original-text component**

Create `Apps/SharedUI/CollapsibleOriginalText.swift`:

```swift
import SwiftUI

enum OriginalTextFoldPolicy {
    static func isTruncated(fullHeight: CGFloat, collapsedHeight: CGFloat) -> Bool {
        fullHeight > collapsedHeight + 0.5
    }
}

struct CollapsibleOriginalText: View {
    let text: String

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private var isTruncated: Bool {
        OriginalTextFoldPolicy.isTruncated(
            fullHeight: fullHeight,
            collapsedHeight: collapsedHeight
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .lineLimit(isExpanded ? nil : 4)
                .textSelection(.enabled)
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        measuredText(lineLimit: nil)
                            .background(heightReader(FullTextHeightKey.self))
                        measuredText(lineLimit: 4)
                            .background(heightReader(CollapsedTextHeightKey.self))
                    }
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }

            if isTruncated {
                Button(isExpanded ? "Collapse original" : "Expand original") {
                    isExpanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(MarginTheme.accent)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }
        }
        .onPreferenceChange(FullTextHeightKey.self) { fullHeight = $0 }
        .onPreferenceChange(CollapsedTextHeightKey.self) { collapsedHeight = $0 }
    }

    private func measuredText(lineLimit: Int?) -> some View {
        Text(text)
            .font(.system(.body, design: .serif))
            .lineSpacing(2)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func heightReader<K: PreferenceKey>(_ type: K.Type) -> some View where K.Value == CGFloat {
        GeometryReader { geometry in
            Color.clear.preference(key: type, value: geometry.size.height)
        }
    }
}

private struct FullTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CollapsedTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
```

- [ ] **Step 4: Create the bilingual passage result view while preserving the action bar**

Create `Apps/SharedUI/PassageResultView.swift`:

```swift
import LookupCore
import SwiftUI

struct PassageResultView: View {
    let originalText: String
    let outcome: LookupOutcome
    let isSaved: Bool
    let onToggleSaved: () -> Void
    let onRetry: () -> Void
    let onDismiss: (() -> Void)?

    @State private var showsLiteralGloss = false

    var body: some View {
        Group {
            if case let .passage(passage) = outcome.result {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header
                            originalSection
                            Divider()
                            translationSection(passage)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 14)
                    }

                    LookupActionBar(
                        primaryText: passage.translation,
                        isSaved: isSaved,
                        onToggleSaved: onToggleSaved,
                        onRetry: onRetry
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                }
                .background(MarginTheme.canvas)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MARGIN")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                Text("Context without leaving the page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Close")
            }
        }
    }

    private var originalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            languageLabel(marker: "EN", title: "ORIGINAL")
            CollapsibleOriginalText(text: originalText)
        }
    }

    private func translationSection(_ passage: PassageLookupResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                languageLabel(marker: "中", title: "自然译文")
                Spacer()
                if outcome.wasCached {
                    Label("Cached", systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(outcome.providerName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(passage.translation)
                    .font(.system(.title3, design: .serif))
                    .lineSpacing(5)
                    .textSelection(.enabled)

                if let note = nonempty(passage.nuanceNote) {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MarginTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 10))
                }

                if let literal = nonempty(passage.literalGloss) {
                    DisclosureGroup("Literal view", isExpanded: $showsLiteralGloss) {
                        Text(literal)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    .font(.caption)
                }
            }
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(MarginTheme.accent)
                    .frame(width: 3)
            }
        }
    }

    private func languageLabel(marker: String, title: String) -> some View {
        HStack(spacing: 7) {
            Text(marker).foregroundStyle(MarginTheme.accent)
            Text(title).foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.bold))
        .tracking(1.2)
        .accessibilityElement(children: .combine)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

- [ ] **Step 5: Route passage outcomes to the new view**

Restructure `LookupPanelView.body` into three branches:

```swift
@ViewBuilder
var body: some View {
    if case let .result(outcome) = session.phase,
       case .word = outcome.result {
        WordDictionaryView(
            outcome: outcome,
            isSaved: session.isSaved(id: outcome.historyEntryID),
            onToggleSaved: {
                if let id = outcome.historyEntryID { session.toggleSaved(id: id) }
            },
            onRetry: session.retry,
            onDismiss: onDismiss
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else if case let .result(outcome) = session.phase,
              case .passage = outcome.result {
        PassageResultView(
            originalText: session.selection,
            outcome: outcome,
            isSaved: session.isSaved(id: outcome.historyEntryID),
            onToggleSaved: {
                if let id = outcome.historyEntryID { session.toggleSaved(id: id) }
            },
            onRetry: session.retry,
            onDismiss: onDismiss
        )
    } else {
        ScrollView { standardPanel }
            .background(MarginTheme.canvas)
    }
}
```

Remove the `.result(outcome)` case and its `ResultCardView` call from `standardPanel`; passage results no longer reach that switch branch. Delete `Apps/SharedUI/ResultCardView.swift`.

- [ ] **Step 6: Replace the word view's private blue with the shared accent**

Change the active underline in `WordDictionaryView` to:

```swift
.fill(anchorID == activeAnchorID ? MarginTheme.accent : .clear)
```

Delete the private `marginBlue` computed property. Do not change the dictionary layout, anchor behavior, or `LookupActionBar` invocation.

- [ ] **Step 7: Run tests and compile both platforms**

Run:

```bash
./scripts/test-mac.sh
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorIOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: fold-policy and existing Mac tests pass; iOS app and extension compile with the new shared views.

- [ ] **Step 8: Commit the bilingual passage page**

```bash
git add Apps/SharedUI/CollapsibleOriginalText.swift Apps/SharedUI/PassageResultView.swift Apps/SharedUI/LookupPanelView.swift Apps/SharedUI/WordDictionaryView.swift Apps/SharedUI/ResultCardView.swift Tests/MacAppTests/OriginalTextFoldPolicyTests.swift
git commit -m "Build compact bilingual passage results"
```

### Task 4: Add measured, adaptive macOS panel height

**Files:**
- Create: `Apps/SharedUI/NaturalHeightReader.swift`
- Modify: `Apps/SharedUI/LookupPanelView.swift`
- Modify: `Apps/SharedUI/PassageResultView.swift`
- Modify: `Apps/SharedUI/WordDictionaryView.swift`
- Modify: `Apps/macOS/LookupPanel.swift`
- Test: `Tests/MacAppTests/LookupPanelTests.swift`

- [ ] **Step 1: Replace fixed-size expectations with failing sizing-policy tests**

Keep the existing placement and single-panel tests. Replace `testControllerRestoresPreferredContentSizeAfterSmallScreen` and add these pure-policy tests:

```swift
func testSizingClampsCompactHeightToMinimum() {
    let size = LookupPanelSizing.contentSize(
        reportedHeight: 180,
        availableContentSize: NSSize(width: 1_000, height: 800)
    )

    XCTAssertEqual(size, NSSize(width: 540, height: 280))
}

func testSizingUsesMeasuredPassageHeightInsideBounds() {
    let size = LookupPanelSizing.contentSize(
        reportedHeight: 430,
        availableContentSize: NSSize(width: 1_000, height: 800)
    )

    XCTAssertEqual(size, NSSize(width: 540, height: 430))
}

func testSizingClampsLongPassageToMaximum() {
    let size = LookupPanelSizing.contentSize(
        reportedHeight: 900,
        availableContentSize: NSSize(width: 1_000, height: 800)
    )

    XCTAssertEqual(size, NSSize(width: 540, height: 620))
}

func testSizingShrinksToSmallVisibleContentArea() {
    let size = LookupPanelSizing.contentSize(
        reportedHeight: 620,
        availableContentSize: NSSize(width: 400, height: 300)
    )

    XCTAssertEqual(size, NSSize(width: 400, height: 300))
}

func testResizePreservesTopEdge() {
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let current = NSRect(x: 400, y: 140, width: 540, height: 620)

    let resized = LookupPanelSizing.framePreservingTopEdge(
        currentFrame: current,
        targetFrameSize: NSSize(width: 540, height: 360),
        visibleFrame: visible
    )

    XCTAssertEqual(resized.maxY, current.maxY, accuracy: 0.5)
    XCTAssertTrue(visible.contains(resized))
}
```

- [ ] **Step 2: Run hosted tests and verify the sizing tests fail**

Run:

```bash
./scripts/test-mac.sh
```

Expected: compilation fails because `LookupPanelSizing` does not exist.

- [ ] **Step 3: Add the reusable natural-height callback**

Create `Apps/SharedUI/NaturalHeightReader.swift`:

```swift
import SwiftUI

extension View {
    func onNaturalHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { geometry in
            ceil(geometry.size.height)
        } action: { height in
            guard height > 0 else { return }
            action(height)
        }
    }
}
```

The deployment targets are macOS 15 and iOS 18, so `onGeometryChange` is available without compatibility shims.

- [ ] **Step 4: Report natural height from compact, passage, and word branches**

Add this callback to `LookupPanelView`:

```swift
var onPreferredHeightChange: ((CGFloat) -> Void)? = nil
```

For the standard branch, measure the natural child rather than the assigned `ScrollView` viewport:

```swift
ScrollView {
    standardPanel
        .onNaturalHeightChange { onPreferredHeightChange?($0) }
}
.background(MarginTheme.canvas)
```

Add the same callback to `PassageResultView` and store its two measured regions:

```swift
var onPreferredHeightChange: ((CGFloat) -> Void)? = nil
@State private var readingHeight: CGFloat = 0
@State private var actionHeight: CGFloat = 0
```

Measure the content `VStack` inside its `ScrollView`:

```swift
.onNaturalHeightChange {
    readingHeight = $0
    reportPreferredHeight()
}
```

Measure the padded `LookupActionBar` region:

```swift
.onNaturalHeightChange {
    actionHeight = $0
    reportPreferredHeight()
}
```

Add:

```swift
private func reportPreferredHeight() {
    guard readingHeight > 0, actionHeight > 0 else { return }
    onPreferredHeightChange?(readingHeight + actionHeight)
}
```

Pass the callback from `LookupPanelView` into `PassageResultView`. Add an optional callback to `WordDictionaryView` and report the fixed policy on appearance:

```swift
var onPreferredHeightChange: ((CGFloat) -> Void)? = nil
```

```swift
.onAppear { onPreferredHeightChange?(LookupPanelSizing.wordContentHeight) }
```

Because `LookupPanelSizing` is macOS-only, wrap the word report in `#if os(macOS)` and pass `nil` from iOS callers. Keep the existing macOS dictionary size frame unchanged.

- [ ] **Step 5: Implement the pure panel sizing policy**

Add above `LookupPanelController` in `Apps/macOS/LookupPanel.swift`:

```swift
enum LookupPanelSizing {
    static let preferredWidth: CGFloat = 540
    static let minimumContentHeight: CGFloat = 280
    static let maximumContentHeight: CGFloat = 620
    static let initialContentHeight: CGFloat = 360
    static let wordContentHeight: CGFloat = 620

    static func contentSize(
        reportedHeight: CGFloat,
        availableContentSize: NSSize
    ) -> NSSize {
        NSSize(
            width: min(preferredWidth, max(availableContentSize.width, 0)),
            height: min(
                max(reportedHeight, min(minimumContentHeight, availableContentSize.height)),
                min(maximumContentHeight, max(availableContentSize.height, 0))
            )
        )
    }

    static func framePreservingTopEdge(
        currentFrame: NSRect,
        targetFrameSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        var frame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - targetFrameSize.height,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )
        frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        return frame
    }
}
```

- [ ] **Step 6: Let the controller accept measured heights without resize loops**

Replace `preferredContentSize` with a compatibility value backed by the policy and add stored state:

```swift
static let preferredContentSize = NSSize(
    width: LookupPanelSizing.preferredWidth,
    height: LookupPanelSizing.wordContentHeight
)
private var reportedContentHeight = LookupPanelSizing.initialContentHeight
```

Pass the new callback into the hosted root:

```swift
onPreferredHeightChange: { [weak self, weak panel] height in
    guard let self, let panel else { return }
    self.updatePreferredHeight(height, for: panel)
}
```

Implement the update and top-edge-preserving resize:

```swift
private func updatePreferredHeight(_ height: CGFloat, for panel: LookupPanel) {
    guard abs(reportedContentHeight - height) >= 1 else { return }
    reportedContentHeight = height
    guard panel.isVisible,
          let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

    let availableContentSize = panel.contentRect(forFrameRect: screen.visibleFrame).size
    let targetContentSize = LookupPanelSizing.contentSize(
        reportedHeight: height,
        availableContentSize: availableContentSize
    )
    let targetFrameSize = panel.frameRect(
        forContentRect: NSRect(origin: .zero, size: targetContentSize)
    ).size
    let targetFrame = LookupPanelSizing.framePreservingTopEdge(
        currentFrame: panel.frame,
        targetFrameSize: targetFrameSize,
        visibleFrame: screen.visibleFrame
    )
    let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    panel.setFrame(targetFrame, display: true, animate: animate)
}
```

Update `prepareSizing` to use `reportedContentHeight` and the policy instead of always using 620. Configure `contentMinSize` using the available width and a height no larger than 280; configure `contentMaxSize` using the available width and a height no larger than 620. Keep `LookupPanelPlacement.frame` as the initial placement algorithm.

- [ ] **Step 7: Run the adaptive sizing tests**

Run:

```bash
./scripts/test-mac.sh
```

Expected: existing panel reuse/placement/dismissal tests and all new sizing-policy tests pass.

- [ ] **Step 8: Compile the iOS views after adding optional callbacks**

Run:

```bash
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorIOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: iOS app and Action Extension compile; they ignore AppKit frame sizing and use their existing platform containers.

- [ ] **Step 9: Commit adaptive panel sizing**

```bash
git add Apps/SharedUI/NaturalHeightReader.swift Apps/SharedUI/LookupPanelView.swift Apps/SharedUI/PassageResultView.swift Apps/SharedUI/WordDictionaryView.swift Apps/macOS/LookupPanel.swift Tests/MacAppTests/LookupPanelTests.swift
git commit -m "Resize passage panels to their content"
```

### Task 5: Documentation, full verification, and fixed-app installation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the lookup-experience documentation**

Replace the old sentence/passage paragraph in `README.md` with:

```markdown
Sentence and passage results use a compact bilingual reading layout: the selected English text appears above the natural Simplified Chinese translation, long originals fold after four lines, and nuance or literal notes appear only when useful. On Mac, short results shrink the panel to their content while long passages scroll within the panel and keep **Copy**, **Speak**, **Save**, and **Retry** visible.

Margin offers **Follow System**, **Light**, and **Dark** appearance choices in Settings. The preference is local to each device; the iPhone/iPad app and Action Extension share the choice through their existing App Group. Margin uses a restrained warm-orange accent, while system permission dialogs retain the operating system's appearance.
```

- [ ] **Step 2: Verify formatting and generated project consistency**

Run:

```bash
git diff --check
xcodegen generate
git status --short
```

Expected: no whitespace errors. Only intentional source, test, documentation, and generated-project changes appear; ignored `.build` and `.superpowers` files do not enter the commit.

- [ ] **Step 3: Run the package and hosted Mac test suites**

Run:

```bash
swift test
./scripts/test-mac.sh
```

Expected: all package tests and hosted Mac tests pass.

- [ ] **Step 4: Build the complete iOS app and Action Extension**

Run:

```bash
xcodebuild -project BooksTranslator.xcodeproj -scheme BooksTranslatorIOS -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` for the app and embedded extension.

- [ ] **Step 5: Perform focused manual acceptance before installation**

Using the Xcode Mac run only for development inspection, verify:

1. A short passage panel is approximately its natural height and has no large empty lower region.
2. A long original is four lines until “Expand original” is activated.
3. A long result scrolls while the action row stays visible.
4. Word results remain approximately 540 × 620 points with working `adj.`/`n.`/`v.` anchors.
5. Follow System, Light, and Dark update lookup, Settings, and History without restarting.
6. The copy, speak, save, and retry symbols and order match the pre-change build.
7. Escape and returning to Apple Books still dismiss the lookup panel.

- [ ] **Step 6: Commit documentation and any generated project update**

```bash
git add README.md BooksTranslator.xcodeproj
git commit -m "Document passage layout and appearance controls"
```

If `BooksTranslator.xcodeproj` is ignored or unchanged after XcodeGen, add only `README.md`.

- [ ] **Step 7: Install the verified signed daily-use build**

Run:

```bash
./scripts/install-mac.sh
```

Expected: the script verifies the Apple Development identity and installs exactly one signed app at `~/Applications/Margin.app`. If the user declines the filesystem approval or signing verification fails, leave the tested source build intact and report that only fixed-app installation remains.

- [ ] **Step 8: Verify the installed app manually**

Launch `~/Applications/Margin.app`, select a short sentence in Apple Books, and press Control–Option–M. Confirm the compact bilingual panel, chosen appearance, stable Accessibility authorization, unchanged action icons, and absence of a second Spotlight Margin result.
