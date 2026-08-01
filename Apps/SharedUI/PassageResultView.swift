import Foundation
import LookupCore
import SwiftUI

struct PassagePresentationIdentity: Hashable {
    let originalText: String
    let translation: String
    let alignmentBlocks: [PassageAlignmentBlock]
    let nuanceNote: String?
    let literalGloss: String?
    let providerName: String
    let wasCached: Bool
    let outcomeID: UUID
}

enum PassageReadingMode: String, CaseIterable {
    case naturalTranslation
    case bilingualView

    static func initial(didStream: Bool) -> PassageReadingMode {
        didStream ? .bilingualView : .naturalTranslation
    }

    var title: LocalizedStringResource {
        switch self {
        case .naturalTranslation: "Natural Translation"
        case .bilingualView: "Bilingual View"
        }
    }
}

enum PassageReadingAvailability: Equatable {
    case naturalOnly
    case singleBlock
    case switchable

    init(alignmentBlockCount: Int) {
        switch alignmentBlockCount {
        case ...0:
            self = .naturalOnly
        case 1:
            self = .singleBlock
        default:
            self = .switchable
        }
    }

    var showsModePicker: Bool {
        self == .switchable
    }

    func effectiveMode(for requestedMode: PassageReadingMode) -> PassageReadingMode {
        switch self {
        case .naturalOnly:
            .naturalTranslation
        case .singleBlock, .switchable:
            requestedMode
        }
    }
}

struct PassageAlignmentDisplayBlock: Equatable {
    let sourceSentenceIDs: [Int]
    let sourceText: String
    let translation: String

    var sentenceLabel: String {
        guard let first = sourceSentenceIDs.first else { return "Sentence" }
        guard sourceSentenceIDs.count > 1, let last = sourceSentenceIDs.last else {
            return "Sentence \(first)"
        }
        return "Sentences \(first)–\(last)"
    }
}

enum PassageAlignmentPresentation {
    static func blocks(
        originalText: String,
        passage: PassageLookupResult
    ) -> [PassageAlignmentDisplayBlock] {
        blocks(
            originalText: originalText,
            alignmentBlocks: passage.alignmentBlocks
        )
    }

    static func blocks(
        originalText: String,
        alignmentBlocks: [PassageAlignmentBlock]
    ) -> [PassageAlignmentDisplayBlock] {
        blocks(
            sourceTextBySentenceID: sourceTextBySentenceID(originalText: originalText),
            alignmentBlocks: alignmentBlocks
        )
    }

    static func sourceTextBySentenceID(originalText: String) -> [Int: String] {
        Dictionary(
            uniqueKeysWithValues: PassageSentenceSegmenter.segment(originalText)
                .map { ($0.id, $0.text) }
        )
    }

    static func blocks(
        sourceTextBySentenceID: [Int: String],
        alignmentBlocks: [PassageAlignmentBlock]
    ) -> [PassageAlignmentDisplayBlock] {
        alignmentBlocks.compactMap { block in
            let translation = ChineseTypographyNormalizer.normalize(block.translation)
            guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return PassageAlignmentDisplayBlock(
                sourceSentenceIDs: block.sourceSentenceIDs,
                sourceText: block.sourceSentenceIDs
                    .compactMap { sourceTextBySentenceID[$0] }
                    .joined(separator: " "),
                translation: translation
            )
        }
    }
}

enum PassageVisibleContent {
    static func text(
        for mode: PassageReadingMode,
        originalText: String,
        passage: PassageLookupResult
    ) -> String {
        guard mode == .bilingualView, !passage.alignmentBlocks.isEmpty else {
            return ChineseTypographyNormalizer.normalize(passage.translation)
        }
        return PassageAlignmentPresentation.blocks(
            originalText: originalText,
            passage: passage
        ).map { block in
            "\(block.sourceText)\n\(block.translation)"
        }
        .joined(separator: "\n\n")
    }
}

struct PassagePresentationState {
    var readingMode: PassageReadingMode = .naturalTranslation
    var showsOriginalText = false
    var showsLiteralView = false
    var readingHeight: CGFloat = 0
    var actionHeight: CGFloat = 0
}

