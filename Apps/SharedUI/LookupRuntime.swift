import ApplePlatformSupport
import Foundation
import LookupCore

enum LookupRuntime {
    static func lookup(selection: String) async throws -> LookupOutcome {
        let preferences = ProviderPreferences()
        guard let endpoint = URL(string: preferences.endpoint), endpoint.scheme == "https",
              !preferences.model.isEmpty else {
            throw TranslationProviderError.misconfigured
        }
        let vault = APIKeyVault(store: KeychainAPIKeyStore(service: SharedConfiguration.keychainService))
        guard let apiKey = try await Task.detached(operation: { try vault.read() }).value,
              !apiKey.isEmpty else {
            throw TranslationProviderError.misconfigured
        }
        let directory = SharedConfiguration.storageDirectory
        let provider = OpenAICompatibleProvider(configuration: .init(
            endpoint: endpoint,
            model: preferences.model,
            apiKey: apiKey
        ))
        let engine = LookupEngine(
            provider: provider,
            providerIdentifier: TranslationContract.providerIdentifier(
                endpoint: endpoint,
                model: preferences.model
            ),
            cache: LookupCache(fileURL: directory.appending(path: "cache.json"))
        )
        return try await engine.lookup(selection: selection)
    }
}
