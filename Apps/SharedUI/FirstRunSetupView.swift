import SwiftUI

struct FirstRunSetupView: View {
    typealias SaveAndTestAction = @MainActor (_ apiKey: String) async throws -> Void

    @ObservedObject var state: FirstRunState
    let saveAndTest: SaveAndTestAction

    @State private var apiKey = ""
    @State private var statusMessage: String?
    @State private var isTesting = false
    @State private var showsAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                providerSetup
                shortcutSetup
                advancedCompatibility

                HStack {
                    Button("Set up later") {
                        state.complete()
                    }
                    Spacer()
                    Button("Save and test") {
                        testDeepSeekConnection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                }
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 420, minHeight: 440)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Margin")
                .font(.largeTitle.weight(.semibold))
            Text("Contextual Reading for Apple Books")
                .font(.title3)
            Text("Read English. Stay in the book.")
                .foregroundStyle(.secondary)
        }
    }

    private var providerSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect DeepSeek", systemImage: "sparkles")
                .font(.headline)
            Text("Margin uses deepseek-v4-flash for its certified translation experience. Your API key stays in this device's Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("DeepSeek API key", text: $apiKey)
                .textContentType(.password)

            if isTesting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Testing the DeepSeek connection…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var shortcutSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            #if os(macOS)
            Label("Use Margin in Apple Books", systemImage: "command")
                .font(.headline)
            Text("Select a word or passage, then press ⌃⌥M. Margin asks for Accessibility access only after you press the shortcut for the first time.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #else
            Label("Use Margin in Apple Books", systemImage: "square.and.arrow.up")
                .font(.headline)
            Text("Select a word or passage, open the Share Sheet, then choose Look Up with Margin.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    private var advancedCompatibility: some View {
        DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
            Text("Custom OpenAI-compatible endpoints remain available as a future compatibility option in Settings. Margin does not certify their translation quality.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private func testDeepSeekConnection() {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else { return }

        statusMessage = nil
        isTesting = true
        Task { @MainActor in
            defer { isTesting = false }
            do {
                try await saveAndTest(trimmedAPIKey)
                apiKey = ""
                state.complete()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
