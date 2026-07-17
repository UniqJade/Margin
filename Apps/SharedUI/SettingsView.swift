import SwiftUI

struct ProviderSettingsDraft: Equatable {
    var endpoint: String
    var model: String

    init(endpoint: String = "", model: String = "") {
        self.endpoint = endpoint
        self.model = model
    }

    var isUsingDeepSeek: Bool {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines) == ProviderPreferences.defaultEndpoint
            && model.trimmingCharacters(in: .whitespacesAndNewlines) == ProviderPreferences.defaultModel
    }

    mutating func resetToDeepSeek() {
        endpoint = ProviderPreferences.defaultEndpoint
        model = ProviderPreferences.defaultModel
    }
}

struct SettingsView: View {
    @ObservedObject var session: LookupSession
    @State private var provider = ProviderSettingsDraft()
    @State private var apiKey = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var showsAdvanced = false
    @State private var showsClearCacheConfirmation = false
    @State private var showsClearSavedConfirmation = false
    @State private var showsClearDiagnosticsConfirmation = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { session.appearance },
                        set: { session.setAppearance($0) }
                    )
                ) {
                    ForEach(MarginAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("Follow System changes automatically with this device. Light and Dark affect Margin only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("DeepSeek") {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Certified translation provider", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Text("Margin uses deepseek-v4-flash with structured JSON output for its certified translation experience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("API key (leave blank to keep the saved key)", text: $apiKey)
                    .textContentType(.password)

                HStack {
                    Button("Save settings") { save() }
                    Button("Save and test") { saveAndTest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting)
                    Spacer()
                    Button("Delete API key", role: .destructive) { deleteKey() }
                }

                if isTesting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Testing the provider connection…")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(statusIsError ? .red : .green)
                    .textSelection(.enabled)
                }
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom OpenAI-compatible endpoints are retained for future compatibility. Margin does not test or certify their translation quality.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Base URL or /chat/completions URL", text: $provider.endpoint)
                            .textContentType(.URL)
                        TextField("Model ID", text: $provider.model)
                            .textContentType(.none)

                        HStack {
                            Button("Reset to DeepSeek") { resetToDeepSeek() }
                            if !provider.isUsingDeepSeek {
                                Label("Custom provider active", systemImage: "wrench.and.screwdriver")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Section("Privacy") {
                Text("Only selected text and the language/style settings are sent. The API key is stored device-only in Keychain and is never written to preferences or history.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("BYOK is intended for a locally built personal prototype. A public release must use an authenticated backend relay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local storage") {
                LabeledContent("Translation cache") {
                    Text("\(formattedCacheUsage) / \(formattedCacheLimit)")
                        .foregroundStyle(.secondary)
                }
                Button("Clear translation cache", role: .destructive) {
                    showsClearCacheConfirmation = true
                }
                .disabled(session.cacheUsageBytes == 0)

                LabeledContent("Saved items") {
                    Text(session.historyEntries.count, format: .number)
                        .foregroundStyle(.secondary)
                }
                Button("Clear saved items", role: .destructive) {
                    showsClearSavedConfirmation = true
                }
                .disabled(session.historyEntries.isEmpty)

                LabeledContent("Diagnostic events") {
                    Text(session.diagnosticCount, format: .number)
                        .foregroundStyle(.secondary)
                }
                Text("Diagnostics contain request status and format checks only, never selected text, translations, API keys, or raw responses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear diagnostic events", role: .destructive) {
                    showsClearDiagnosticsConfirmation = true
                }
                .disabled(session.diagnosticCount == 0)
            }

            Section("Setup") {
                Button("Show setup guide again") {
                    session.firstRunState.reopen()
                }
            }

        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
            provider = ProviderSettingsDraft(
                endpoint: session.preferences.endpoint,
                model: session.preferences.model
            )
        }
        .task {
            await session.refreshCacheUsage()
            await session.refreshHistory()
            await session.refreshDiagnostics()
        }
        .confirmationDialog(
            "Clear translation cache?",
            isPresented: $showsClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear cache", role: .destructive) { session.clearCache() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved items and your API key will not be affected.")
        }
        .confirmationDialog(
            "Clear all saved items?",
            isPresented: $showsClearSavedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear saved items", role: .destructive) { session.clearSavedItems() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The translation cache and API key will not be affected.")
        }
        .confirmationDialog(
            "Clear diagnostic events?",
            isPresented: $showsClearDiagnosticsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear diagnostics", role: .destructive) { session.clearDiagnostics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Translations, saved items, cache entries, and your API key will not be affected.")
        }
    }

    private var formattedCacheUsage: String {
        formattedByteCount(session.cacheUsageBytes)
    }

    private var formattedCacheLimit: String {
        formattedByteCount(10_000_000)
    }

    private func formattedByteCount(_ byteCount: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(byteCount))
    }

    private func resetToDeepSeek() {
        provider.resetToDeepSeek()
        showStatus(String(localized: "DeepSeek defaults restored. Click Save settings or Save and test."))
    }

    private func save() {
        do {
            try session.saveSettings(endpoint: provider.endpoint, model: provider.model, apiKey: apiKey)
            apiKey = ""
            showStatus(String(localized: "Settings saved."))
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func deleteKey() {
        do {
            try session.deleteAPIKey()
            showStatus(String(localized: "API key deleted."))
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func saveAndTest() {
        do {
            try session.saveSettings(endpoint: provider.endpoint, model: provider.model, apiKey: apiKey)
            apiKey = ""
            statusMessage = nil
            isTesting = true
            Task { @MainActor in
                defer { isTesting = false }
                do {
                    _ = try await session.testConnection()
                    showStatus(String(localized: "Connection works. You can start reading."))
                } catch {
                    showStatus(error.localizedDescription, isError: true)
                }
            }
        } catch {
            showStatus(error.localizedDescription, isError: true)
        }
    }

    private func showStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
    }
}
