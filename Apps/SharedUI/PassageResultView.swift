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
    case semanticAlignment

    var title: LocalizedStringResource {
        switch self {
        case .naturalTranslation: "Natural Translation"
        case .semanticAlignment: "Semantic Alignment"
        }
    }
}

enum PassageVisibleContent {
    static func text(
        for mode: PassageReadingMode,
        originalText: String,
        passage: PassageLookupResult
    ) -> String {
        guard mode == .semanticAlignment, !passage.alignmentBlocks.isEmpty else {
            return passage.translation
        }
        let sentences = Dictionary(
            uniqueKeysWithValues: PassageSentenceSegmenter.segment(originalText).map { ($0.id, $0.text) }
        )
        return passage.alignmentBlocks.map { block in
            let source = block.sourceSentenceIDs.compactMap { sentences[$0] }.joined(separator: " ")
            return "\(source)\n\(block.translation)"
        }
        .joined(separator: "\n\n")
    }
}

struct PassagePresentationState {
    var readingMode: PassageReadingMode = .naturalTranslation
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.bottom, passage.alignmentBlocks.isEmpty ? 24 : 18)

                    if !passage.alignmentBlocks.isEmpty {
                        readingModePicker
                            .padding(.bottom, 22)
                    } else {
                        Label("Semantic alignment was not generated for this lookup.", systemImage: "text.alignleft")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 18)
                    }

                    switch presentationState.readingMode {
                    case .naturalTranslation:
                        naturalTranslationBody
                    case .semanticAlignment:
                        semanticAlignmentBody
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
                    for: presentationState.readingMode,
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
            sectionMarker(marker: "EN", label: "ORIGINAL", accessibilityLabel: "Original English text")
                .padding(.bottom, 10)
            CollapsibleOriginalText(text: originalText)

            Divider()
                .padding(.vertical, 22)

            sectionMarker(marker: "中", label: "自然译文", accessibilityLabel: "Natural Chinese translation")
                .padding(.bottom, 12)

            naturalTranslation(passage)
        }
    }

    private var semanticAlignmentBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionMarker(
                marker: "EN / 中",
                label: "SEMANTIC ALIGNMENT",
                accessibilityLabel: "English and Chinese semantic alignment"
            )

            ForEach(Array(passage.alignmentBlocks.enumerated()), id: \.offset) { _, block in
                alignmentBlock(block)
            }

            supplementaryDetails(includeLiteralGloss: false)
        }
    }

    private func alignmentBlock(_ block: PassageAlignmentBlock) -> some View {
        let sentences = Dictionary(
            uniqueKeysWithValues: PassageSentenceSegmenter.segment(originalText).map { ($0.id, $0.text) }
        )
        let sourceText = block.sourceSentenceIDs.compactMap { sentences[$0] }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 10) {
            Text(sourceText)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)

            Text(block.translation)
                .font(.system(.title3, design: .serif))
                .lineSpacing(5)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MarginTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(MarginTheme.accent)
                .frame(width: 3)
        }
        .accessibilityElement(children: .combine)
    }

    private func reportPreferredHeight() {
        guard presentationState.readingHeight > 0, presentationState.actionHeight > 0 else { return }
        onPreferredHeightChange?(presentationState.readingHeight + presentationState.actionHeight)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MARGIN")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                Text("Context without leaving the page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close translation")
            }
        }
    }

    private func sectionMarker(
        marker: String,
        label: LocalizedStringKey,
        accessibilityLabel: LocalizedStringKey
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

    private func naturalTranslation(_ passage: PassageLookupResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(passage.translation)
                .font(.system(.title3, design: .serif))
                .lineSpacing(5)
                .textSelection(.enabled)
                .accessibilityLabel("Natural translation: \(passage.translation)")

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
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
