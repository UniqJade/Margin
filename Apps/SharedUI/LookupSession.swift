import ApplePlatformSupport
import Combine
import Foundation
import LookupCore

@MainActor
final class LookupSession: ObservableObject {
    typealias ProviderFactory = (OpenAICompatibleProvider.Configuration) -> any TranslationProvider

    enum Phase: Equatable {
        case idle
        case loading
        case result(LookupOutcome)
        case failure(String)
    }

    struct HistorySnapshot: Sendable {
        let entries: [LookupHistoryEntry]
        let enabled: Bool
    }

    @Published var selection = ""
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var historyEntries: [LookupHistoryEntry] = []
    @Published private(set) var cacheUsageBytes = 0
    @Published private(set) var appearance: MarginAppearance
    @Published private(set) var loadingProgress = TranslationProgress.readingContext
    @Published private(set) var failureTechnicalDetail: String?
    @Published private(set) var diagnosticCount = 0

    private(set) var preferences: ProviderPreferences
    let firstRunState: FirstRunState
    private let defaults: UserDefaults
    private let vault: APIKeyVault
    private let cache: LookupCache
    private let history: LookupHistoryStore
    private let diagnosticStore: TranslationDiagnosticStore
    private let providerFactory: ProviderFactory
    private let lookupOperation: ((String) async throws -> LookupOutcome)?
    private let historySnapshotOperation: (() async throws -> HistorySnapshot)?
    private var lookupTask: Task<Void, Never>?
    private var lookupGeneration: UInt = 0
    private var retryLookupPolicy = ProviderLookupPolicy.standard

    init(
        defaults: UserDefaults = SharedConfiguration.defaults,
        vault: APIKeyVault = APIKeyVault(store: KeychainAPIKeyStore(service: SharedConfiguration.keychainService)),
        providerFactory: @escaping ProviderFactory = { OpenAICompatibleProvider(configuration: $0) },
        lookupOperation: ((String) async throws -> LookupOutcome)? = nil,
        historySnapshotOperation: (() async throws -> HistorySnapshot)? = nil,
        loadInitialHistory: Bool = true,
        storageDirectory: URL = SharedConfiguration.storageDirectory
    ) {
        self.defaults = defaults
        self.vault = vault
        self.providerFactory = providerFactory
        preferences = ProviderPreferences(defaults: defaults)
        firstRunState = FirstRunState(defaults: defaults)
        appearance = defaults.string(forKey: MarginAppearance.defaultsKey)
            .flatMap(MarginAppearance.init(rawValue:)) ?? .system
        cache = LookupCache(fileURL: storageDirectory.appending(path: "cache.json"))
        history = LookupHistoryStore(fileURL: storageDirectory.appending(path: "history.json"))
        diagnosticStore = TranslationDiagnosticStore(
            fileURL: storageDirectory.appending(path: "diagnostics.json")
        )
        self.lookupOperation = lookupOperation
        self.historySnapshotOperation = historySnapshotOperation
        if loadInitialHistory {
            Task {
                await refreshHistory()
                await refreshCacheUsage()
                await refreshDiagnostics()
            }
        }
    }

    deinit {
        lookupTask?.cancel()
    }

    func lookup(selection newSelection: String? = nil) {
        if let newSelection { selection = newSelection }
        retryLookupPolicy = .standard
        beginLookup(policy: .standard)
    }