struct PassageResultView: View {
    let originalText: String
    let outcome: LookupOutcome
    let isSaved: Bool
    let onToggleSaved: () -> Void
    let onRetry: () -> Void
    let onDismiss: (() -> Void)?
    var initialReadingMode: PassageReadingMode = .naturalTranslation
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if case let .passage(passage) = outcome.result {
            let identity = PassagePresentationIdentity(
                originalText: originalText,
                translation: passage.translation,
                alignmentBlocks: passage.alignmentBlocks,
                nuanceNote: passage.nuanceNote,
                literalGloss: passage.literalGloss,
                providerName: outcome.providerName,
                wasCached: outcome.wasCached,
                outcomeID: outcome.id
            )
            PassageResultContent(
                originalText: originalText,
                outcome: outcome,
                passage: passage,
                isSaved: isSaved,
                onToggleSaved: onToggleSaved,
                onRetry: onRetry,
                onDismiss: onDismiss,
                initialReadingMode: initialReadingMode,
                onPreferredHeightChange: onPreferredHeightChange
            )
            .id(identity)
        }
    }
}

private struct PassageStreamingDisplayBlock: Identifiable {
    let id: String
    let block: PassageAlignmentDisplayBlock
    let isInProgress: Bool
}

private final class PassageSourceTextIndex: ObservableObject {
    let value: [Int: String]

    init(originalText: String) {
        value = PassageAlignmentPresentation.sourceTextBySentenceID(
            originalText: originalText
        )
    }
}

struct PassageStreamingView: View {
    let originalText: String
    let partial: PassagePartial
    let onCancel: () -> Void
    let onDismiss: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var sourceTextIndex: PassageSourceTextIndex
    @State private var readingHeight: CGFloat = 0
    @State private var actionHeight: CGFloat = 0

    init(
        originalText: String,
        partial: PassagePartial,
        onCancel: @escaping () -> Void,
        onDismiss: (() -> Void)?,
        onPreferredHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.originalText = originalText
        self.partial = partial
        self.onCancel = onCancel
        self.onDismiss = onDismiss
        self.onPreferredHeightChange = onPreferredHeightChange
        _sourceTextIndex = StateObject(
            wrappedValue: PassageSourceTextIndex(originalText: originalText)
        )
    }

    private var blocks: [PassageStreamingDisplayBlock] {
        var values = PassageAlignmentPresentation.blocks(
            sourceTextBySentenceID: sourceTextIndex.value,
            alignmentBlocks: partial.completedBlocks
        ).enumerated().map { index, block in
            PassageStreamingDisplayBlock(
                id: "completed-\(index)-\(block.sourceSentenceIDs)",
                block: block,
                isInProgress: false
            )
        }
        if !reduceMotion, let inProgress = partial.inProgress,
           !inProgress.text.isEmpty {
            let alignmentBlock = PassageAlignmentBlock(
                sourceSentenceIDs: inProgress.sourceSentenceIDs,
                translation: inProgress.text
            )
            if let block = PassageAlignmentPresentation.blocks(
                sourceTextBySentenceID: sourceTextIndex.value,
                alignmentBlocks: [alignmentBlock]
            ).first {
                values.append(PassageStreamingDisplayBlock(
                    id: "in-progress-\(inProgress.sourceSentenceIDs)",
                    block: block,
                    isInProgress: true
                ))
            }
        }
        return values
    }

