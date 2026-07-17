import Foundation
import ApplePlatformSupport
import Combine
import LookupCore
import SwiftUI
import XCTest
@testable import Margin

@MainActor
final class LookupSessionTests: XCTestCase {
    func testAppearancePreferredColorSchemeMapping() {
        XCTAssertNil(MarginAppearance.system.preferredColorScheme)
        XCTAssertEqual(MarginAppearance.light.preferredColorScheme, .light)
        XCTAssertEqual(MarginAppearance.dark.preferredColorScheme, .dark)
    }

    func testAppearanceDefaultsToSystemWhenInjectedDefaultsAreEmpty() {
        let defaults = makeTemporaryDefaults()
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: TestSecretStore()),
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )

        XCTAssertEqual(session.appearance, .system)
    }

    func testAppearanceLoadsDarkFromInjectedDefaults() {
        let defaults = makeTemporaryDefaults()
        defaults.set("dark", forKey: MarginAppearance.defaultsKey)
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: TestSecretStore()),
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )

        XCTAssertEqual(session.appearance, .dark)
    }

    func testInvalidAppearanceFallsBackToSystem() {
        let defaults = makeTemporaryDefaults()
        defaults.set("sepia", forKey: MarginAppearance.defaultsKey)
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: TestSecretStore()),
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )

        XCTAssertEqual(session.appearance, .system)
    }

    func testSetAppearancePublishesAndPersistsLightToInjectedDefaults() {
        let defaults = makeTemporaryDefaults()
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: TestSecretStore()),
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )
        var publishedAppearances: [MarginAppearance] = []
        let cancellable = session.$appearance.dropFirst().sink {
            publishedAppearances.append($0)
        }

        session.setAppearance(.light)

        XCTAssertEqual(session.appearance, .light)
        XCTAssertEqual(publishedAppearances, [.light])
        XCTAssertEqual(defaults.string(forKey: MarginAppearance.defaultsKey), "light")
        withExtendedLifetime(cancellable) {}
    }

    func testInjectedDefaultsAreUsedForPreferenceLoadAndSave() throws {
        let suiteName = "LookupSessionTests.\(UUID().uuidString)"
        let untouchedSuiteName = "LookupSessionTests.untouched.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let untouchedDefaults = try XCTUnwrap(UserDefaults(suiteName: untouchedSuiteName))
        defaults.set("https://example.com/old", forKey: ProviderPreferences.endpointDefaultsKey)
        defaults.set("old-model", forKey: ProviderPreferences.modelDefaultsKey)
        untouchedDefaults.set("untouched-model", forKey: ProviderPreferences.modelDefaultsKey)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            untouchedDefaults.removePersistentDomain(forName: untouchedSuiteName)
        }
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: TestSecretStore()),
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )

        XCTAssertEqual(session.preferences.endpoint, "https://example.com/old")
        XCTAssertEqual(session.preferences.model, "old-model")

        try session.saveSettings(
            endpoint: "https://example.com/new",
            model: "new-model",
            apiKey: ""
        )

        XCTAssertEqual(defaults.string(forKey: ProviderPreferences.endpointDefaultsKey), "https://example.com/new")
        XCTAssertEqual(defaults.string(forKey: ProviderPreferences.modelDefaultsKey), "new-model")
        XCTAssertEqual(untouchedDefaults.string(forKey: ProviderPreferences.modelDefaultsKey), "untouched-model")
    }

    func testOlderSuccessCannotOverwriteNewerResult() async throws {
        let operation = ControlledLookupOperation()
        let session = testSession(lookupOperation: { selection in
            try await operation.perform(selection)
        })
        addTeardownBlock { await operation.cancelAll() }
        let oldOutcome = try await makeOutcome(selection: "old")
        let newOutcome = try await makeOutcome(selection: "new")

        session.lookup(selection: "old")
        try await operation.waitUntilStarted("old")
        session.lookup(selection: "new")
        try await operation.waitUntilStarted("new")
        await operation.resume("new", with: .success(newOutcome))
        try await waitUntil { session.phase == .result(newOutcome) }
        await operation.resume("old", with: .success(oldOutcome))
        await Task.yield()

        XCTAssertEqual(session.phase, .result(newOutcome))
    }

    func testOlderFailureCannotOverwriteNewerLoading() async throws {
        let operation = ControlledLookupOperation()
        let session = testSession(lookupOperation: { selection in
            try await operation.perform(selection)
        })
        addTeardownBlock { await operation.cancelAll() }

        session.lookup(selection: "old")
        try await operation.waitUntilStarted("old")
        session.lookup(selection: "new")
        try await operation.waitUntilStarted("new")
        await operation.resume("old", with: .failure(TestFailure.oldRequest))
        await Task.yield()

        XCTAssertEqual(session.phase, .loading)
        await operation.resume("new", with: .failure(CancellationError()))
    }

    func testOlderCancellationCannotOverwriteNewerFailure() async throws {
        let operation = ControlledLookupOperation()
        let session = testSession(lookupOperation: { selection in
            try await operation.perform(selection)
        })
        addTeardownBlock { await operation.cancelAll() }

        session.lookup(selection: "old")
        try await operation.waitUntilStarted("old")
        session.lookup(selection: "new")
        try await operation.waitUntilStarted("new")
        await operation.resume("new", with: .failure(TestFailure.newRequest))
        try await waitUntil {
            if case .failure = session.phase { return true }
            return false
        }
        let newerFailure = session.phase
        await operation.resume("old", with: .failure(CancellationError()))
        await Task.yield()

        XCTAssertEqual(session.phase, newerFailure)
    }

    func testLookupIsUnsavedUntilExplicitSaveAndUnsavePhysicallyRemovesIt() async throws {
        let outcome = try await makeOutcome(selection: "deliberate")
        let session = testSession(lookupOperation: { _ in outcome })

        session.lookup(selection: "deliberate")
        try await waitUntil { session.phase == .result(outcome) }
        XCTAssertTrue(session.historyEntries.isEmpty)
        XCTAssertFalse(session.isSaved(id: outcome.id))

        session.toggleSaved(outcome: outcome)
        try await waitUntil { session.historyEntries.map(\.id) == [outcome.id] }
        XCTAssertTrue(session.isSaved(id: outcome.id))

        session.toggleSaved(outcome: outcome)
        try await waitUntil { session.historyEntries.isEmpty }
        XCTAssertFalse(session.isSaved(id: outcome.id))
    }

    func testConnectionThenLookupReadsSecretStoreOnceAndUsesSessionProviderTwice() async throws {
        let defaults = makeTemporaryDefaults()
        defaults.set("https://example.com/v1", forKey: ProviderPreferences.endpointDefaultsKey)
        defaults.set("test-model", forKey: ProviderPreferences.modelDefaultsKey)
        let secretStore = CountingSecretStore(value: "saved-key")
        let provider = CountingProvider()
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: secretStore),
            providerFactory: { configuration in
                XCTAssertEqual(configuration.apiKey, "saved-key")
                return provider
            },
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )

        _ = try await session.testConnection()
        session.lookup(selection: "another")
        try await waitUntil {
            if case .result = session.phase { return true }
            return false
        }

        XCTAssertEqual(secretStore.readCount, 1)
        let callCount = await provider.callCount
        let selections = await provider.selections
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(selections, ["book", "another"])
    }

    func testFallbackProgressChangesLoadingCopy() {
        let session = testSession { _ in throw TestFailure.newRequest }

        session.receiveProviderEvent(.progress(.refiningNaturalTranslation))

        XCTAssertEqual(session.loadingProgress, .refiningNaturalTranslation)
    }

    func testResponseFailureRetryUsesNaturalOnlyProviderPolicy() async throws {
        let defaults = makeTemporaryDefaults()
        defaults.set(ProviderPreferences.defaultEndpoint, forKey: ProviderPreferences.endpointDefaultsKey)
        defaults.set(ProviderPreferences.defaultModel, forKey: ProviderPreferences.modelDefaultsKey)
        let secretStore = TestSecretStore()
        try secretStore.save("saved-key")
        let recorder = ProviderConfigurationRecorder()
        let session = LookupSession(
            defaults: defaults,
            vault: APIKeyVault(store: secretStore),
            providerFactory: { configuration in
                Task { await recorder.record(configuration.lookupPolicy) }
                return AlwaysResponseFailureProvider()
            },
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )

        session.lookup(selection: "First sentence. Second sentence.")
        try await waitUntil {
            if case .failure = session.phase { return true }
            return false
        }
        XCTAssertNotNil(session.failureTechnicalDetail)

        session.retry()
        try await waitUntil {
            if case .failure = session.phase { return true }
            return false
        }
        try await waitUntilAsync { await recorder.policies.count == 2 }

        let policies = await recorder.policies
        XCTAssertEqual(policies, [.standard, .naturalOnly])
    }

    private func testSession(
        lookupOperation: @escaping (String) async throws -> LookupOutcome,
        historySnapshotOperation: (() async throws -> LookupSession.HistorySnapshot)? = nil
    ) -> LookupSession {
        makeIsolatedSession(
            lookupOperation: lookupOperation,
            historySnapshotOperation: historySnapshotOperation
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else { throw TestTimeout.deadlineExceeded }
            await Task.yield()
        }
    }

    private func waitUntilAsync(_ condition: @escaping () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            guard clock.now < deadline else { throw TestTimeout.deadlineExceeded }
            await Task.yield()
        }
    }

    private func makeOutcome(selection: String) async throws -> LookupOutcome {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let engine = LookupEngine(
            provider: FixtureProvider(),
            providerIdentifier: "fixture",
            cache: LookupCache(fileURL: directory.appending(path: "cache.json")),
            history: LookupHistoryStore(fileURL: directory.appending(path: "history.json"))
        )
        return try await engine.lookup(selection: selection)
    }

}