    private func beginLookup(policy: ProviderLookupPolicy) {
        let generation = invalidateLookup()
        loadingProgress = .readingContext
        failureTechnicalDetail = nil
        phase = .loading
        let currentSelection = selection
        lookupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome: LookupOutcome
                if let lookupOperation = self.lookupOperation {
                    outcome = try await lookupOperation(currentSelection)
                } else {
                    outcome = try await self.performLookup(selection: currentSelection, policy: policy)
                }
                guard self.isCurrent(generation) else { return }
                self.retryLookupPolicy = .standard
                self.phase = .result(outcome)
            } catch is CancellationError {
                guard self.isCurrent(generation) else { return }
                self.phase = .idle
            } catch {
                guard self.isCurrent(generation) else { return }
                if let responseError = error as? TranslationResponseError {
                    self.failureTechnicalDetail = responseError.technicalDescription
                    self.retryLookupPolicy = .naturalOnly
                } else {
                    self.failureTechnicalDetail = nil
                    self.retryLookupPolicy = .standard
                }
                self.phase = .failure(error.localizedDescription)
            }
        }
    }

    func retry() {
        beginLookup(policy: retryLookupPolicy)
    }

    func cancel() {
        _ = invalidateLookup()
        phase = .idle
    }

    func reset() {
        _ = invalidateLookup()
        selection = ""
        phase = .idle
    }

    func presentFailure(_ message: String) {
        _ = invalidateLookup()
        phase = .failure(message)
    }

    func saveSettings(endpoint: String, model: String, apiKey: String) throws {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmedEndpoint)?.scheme == "https", !trimmedModel.isEmpty else {
            throw TranslationProviderError.misconfigured
        }
        preferences = ProviderPreferences(endpoint: trimmedEndpoint, model: trimmedModel)
        preferences.save(defaults: defaults)
        if !apiKey.isEmpty {
            try vault.save(apiKey)
        }
    }

    func setAppearance(_ appearance: MarginAppearance) {
        self.appearance = appearance
        defaults.set(appearance.rawValue, forKey: MarginAppearance.defaultsKey)
    }

    func deleteAPIKey() throws {
        try vault.delete()
    }

    func testConnection() async throws -> LookupOutcome {
        try await performLookup(selection: "book")
    }

    func saveAndTestDeepSeek(apiKey: String) async throws {
        try saveSettings(
            endpoint: ProviderPreferences.defaultEndpoint,
            model: ProviderPreferences.defaultModel,
            apiKey: apiKey
        )
        _ = try await testConnection()
    }

    func refreshHistory() async {
        guard let snapshot = try? await loadHistorySnapshot() else { return }
        publish(snapshot)
    }

    func toggleSaved(outcome: LookupOutcome) {
        Task {
            if isSaved(id: outcome.id) {
                try? await history.remove(id: outcome.id)
            } else {
                _ = try? await history.save(
                    request: outcome.request,
                    result: outcome.result,
                    providerName: outcome.providerName,
                    id: outcome.id
                )
            }
            await refreshHistory()
        }
    }

    func removeSaved(id: UUID) {
        Task {
            try? await history.remove(id: id)
            await refreshHistory()
        }
    }

    func clearSavedItems() {
        Task {
            try? await history.clear()
            await refreshHistory()
        }
    }

    func isSaved(id: UUID?) -> Bool {
        guard let id else { return false }
        return historyEntries.contains(where: { $0.id == id })
    }

    func refreshCacheUsage() async {
        cacheUsageBytes = (try? await cache.usageBytes()) ?? 0
    }

    func refreshDiagnostics() async {
        diagnosticCount = (try? await diagnosticStore.recent().count) ?? 0
    }

    func clearDiagnostics() {
        Task {
            try? await diagnosticStore.clear()
            await refreshDiagnostics()
        }
    }

    func receiveProviderEvent(_ event: TranslationProviderEvent) {
        switch event {
        case let .progress(progress):
            loadingProgress = progress
        case let .diagnostic(diagnostic):
            let store = diagnosticStore
            Task {
                try? await store.append(diagnostic)
                await refreshDiagnostics()
            }
        }
    }

    func clearCache() {
        Task {
            try? await cache.clear()
            await refreshCacheUsage()
        }
    }

    private func performLookup(
        selection: String,
        policy: ProviderLookupPolicy = .standard
    ) async throws -> LookupOutcome {
        guard let endpoint = URL(string: preferences.endpoint), endpoint.scheme == "https",
              !preferences.model.isEmpty,
              let apiKey = try await Task.detached(operation: { [vault] in try vault.read() }).value,
              !apiKey.isEmpty else {
            throw TranslationProviderError.misconfigured
        }
        let configuration = OpenAICompatibleProvider.Configuration(
            endpoint: endpoint,
            model: preferences.model,
            apiKey: apiKey,
            lookupPolicy: policy,
            eventHandler: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.receiveProviderEvent(event)
                }
            }
        )
        let provider = providerFactory(configuration)
        let engine = LookupEngine(
            provider: provider,
            providerIdentifier: TranslationContract.providerIdentifier(
                endpoint: endpoint,
                model: preferences.model
            ),
            cache: cache
        )
        return try await engine.lookup(selection: selection)
    }

    private func loadHistorySnapshot() async throws -> HistorySnapshot {
        if let historySnapshotOperation {
            return try await historySnapshotOperation()
        }
        let entries = await history.entries
        return HistorySnapshot(entries: entries, enabled: true)
    }

    private func publish(_ snapshot: HistorySnapshot) {
        historyEntries = snapshot.entries
    }

    @discardableResult
    private func invalidateLookup() -> UInt {
        lookupTask?.cancel()
        lookupGeneration &+= 1
        return lookupGeneration
    }

    private func isCurrent(_ generation: UInt) -> Bool {
        generation == lookupGeneration
    }
}

private extension ProviderPreferences {
    init(endpoint: String, model: String) {
        self.endpoint = endpoint
        self.model = model
    }
}
