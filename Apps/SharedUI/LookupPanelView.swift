import SwiftUI

struct MarginRootView: View {
    @ObservedObject var session: LookupSession
    @ObservedObject private var firstRunState: FirstRunState
    var onDismiss: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil

    init(
        session: LookupSession,
        onDismiss: (() -> Void)? = nil,
        onPreferredHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self.session = session
        firstRunState = session.firstRunState
        self.onDismiss = onDismiss
        self.onPreferredHeightChange = onPreferredHeightChange
    }

    @ViewBuilder
    var body: some View {
        if !firstRunState.isComplete, session.phase == .idle {
            FirstRunSetupView(state: firstRunState) { apiKey in
                try await session.saveAndTestDeepSeek(apiKey: apiKey)
            }
            .onNaturalHeightChange { onPreferredHeightChange?($0) }
        } else {
            LookupPanelView(
                session: session,
                onDismiss: onDismiss,
                onPreferredHeightChange: onPreferredHeightChange
            )
        }
    }
}

struct LookupPanelView: View {
    @ObservedObject var session: LookupSession
    var onDismiss: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        switch session.phase {
        case let .result(outcome):
            switch outcome.result {
            case .word:
                WordDictionaryView(
                    outcome: outcome,
                    isSaved: session.isSaved(id: outcome.id),
                    onToggleSaved: {
                        session.toggleSaved(outcome: outcome)
                    },
                    onRetry: session.retry,
                    onDismiss: onDismiss,
                    onPreferredHeightChange: onPreferredHeightChange
                )
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .passage:
                PassageResultView(
                    originalText: session.selection,
                    outcome: outcome,
                    isSaved: session.isSaved(id: outcome.id),
                    onToggleSaved: {
                        session.toggleSaved(outcome: outcome)
                    },
                    onRetry: session.retry,
                    onDismiss: onDismiss,
                    onPreferredHeightChange: onPreferredHeightChange
                )
            }
        case .idle, .loading, .failure:
            ScrollView {
                standardPanel
                    .onNaturalHeightChange { onPreferredHeightChange?($0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MarginTheme.canvas)
        }
    }

    private var standardPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
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

            if !session.selection.isEmpty {
                Text(session.selection)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.quaternary).frame(width: 2)
                    }
            }

            switch session.phase {
            case .idle:
                VStack(alignment: .leading, spacing: 10) {
                    #if os(macOS)
                    Label("In Apple Books, select text and press ⌃⌥M", systemImage: "command")
                        .font(.callout.weight(.medium))
                    #endif
                    TextField("Paste or type a word or passage", text: $session.selection, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                    Button("Look up", systemImage: "text.magnifyingglass") {
                        session.lookup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loadingTitle).font(.headline)
                        Text("The selection stays available if the request fails.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel", action: session.cancel)
                }
                .padding(.vertical, 18)
            case .result:
                EmptyView()
            case let .failure(message):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Lookup unavailable", systemImage: "exclamationmark.circle")
                        .font(.headline)
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    if let detail = session.failureTechnicalDetail {
                        DisclosureGroup("Technical details") {
                            Text(detail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .padding(.top, 6)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Retry", action: session.retry).buttonStyle(.borderedProminent)
                        Button("Edit selection", action: session.reset)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .padding(20)
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 560)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var loadingTitle: LocalizedStringKey {
        switch session.loadingProgress {
        case .readingContext:
            "Reading the context…"
        case .refiningNaturalTranslation:
            "Refining the natural translation…"
        }
    }
}
