import LookupCore
import SwiftUI

struct WordDictionaryView: View {
    let outcome: LookupOutcome
    let isSaved: Bool
    let onToggleSaved: () -> Void
    let onRetry: () -> Void
    let onDismiss: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeAnchorID = ""

    var body: some View {
        Group {
            if case let .word(word) = outcome.result {
                dictionary(word)
            }
        }
        #if os(macOS)
        .frame(
            minWidth: 500,
            idealWidth: 500,
            maxWidth: 520,
            minHeight: 580,
            idealHeight: 580,
            maxHeight: 600
        )
        .onAppear { onPreferredHeightChange?(LookupPanelSizing.wordContentHeight) }
        #endif
    }

    private func dictionary(_ word: WordLookupResult) -> some View {
        let anchorIDs = word.partsOfSpeech.uniqueAnchorIDs
        let sections = Array(zip(word.partsOfSpeech, anchorIDs))
        let earlierSections = Array(sections.dropLast())
        let finalSection = sections.last
        let scrollContentPadding: CGFloat = 20

        return VStack(alignment: .leading, spacing: 0) {
            header(word)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    partOfSpeechNavigation(sections, proxy: proxy)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    Divider()

                    GeometryReader { viewport in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 26) {
                                ForEach(Array(earlierSections.enumerated()), id: \.element.1) { _, section in
                                    partOfSpeechSection(section.0, anchorID: section.1)
                                }

                                finalTail(
                                    section: finalSection,
                                    alternatives: word.alternatives,
                                    minHeight: max(
                                        0,
                                        viewport.size.height - scrollContentPadding
                                    )
                                )
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, scrollContentPadding)
                        }
                        .coordinateSpace(name: "wordDictionaryScroll")
                        .onPreferenceChange(PartOfSpeechOffsetKey.self) { offsets in
                            guard let closest = offsets.min(by: {
                                abs($0.value) < abs($1.value)
                            })?.key else { return }
                            activeAnchorID = closest
                        }
                    }
                }
                .onAppear {
                    if activeAnchorID.isEmpty {
                        activeAnchorID = anchorIDs.first ?? ""
                    }
                }
                .onChange(of: anchorIDs) { _, newIDs in
                    guard !newIDs.contains(activeAnchorID) else { return }
                    activeAnchorID = newIDs.first ?? ""
                }
            }

            LookupActionBar(
                primaryText: chineseDefinitions(in: word),
                isSaved: isSaved,
                onToggleSaved: onToggleSaved,
                onRetry: onRetry
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func header(_ word: WordLookupResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word.headword)
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close")
                    .accessibilityLabel("Close dictionary")
                }
            }

            if !word.pronunciations.isEmpty {
                HStack(spacing: 14) {
                    ForEach(Array(word.pronunciations.prefix(2).enumerated()), id: \.offset) { _, pronunciation in
                        Text(pronunciationText(pronunciation))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func partOfSpeechNavigation(
        _ sections: [(WordPartOfSpeech, String)],
        proxy: ScrollViewProxy
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(Array(sections.enumerated()), id: \.element.1) { _, section in
                    let group = section.0
                    let anchorID = section.1
                    Button {
                        activeAnchorID = anchorID
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                            proxy.scrollTo(anchorID, anchor: .top)
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(group.abbreviation)
                                .font(.callout.weight(.medium))
                            Rectangle()
                                .fill(anchorID == activeAnchorID ? MarginTheme.accentForeground : .clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(displayName(for: group))
                    .accessibilityLabel(displayName(for: group))
                    .accessibilityAddTraits(anchorID == activeAnchorID ? .isSelected : [])
                }
            }
        }
    }

    private func partOfSpeechSection(_ group: WordPartOfSpeech, anchorID: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(displayName(for: group))
                .font(.headline)

            ForEach(Array(group.senses.enumerated()), id: \.offset) { index, sense in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        definitionText(sense)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)

                        ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, example in
                            exampleView(example)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .id(anchorID)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PartOfSpeechOffsetKey.self,
                    value: [
                        anchorID: geometry.frame(in: .named("wordDictionaryScroll")).minY
                    ]
                )
            }
        }
    }

    private func finalTail(
        section: (WordPartOfSpeech, String)?,
        alternatives: [String],
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            if let section {
                partOfSpeechSection(section.0, anchorID: section.1)
            }
            alternativesView(alternatives)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func alternativesView(_ alternatives: [String]) -> some View {
        let values = alternatives.compactMap { nonempty($0) }
        if !values.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Also")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(values.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Other readings: \(values.joined(separator: ", "))")
        }
    }

    private func definitionText(_ sense: WordSense) -> Text {
        var text = Text("")
        if let context = nonempty(sense.contextLabel) {
            text = text + Text("\(context) ").foregroundStyle(.secondary)
        }
        if let english = nonempty(sense.englishDefinition) {
            text = text + Text("\(english) ")
        }
        if let chinese = nonempty(sense.chineseDefinition) {
            text = text + Text(chinese).fontWeight(.semibold)
        }
        return text
    }

    @ViewBuilder
    private func exampleView(_ example: WordExample) -> some View {
        let english = nonempty(example.english)
        let chinese = nonempty(example.chinese)

        if english != nil || chinese != nil {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 3) {
                    if english != nil {
                        highlightedEnglish(example)
                    }
                    if let chinese {
                        Text(chinese)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .lineSpacing(2)
                .textSelection(.enabled)
            }
        }
    }

    private func highlightedEnglish(_ example: WordExample) -> Text {
        example.highlightedEnglishSegments.reduce(Text("")) { text, segment in
            text + (segment.isHighlighted
                ? Text(segment.text).fontWeight(.bold)
                : Text(segment.text))
        }
    }

    private func chineseDefinitions(in word: WordLookupResult) -> String {
        word.partsOfSpeech
            .flatMap(\.senses)
            .compactMap { nonempty($0.chineseDefinition) }
            .joined(separator: "；")
    }

    private func pronunciationText(_ pronunciation: WordPronunciation) -> String {
        let region = nonempty(pronunciation.region)
        let ipa = pronunciation.ipa.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappedIPA = ipa.hasPrefix("/") && ipa.hasSuffix("/") ? ipa : "/\(ipa)/"
        return [region, wrappedIPA].compactMap { $0 }.joined(separator: " ")
    }

    private func displayName(for group: WordPartOfSpeech) -> String {
        nonempty(group.name) ?? String(localized: "Word")
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct PartOfSpeechOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
