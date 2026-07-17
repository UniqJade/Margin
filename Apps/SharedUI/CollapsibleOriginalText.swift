import SwiftUI

enum OriginalTextFoldPolicy {
    static func isTruncated(fullHeight: CGFloat, collapsedHeight: CGFloat) -> Bool {
        fullHeight - collapsedHeight > 0.5
    }
}

struct OriginalTextFoldState {
    var isExpanded = false
    var fullHeight: CGFloat = 0
    var collapsedHeight: CGFloat = 0

    var isTruncated: Bool {
        OriginalTextFoldPolicy.isTruncated(
            fullHeight: fullHeight,
            collapsedHeight: collapsedHeight
        )
    }
}

struct OriginalTextPresentationIdentity: Hashable {
    let text: String
}

struct CollapsibleOriginalText: View {
    let text: String

    var body: some View {
        CollapsibleOriginalTextContent(text: text)
            .id(OriginalTextPresentationIdentity(text: text))
    }
}

private struct CollapsibleOriginalTextContent: View {
    let text: String

    @State private var foldState = OriginalTextFoldState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            prose
                .lineLimit(foldState.isExpanded ? nil : 4)
                .overlay(alignment: .topLeading) {
                    measurementCopies
                }

            if foldState.isTruncated {
                Button {
                    foldState.isExpanded.toggle()
                } label: {
                    foldButtonLabel
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MarginTheme.accentForeground)
                .accessibilityValue(Text(foldAccessibilityValue))
                #if os(iOS)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
        }
        .onPreferenceChange(OriginalTextHeightPreferenceKey.self) { heights in
            foldState.fullHeight = heights[.init(text: text, kind: .full)] ?? 0
            foldState.collapsedHeight = heights[.init(text: text, kind: .collapsed)] ?? 0
        }
    }

    @ViewBuilder
    private var foldButtonLabel: some View {
        #if os(iOS)
        Text(foldButtonTitle)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        #else
        Text(foldButtonTitle)
        #endif
    }

    private var foldButtonTitle: LocalizedStringResource {
        foldState.isExpanded ? "Collapse original" : "Expand original"
    }

    private var foldAccessibilityValue: LocalizedStringResource {
        foldState.isExpanded ? "Expanded" : "Collapsed"
    }

    private var prose: some View {
        Text(text)
            .font(.system(.body, design: .serif))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measurementCopies: some View {
        ZStack(alignment: .topLeading) {
            measurementText
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .measureOriginalTextHeight(as: .full, for: text)

            measurementText
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .measureOriginalTextHeight(as: .collapsed, for: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hidden()
        .focusable(false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var measurementText: some View {
        Text(text)
            .font(.system(.body, design: .serif))
            .lineSpacing(3)
    }
}

private enum OriginalTextMeasurementKind: Hashable {
    case full
    case collapsed
}

private struct OriginalTextMeasurementID: Hashable {
    let text: String
    let kind: OriginalTextMeasurementKind
}

private struct OriginalTextHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [OriginalTextMeasurementID: CGFloat] = [:]

    static func reduce(
        value: inout [OriginalTextMeasurementID: CGFloat],
        nextValue: () -> [OriginalTextMeasurementID: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func measureOriginalTextHeight(
        as kind: OriginalTextMeasurementKind,
        for text: String
    ) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: OriginalTextHeightPreferenceKey.self,
                    value: [.init(text: text, kind: kind): geometry.size.height]
                )
            }
        }
    }
}