private struct AlwaysResponseFailureProvider: TranslationProvider {
    let displayName = "Fixture"

    func translate(_ request: LookupRequest) async throws -> LookupResult {
        throw TranslationResponseError(
            issue: .invalidStructure,
            stage: "naturalFallback",
            detail: "expected=2 · received=1"
        )
    }
}

private actor ProviderConfigurationRecorder {
    private(set) var policies: [ProviderLookupPolicy] = []

    func record(_ policy: ProviderLookupPolicy) {
        policies.append(policy)
    }
}

private enum TestFailure: Error {
    case oldRequest
    case newRequest
}

private enum TestTimeout: Error {
    case deadlineExceeded
}

private actor ControlledLookupOperation {
    private var continuations: [String: CheckedContinuation<LookupOutcome, Error>] = [:]

    func perform(_ selection: String) async throws -> LookupOutcome {
        try await withCheckedThrowingContinuation { continuation in
            continuations[selection] = continuation
        }
    }

    func waitUntilStarted(_ selection: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while continuations[selection] == nil {
            guard clock.now < deadline else { throw TestTimeout.deadlineExceeded }
            await Task.yield()
        }
    }

    func resume(_ selection: String, with result: Result<LookupOutcome, Error>) {
        continuations.removeValue(forKey: selection)?.resume(with: result)
    }

    func cancelAll() {
        let pending = continuations.values
        continuations.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

private struct FixtureProvider: TranslationProvider {
    let displayName = "Fixture"

    func translate(_ request: LookupRequest) async throws -> LookupResult {
        .word(WordLookupResult(
            headword: request.text,
            pronunciations: [],
            partsOfSpeech: [],
            alternatives: []
        ))
    }
}

private final class CountingSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var _readCount = 0

    init(value: String?) { self.value = value }

    var readCount: Int { lock.withLock { _readCount } }
    func save(_ secret: String) throws { lock.withLock { value = secret } }
    func read() throws -> String? { lock.withLock { _readCount += 1; return value } }
    func delete() throws { lock.withLock { value = nil } }
}

private actor CountingProvider: TranslationProvider {
    nonisolated let displayName = "Counting"
    private(set) var callCount = 0
    private(set) var selections: [String] = []

    func translate(_ request: LookupRequest) async throws -> LookupResult {
        callCount += 1
        selections.append(request.text)
        return .word(.init(headword: request.text, pronunciations: [], partsOfSpeech: [], alternatives: []))
    }
}
