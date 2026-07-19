import Foundation

public struct LookupOutcome: Equatable, Sendable {
    public let id: UUID
    public let request: LookupRequest
    public let result: LookupResult
    public let providerName: String
    public let wasCached: Bool

    @available(*, deprecated, message: "Use id. History is created only by an explicit save action.")
    public var historyEntryID: UUID? { id }
}

public actor LookupEngine {
    private let provider: any TranslationProvider
    private let providerIdentifier: String
    private let cache: LookupCache

    public init(
        provider: any TranslationProvider,
        providerIdentifier: String,
        cache: LookupCache
    ) {
        self.provider = provider
        self.providerIdentifier = providerIdentifier
        self.cache = cache
    }

    /// Transitional initializer for callers that still construct the engine with a history store.
    /// The store is intentionally ignored; lookups never persist history.
    public init(
        provider: any TranslationProvider,
        providerIdentifier: String,
        cache: LookupCache,
        history: LookupHistoryStore
    ) {
        self.provider = provider
        self.providerIdentifier = providerIdentifier
        self.cache = cache
    }

    public func lookup(selection: String) async throws -> LookupOutcome {
        let request = try LookupRequest(selection: selection)
        let key = LookupCacheKey.make(request: request, providerIdentifier: providerIdentifier)

        let cached = await cache.value(for: key)
        try Task.checkCancellation()
        if let cached {
            let cleaned = AppleBooksAttributionCleaner.removingFooter(from: cached)
            if cleaned != cached {
                try await cacheBestEffort(cleaned, for: key)
            }
            return LookupOutcome(
                id: UUID(),
                request: request,
                result: cleaned,
                providerName: provider.displayName,
                wasCached: true
            )
        }

        if let legacyKey = legacyCacheKey(for: selection, canonicalRequest: request),
           let legacyCached = await cache.value(for: legacyKey) {
            try Task.checkCancellation()
            let cleaned = AppleBooksAttributionCleaner.removingFooter(from: legacyCached)
            try await cacheBestEffort(cleaned, for: key)
            return LookupOutcome(
                id: UUID(),
                request: request,
                result: cleaned,
                providerName: provider.displayName,
                wasCached: true
            )
        }

        let providerResult = try await provider.translate(request)
        try Task.checkCancellation()
        let result = AppleBooksAttributionCleaner.removingFooter(from: providerResult)
        try await cacheBestEffort(result, for: key)
        try Task.checkCancellation()
        return LookupOutcome(
            id: UUID(),
            request: request,
            result: result,
            providerName: provider.displayName,
            wasCached: false
        )
    }

    private func cacheBestEffort(_ result: LookupResult, for key: String) async throws {
        do {
            try await cache.insert(result, for: key)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Cache persistence is best effort and must not fail a successful lookup.
        }
    }

    private func legacyCacheKey(
        for selection: String,
        canonicalRequest: LookupRequest
    ) -> String? {
        guard let legacyText = try? LookupInputNormalizer.normalize(selection) else {
            return nil
        }
        guard legacyText != canonicalRequest.text else { return nil }
        let legacyRequest = LookupRequest(
            text: legacyText,
            kind: LookupClassifier.classify(legacyText),
            sourceLanguage: canonicalRequest.sourceLanguage,
            targetLanguage: canonicalRequest.targetLanguage,
            style: canonicalRequest.style
        )
        return LookupCacheKey.make(
            request: legacyRequest,
            providerIdentifier: providerIdentifier
        )
    }

}
