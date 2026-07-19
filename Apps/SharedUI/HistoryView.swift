import LookupCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var session: LookupSession
    @State private var showsClearConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if session.historyEntries.isEmpty {
                    ContentUnavailableView(
                        "No saved items",
                        systemImage: "bookmark",
                        description: Text("Only lookups you explicitly save appear here.")
                    )
                } else {
                    List(session.historyEntries) { entry in
                        HistoryRow(entry: entry) {
                            session.removeSaved(id: entry.id)
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItemGroup {
                    Button("Clear", role: .destructive) { showsClearConfirmation = true }
                        .disabled(session.historyEntries.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .task { await session.refreshHistory() }
        .confirmationDialog(
            "Clear all saved items?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear saved items", role: .destructive) { session.clearSavedItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct HistoryRow: View {
    let entry: LookupHistoryEntry
    let onToggleSaved: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.selection).font(.headline).lineLimit(2)
                Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onToggleSaved) {
                Image(systemName: "bookmark.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove from saved")
        }
        .padding(.vertical, 5)
    }

    private var summary: String {
        switch entry.result {
        case let .word(word):
            ChineseTypographyNormalizer.normalize(
                word.partsOfSpeech
                    .flatMap(\.senses)
                    .map(\.chineseDefinition)
                    .prefix(3)
                    .joined(separator: " · ")
            )
        case let .passage(passage):
            ChineseTypographyNormalizer.normalize(passage.translation)
        }
    }
}