    private var showsModePicker: Bool {
        partial.completedBlocks.count + (partial.inProgress == nil ? 0 : 1) >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MarginBrandHeader(
                        onDismiss: onDismiss,
                        closeAccessibilityLabel: "Cancel translation"
                    )
                    .padding(.bottom, showsModePicker ? 18 : 24)

                    if showsModePicker {
                        PassageReadingModePicker(
                            selection: .constant(.bilingualView)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .padding(.bottom, 22)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        sectionMarker(
                            marker: "EN / 中",
                            label: "BILINGUAL VIEW",
                            accessibilityLabel: "English and Chinese bilingual view",
                            onCancel: onCancel
                        )

                        ForEach(blocks) { block in
                            PassageAlignmentBlockView(
                                block: block.block,
                                isInProgress: block.isInProgress
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onNaturalHeightChange {
                    readingHeight = $0
                    reportPreferredHeight()
                }
            }

            LookupActionBar(
                primaryText: partial.prose,
                isSaved: false,
                onToggleSaved: {},
                onRetry: {},
                isEnabled: false
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .onNaturalHeightChange {
                actionHeight = $0
                reportPreferredHeight()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MarginTheme.canvas)
    }

    private func reportPreferredHeight() {
        guard readingHeight > 0, actionHeight > 0 else { return }
        onPreferredHeightChange?(readingHeight + actionHeight)
    }
}

private struct PassageAlignmentBlockView: View {
    let block: PassageAlignmentDisplayBlock
    var isInProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(block.sentenceLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(MarginTheme.accentForeground)

            PassageLanguageRow(marker: "EN") {
                Text(block.sourceText)
                    .font(.body)
                    .foregroundStyle(isInProgress ? .primary : .secondary)
                    .lineSpacing(3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isInProgress
                            ? MarginTheme.accent.opacity(0.13)
                            : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )
                    .textSelection(.enabled)
            }

            Divider()
                .padding(.leading, 30)

            PassageLanguageRow(marker: "中") {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    ChineseReadingTypography.passageText(block.translation)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .overlay(alignment: .bottomTrailing) {
                            if isInProgress {
                                StreamingCaret()
                                    .fixedSize()
                                    .offset(x: 2)
                            }
                        }
                }
                .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MarginTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MarginTheme.accent)
                .frame(width: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PassageLanguageRow<Content: View>: View {
    let marker: String
    let content: Content

    init(
        marker: String,
        @ViewBuilder content: () -> Content
    ) {
        self.marker = marker
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(marker)
                .font(.caption2.weight(.bold))
                .foregroundStyle(MarginTheme.accentForeground)
                .frame(width: 18, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StreamingCaret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            ChineseReadingTypography.passageText("▍")
                .lineSpacing(5)
                .foregroundStyle(MarginTheme.accentForeground)
                .opacity(
                    Int(context.date.timeIntervalSinceReferenceDate / 0.55)
                        .isMultiple(of: 2) ? 1 : 0.2
                )
        }
        .accessibilityHidden(true)
    }
}

private struct PassageReadingModePicker: View {
    @Binding var selection: PassageReadingMode

    var body: some View {
        Picker("Reading mode", selection: $selection) {
            ForEach(PassageReadingMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Passage reading mode")
    }
}

@MainActor
private func sectionMarker(
    marker: String,
    label: LocalizedStringResource,
    accessibilityLabel: LocalizedStringResource,
    onCancel: (() -> Void)? = nil
) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.caption.weight(.bold))
                .foregroundStyle(MarginTheme.accentForeground)
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))

        Spacer(minLength: 8)

        if let onCancel {
            Button("Cancel", action: onCancel)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
        }
    }
    .frame(minHeight: 18)
}

private struct PassageResultContent: View {
    let originalText: String
    let outcome: LookupOutcome
    let passage: PassageLookupResult
    let isSaved: Bool
    let onToggleSaved: () -> Void
    let onRetry: () -> Void
    let onDismiss: (() -> Void)?
    let onPreferredHeightChange: ((CGFloat) -> Void)?
    private let alignmentBlocks: [PassageAlignmentDisplayBlock]

    @State private var presentationState: PassagePresentationState

    init(
        originalText: String,
        outcome: LookupOutcome,
        passage: PassageLookupResult,
        isSaved: Bool,
        onToggleSaved: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onDismiss: (() -> Void)?,
        initialReadingMode: PassageReadingMode,
        onPreferredHeightChange: ((CGFloat) -> Void)?
    ) {
        self.originalText = originalText
        self.outcome = outcome
        self.passage = passage
        self.isSaved = isSaved
        self.onToggleSaved = onToggleSaved
        self.onRetry = onRetry
        self.onDismiss = onDismiss
        self.onPreferredHeightChange = onPreferredHeightChange
        alignmentBlocks = PassageAlignmentPresentation.blocks(
            originalText: originalText,
            passage: passage
        )
        _presentationState = State(
            initialValue: PassagePresentationState(
                readingMode: initialReadingMode
            )
        )
    }

    private var readingAvailability: PassageReadingAvailability {
        PassageReadingAvailability(alignmentBlockCount: alignmentBlocks.count)
    }

    private var effectiveReadingMode: PassageReadingMode {
        readingAvailability.effectiveMode(for: presentationState.readingMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, readingAvailability.showsModePicker ? 18 : 24)

                    if readingAvailability.showsModePicker {
                        readingModePicker
                            .padding(.bottom, 22)
                    }

                    switch effectiveReadingMode {
                    case .naturalTranslation:
                        naturalTranslationBody
                    case .bilingualView:
                        bilingualViewBody
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onNaturalHeightChange {
                    presentationState.readingHeight = $0
                    reportPreferredHeight()
                }
            }

            LookupActionBar(
                primaryText: PassageVisibleContent.text(
                    for: effectiveReadingMode,
                    originalText: originalText,
                    passage: passage
                ),
                isSaved: isSaved,
                onToggleSaved: onToggleSaved,
                onRetry: onRetry
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .onNaturalHeightChange {
                presentationState.actionHeight = $0
                reportPreferredHeight()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MarginTheme.canvas)
    }

    private var readingModePicker: some View {
        PassageReadingModePicker(selection: $presentationState.readingMode)
    }

    private var naturalTranslationBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionMarker(marker: "中", label: "自然译文", accessibilityLabel: "Natural Chinese translation")
                .padding(.bottom, 12)

            naturalTranslation(passage)

            Divider()
                .padding(.vertical, 22)

            DisclosureGroup(isExpanded: $presentationState.showsOriginalText) {
                CollapsibleOriginalText(text: originalText)
                    .padding(.top, 12)
            } label: {
                sectionMarker(
                    marker: "EN",
                    label: originalDisclosureTitle,
                    accessibilityLabel: "Original English text"
                )
            }
            .tint(MarginTheme.accentForeground)
        }
    }

    private var bilingualViewBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionMarker(
                marker: "EN / 中",
                label: "BILINGUAL VIEW",
                accessibilityLabel: "English and Chinese bilingual view"
            )

            ForEach(Array(alignmentBlocks.enumerated()), id: \.offset) { _, block in
                PassageAlignmentBlockView(block: block)
            }

            supplementaryDetails(includeLiteralGloss: false)
        }
    }

