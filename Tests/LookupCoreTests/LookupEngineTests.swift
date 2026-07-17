import Foundation
import XCTest
@testable import LookupCore

@MainActor
final class LookupEngineTests: XCTestCase {
    func testEngineUsesCacheAndNeverWritesHistoryForSuccessfulLookups() async throws {
        let directory = try temporaryDirectory()
        let provider = CountingProvider(result: .passage(.init(
            translation: "这开启了一场交流。", nuanceNote: nil, literalGloss: nil
        )))
        let historyURL = directory.appending(path: "history.json")
        let history = LookupHistoryStore(fileURL: historyURL)
        let engine = LookupEngine(
            provider: provider,
            providerIdentifier: "mock:v1",
            cache: LookupCache(fileURL: directory.appending(path: "cache.json")),
            history: history
        )

        let first = try await engine.lookup(selection: "That started an exchange.")
        let second = try await engine.lookup(selection: "That started an exchange.")

        XCTAssertFalse(first.wasCached)
        XCTAssertTrue(second.wasCached)
        XCTAssertNotEqual(first.id, second.id)
        let providerCount = await provider.callCount
        let historyEntries = await history.entries
        XCTAssertEqual(providerCount, 1)
        XCTAssertTrue(historyEntries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path))
    }

    func testEngineDoesNotRecordFailedLookup() async throws {
        let directory = try temporaryDirectory()
        let provider = CountingProvider(result: nil)
        let engine = LookupEngine(
            provider: provider,
            providerIdentifier: "mock:v1",
            cache: LookupCache(fileURL: directory.appending(path: "cache.json"))
        )

        do {
            _ = try await engine.lookup(selection: "exchange")
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertEqual(error as? TranslationProviderError, .serviceUnavailable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "history.json").path))
    }

    func testCancellationAfterNoncooperativeProviderDoesNotPersistResult() async throws {
        let directory = try temporaryDirectory()
        let provider = ControlledProvider()
        let cache = LookupCache(fileURL: directory.appending(path: "cache.json"))
        let engine = LookupEngine(
            provider: provider,
            providerIdentifier: "controlled:v1",
            cache: cache
        )
        addTeardownBlock { await provider.cancelPending() }

        let task = Task { try await engine.lookup(selection: "obsolete") }
        try await provider.waitUntilStarted()
        task.cancel()
        await provider.resume(with: .passage(.init(
            translation: "过时", nuanceNote: nil, literalGloss: nil
        )))

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let request = try LookupRequest(selection: "obsolete")
        let key = LookupCacheKey.make(request: request, providerIdentifier: "controlled:v1")
        let cachedValue = await cache.value(for: key)
        XCTAssertNil(cachedValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "history.json").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum WaitTimeout: Error {
    case deadlineExceeded
}

private actor ControlledProvider: TranslationProvider {
    let displayName = "Controlled"
    private var continuation: CheckedContinuation<LookupResult, Error>?

    func translate(_ request: LookupRequest) async throws -> LookupResult {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while continuation == nil {
            guard clock.now < deadline else { throw WaitTimeout.deadlineExceeded }
            await Task.yield()
        }
    }

    func resume(with result: LookupResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    func cancelPending() {
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor CountingProvider: TranslationProvider {
    let displayName = "Mock"
    private let result: LookupResult?
    private(set) var callCount = 0

    init(result: LookupResult?) {
        self.result = result
    }

    func translate(_ request: LookupRequest) async throws -> LookupResult {
        callCount += 1
        guard let result else { throw TranslationProviderError.serviceUnavailable }
        return result
    }
}
