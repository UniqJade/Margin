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

    var title: LocalizedStringResource {
        switch self {
        case .naturalTranslation: "Natural Translation"
        case .bilingualView: "Bilingual View"
        }
    }
}

enum PassageReadingAvailability: Equatable {
    case naturalOnly
    case switchable

    init(alignmentBlockCount: Int) {
        self = alignmentBlockCount >= 2 ? .switchable : .naturalOnly
    }

    var showsModePicker: Bool {
        self == .switchable
    }

    func effectiveMode(for requestedMode: PassageReadingMode) -> PassageReadingMode {
        self == .switchable ? requestedMode : .naturalTranslation
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
        let sentences = Dictionary(
            uniqueKeysWithValues: PassageSentenceSegmenter.segment(originalText).map { ($0.id, $0.text) }
        )
        return passage.alignmentBlocks.map { block in
            PassageAlignmentDisplayBlock(
                sourceSentenceIDs: block.sourceSentenceIDs,
                sourceText: block.sourceSentenceIDs.compactMap { sentences[$0] }.joined(separator: " "),
                translation: ChineseTypographyNormalizer.normalize(block.translation)
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
                onPreferredHeightChange: onPreferredHeightChange
            )
            .id(identity)
        }
    }
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

    @State private var presentationState = PassagePresentationState()

    private var readingAvailability: PassageReadingAvailability {
        PassageReadingAvailability(alignmentBlockCount: passage.alignmentBlocks.count)
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
        Picker("Reading mode", selection: $presentationState.readingMode) {
            ForEach(PassageReadingMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Passage reading mode")
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

            ForEach(
                Array(
                    PassageAlignmentPresentation.blocks(
                        originalText: originalText,
                        passage: passage
                    ).enumerated()
                ),
                id: \.offset
            ) { _, block in
                alignmentBlock(block)
            }

            supplementaryDetails(includeLiteralGloss: false)
        }
    }

    private func alignmentBlock(_ block: PassageAlignmentDisplayBlock) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sentenceRangeLabel(for: block.sourceSentenceIDs)
                .font(.caption.weight(.bold))
                .foregroundStyle(MarginTheme.accentForeground)

            alignmentLanguageRow(marker: "EN") {
                Text(block.sourceText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

            Divider()
                .padding(.leading, 30)

            alignmentLanguageRow(marker: "中") {
                ChineseReadingTypography.passageText(block.translation)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
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

    private func alignmentLanguageRow<Content: View>(
        marker: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(marker)
                .font(.caption2.weight(.bold))
                .foregroundStyle(MarginTheme.accentForeground)
                .frame(width: 18, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sentenceRangeLabel(for sentenceIDs: [Int]) -> some View {
        if let first = sentenceIDs.first {
            if sentenceIDs.count > 1, let last = sentenceIDs.last {
                Text("Sentences \(first)–\(last)")
            } else {
                Text("Sentence \(first)")
            }
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

    private func sectionMarker(
        marker: String,
        label: LocalizedStringResource,
        accessibilityLabel: LocalizedStringResource
    ) -> some View {
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