    private func reportPreferredHeight() {
        guard presentationState.readingHeight > 0, presentationState.actionHeight > 0 else { return }
        onPreferredHeightChange?(presentationState.readingHeight + presentationState.actionHeight)
    }

    private var header: some View {
        MarginBrandHeader(
            onDismiss: onDismiss,
            closeAccessibilityLabel: "Close translation"
        )
    }

    private var originalDisclosureTitle: LocalizedStringResource {
        presentationState.showsOriginalText ? "Hide English original" : "View English original"
    }

    private func naturalTranslation(_ passage: PassageLookupResult) -> some View {
        let translation = ChineseTypographyNormalizer.normalize(passage.translation)
        return VStack(alignment: .leading, spacing: 14) {
            ChineseReadingTypography.passageText(translation)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .accessibilityLabel("Natural translation: \(translation)")

            supplementaryDetails(includeLiteralGloss: true)
        }
        .padding(.leading, 16)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(MarginTheme.accent)
                .frame(width: 3)
        }
    }

    @ViewBuilder
    private func supplementaryDetails(includeLiteralGloss: Bool) -> some View {
        if !metadata.isEmpty {
            Text(metadata)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        if let nuanceNote = nonempty(passage.nuanceNote) {
            Text(nuanceNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    MarginTheme.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityLabel("Translation note: \(nuanceNote)")
        }

        if includeLiteralGloss, let literalGloss = nonempty(passage.literalGloss) {
            DisclosureGroup(isExpanded: $presentationState.showsLiteralView) {
                Text(literalGloss)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .textSelection(.enabled)
            } label: {
                Text("Literal view")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadata: String {
        ([outcome.wasCached ? String(localized: "Cached") : nil, nonempty(outcome.providerName)] as [String?])
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = ChineseTypographyNormalizer.normalize(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
