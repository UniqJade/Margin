import Foundation
import XCTest
@testable import LookupCore

@MainActor
final class StorageTests: XCTestCase {
    func testCacheKeyIsStableAndProviderSpecific() throws {
        let request = try LookupRequest(selection: " exchange ")

        let first = LookupCacheKey.make(request: request, providerIdentifier: "openai:test-model")
        let second = LookupCacheKey.make(request: request, providerIdentifier: "openai:test-model")
        let otherProvider = LookupCacheKey.make(request: request, providerIdentifier: "openai:other-model")

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, otherProvider)
        XCTAssertFalse(first.contains("exchange"))
    }

    func testTranslationContractVersionsTheProviderCacheNamespace() throws {
        let endpoint = try XCTUnwrap(URL(string: "https://api.deepseek.com"))
        let versioned = TranslationContract.providerIdentifier(
            endpoint: endpoint,
            model: "deepseek-v4-flash"
        )
        let legacy = "\(endpoint.absoluteString)|deepseek-v4-flash"
        let request = try LookupRequest(selection: "A locked evaluation passage.")

        XCTAssertEqual(TranslationContract.version, "margin-v0.1.0-adaptive-passage-v2")
        XCTAssertTrue(versioned.contains("contract:\(TranslationContract.version)"))
        XCTAssertNotEqual(versioned, legacy)
        XCTAssertNotEqual(
            LookupCacheKey.make(request: request, providerIdentifier: versioned),
            LookupCacheKey.make(request: request, providerIdentifier: legacy)
        )
    }

    func testCachePersistsResultAndCanBeCleared() async throws {
        let directory = try temporaryDirectory()
        let cache = LookupCache(fileURL: directory.appending(path: "cache.json"))
        let request = try LookupRequest(selection: "exchange")
        let key = LookupCacheKey.make(request: request, providerIdentifier: "test")
        let result = LookupResult.word(.init(
            headword: "exchange",
            pronunciations: [],
            partsOfSpeech: [
                .init(name: "noun", senses: [
                    .init(contextLabel: nil, englishDefinition: nil, chineseDefinition: "交流", examples: [])
                ])
            ],
            alternatives: []
        ))

        try await cache.insert(result, for: key)
        let cached = await cache.value(for: key)
        XCTAssertEqual(cached, result)

        let reloaded = LookupCache(fileURL: directory.appending(path: "cache.json"))
        let reloadedValue = await reloaded.value(for: key)
        XCTAssertEqual(reloadedValue, result)
        try await reloaded.clear()
        let clearedUsage = try await reloaded.usageBytes()
        let clearedValue = await reloaded.value(for: key)
        XCTAssertEqual(clearedUsage, 0)
        XCTAssertNil(clearedValue)
    }

    func testCacheUsesTenMillionByteDefaultLimit() {
        XCTAssertEqual(LookupCache.defaultMaximumSizeBytes, 10_000_000)
    }

    func testCacheEvictsLeastRecentlyUsedEntryAndStaysWithinEncodedByteLimit() async throws {
        let probeURL = try temporaryDirectory().appending(path: "probe.json")
        let probe = LookupCache(fileURL: probeURL, maximumSizeBytes: .max)
        try await probe.insert(result(named: "aaaa"), for: "a")
        try await probe.insert(result(named: "bbbb"), for: "b")
        let twoEntrySize = try await probe.usageBytes()
        try await probe.insert(result(named: "cccc"), for: "c")
        let threeEntrySize = try await probe.usageBytes()
        XCTAssertGreaterThan(threeEntrySize, twoEntrySize)

        let limit = (twoEntrySize + threeEntrySize) / 2
        let fileURL = try temporaryDirectory().appending(path: "cache.json")
        let cache = LookupCache(fileURL: fileURL, maximumSizeBytes: limit)
        try await cache.insert(result(named: "aaaa"), for: "a")
        try await cache.insert(result(named: "bbbb"), for: "b")
        let touchedA = await cache.value(for: "a")
        XCTAssertEqual(touchedA, result(named: "aaaa"))

        try await cache.insert(result(named: "cccc"), for: "c")

        let retainedA = await cache.value(for: "a")
        let evictedB = await cache.value(for: "b")
        let retainedC = await cache.value(for: "c")
        let usage = try await cache.usageBytes()
        XCTAssertEqual(retainedA, result(named: "aaaa"))
        XCTAssertNil(evictedB)
        XCTAssertEqual(retainedC, result(named: "cccc"))
        XCTAssertLessThanOrEqual(usage, limit)

        let reloaded = LookupCache(fileURL: fileURL, maximumSizeBytes: limit)
        let reloadedA = await reloaded.value(for: "a")
        let reloadedB = await reloaded.value(for: "b")
        let reloadedC = await reloaded.value(for: "c")
        XCTAssertEqual(reloadedA, result(named: "aaaa"))
        XCTAssertNil(reloadedB)
        XCTAssertEqual(reloadedC, result(named: "cccc"))
    }

    func testCacheDoesNotRetainSingleEntryLargerThanConfiguredLimit() async throws {
        let fileURL = try temporaryDirectory().appending(path: "cache.json")
        let cache = LookupCache(fileURL: fileURL, maximumSizeBytes: 256)

        try await cache.insert(result(named: String(repeating: "large", count: 200)), for: "large")

        let oversizedValue = await cache.value(for: "large")
        let usage = try await cache.usageBytes()
        XCTAssertNil(oversizedValue)
        XCTAssertLessThanOrEqual(usage, 256)
    }

    func testLiveCacheInstancesMergeAlternatingInsertsAndReloadReads() async throws {
        let fileURL = try temporaryDirectory().appending(path: "cache.json")
        let first = LookupCache(fileURL: fileURL)
        let second = LookupCache(fileURL: fileURL)
        let firstResult = result(named: "first")
        let secondResult = result(named: "second")

        try await first.insert(firstResult, for: "first")
        try await second.insert(secondResult, for: "second")

        let firstValues = (await first.value(for: "first"), await first.value(for: "second"))
        let secondValues = (await second.value(for: "first"), await second.value(for: "second"))
        XCTAssertEqual(firstValues.0, firstResult)
        XCTAssertEqual(firstValues.1, secondResult)
        XCTAssertEqual(secondValues.0, firstResult)
        XCTAssertEqual(secondValues.1, secondResult)
    }

    func testConcurrentDistinctCacheWritesPreserveEveryKey() async throws {
        let fileURL = try temporaryDirectory().appending(path: "cache.json")
        let caches = (0..<20).map { _ in LookupCache(fileURL: fileURL) }
        let results = caches.indices.map { result(named: "value-\($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in caches.indices {
                group.addTask {
                    try await caches[index].insert(results[index], for: "key-\(index)")
                }
            }
            try await group.waitForAll()
        }

        let observer = LookupCache(fileURL: fileURL)
        for index in caches.indices {
            let value = await observer.value(for: "key-\(index)")
            XCTAssertEqual(value, result(named: "value-\(index)"))
        }
    }

    func testCacheMigratesPersistedLegacyWordResult() async throws {
        let fileURL = try temporaryDirectory().appending(path: "cache.json")
        let legacyCache = #"{"legacy-key":{"word":{"_0":{"headword":"exchange","ipa":"/ɪksˈtʃeɪndʒ/","partOfSpeech":"noun","senses":["交流","交换"],"example":"That started an exchange.","exampleTranslation":"这开启了一场交流。","alternatives":["交锋"]}}}}"#
        try Data(legacyCache.utf8).write(to: fileURL)

        let cache = LookupCache(fileURL: fileURL)
        let recovered = await cache.value(for: "legacy-key")
        let cached = try XCTUnwrap(recovered)
        guard case let .word(word) = cached else {
            return XCTFail("Expected cached word result")
        }

        XCTAssertEqual(word.partsOfSpeech.count, 1)
        XCTAssertEqual(word.partsOfSpeech[0].name, "noun")
        XCTAssertEqual(word.partsOfSpeech[0].senses.map(\.chineseDefinition), ["交流", "交换"])
        let migratedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        XCTAssertEqual(migratedJSON["schemaVersion"] as? Int, 2)
        XCTAssertNotNil(migratedJSON["entries"])
    }

    func testHistorySaveIsExplicitUUIDIdempotentAndRemoveIsPhysical() async throws {
        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let store = LookupHistoryStore(fileURL: fileURL)
        let request = try LookupRequest(selection: "exchange")
        let lookupResult = LookupResult.word(.init(
            headword: "exchange",
            pronunciations: [],
            partsOfSpeech: [
                .init(name: "word", senses: [
                    .init(contextLabel: nil, englishDefinition: nil, chineseDefinition: "交流", examples: [])
                ])
            ],
            alternatives: []
        ))
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        try await store.save(
            request: request,
            result: lookupResult,
            providerName: "Mock",
            date: date,
            id: id
        )
        try await store.save(
            request: try LookupRequest(selection: "different"),
            result: result(named: "different"),
            providerName: "Other",
            date: date.addingTimeInterval(100),
            id: id
        )
        let entries = await store.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, id)
        XCTAssertEqual(entries.first?.selection, "exchange")
        XCTAssertEqual(entries.first?.providerName, "Mock")
        XCTAssertEqual(entries.first?.timestamp, date)
        XCTAssertEqual(entries.first?.isSaved, true)

        let reloaded = LookupHistoryStore(fileURL: fileURL)
        let reloadedIDs = await reloaded.entries.map(\.id)
        XCTAssertEqual(reloadedIDs, [id])

        try await reloaded.remove(id: id)
        let isEmptyAfterRemove = await reloaded.entries.isEmpty
        XCTAssertTrue(isEmptyAfterRemove)
        let persistedJSON = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        XCTAssertFalse(persistedJSON.contains(id.uuidString))
    }

    func testHistoryMigratesPersistedLegacyFlatWordResult() async throws {
        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let legacyHistory = #"{"isEnabled":false,"entries":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","selection":"exchange","kind":"word","result":{"word":{"_0":{"headword":"exchange","ipa":"/ɪksˈtʃeɪndʒ/","partOfSpeech":"noun","senses":["交流","交换"],"example":"That started an exchange.","exampleTranslation":"这开启了一场交流。","alternatives":["交锋"]}}},"timestamp":12345,"providerName":"Legacy Provider","isSaved":true}]}"#
        try Data(legacyHistory.utf8).write(to: fileURL)

        let store = LookupHistoryStore(fileURL: fileURL)
        let entries = await store.entries
        let entry = try XCTUnwrap(entries.first)
        guard case let .word(word) = entry.result else {
            return XCTFail("Expected migrated word result")
        }

        XCTAssertEqual(entry.id, UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        XCTAssertEqual(entry.selection, "exchange")
        XCTAssertEqual(entry.kind, .word)
        XCTAssertEqual(entry.timestamp, Date(timeIntervalSinceReferenceDate: 12_345))
        XCTAssertEqual(entry.providerName, "Legacy Provider")
        XCTAssertTrue(entry.isSaved)
        XCTAssertEqual(word.headword, "exchange")
        XCTAssertEqual(word.pronunciations, [.init(region: nil, ipa: "/ɪksˈtʃeɪndʒ/")])
        XCTAssertEqual(word.partsOfSpeech.map(\.name), ["noun"])
        XCTAssertEqual(word.partsOfSpeech[0].senses.map(\.chineseDefinition), ["交流", "交换"])
        XCTAssertEqual(word.partsOfSpeech[0].senses[0].examples, [
            .init(
                english: "That started an exchange.",
                chinese: "这开启了一场交流。",
                highlightedPhrase: nil
            )
        ])
        XCTAssertTrue(word.partsOfSpeech[0].senses[1].examples.isEmpty)
        XCTAssertEqual(word.alternatives, ["交锋"])
    }

    func testHistoryV1MigrationKeepsOnlySavedEntriesAndIsIdempotent() async throws {
        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let savedID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let unsavedID = "11111111-2222-3333-4444-555555555555"
        let legacyHistory = #"{"isEnabled":false,"entries":[{"id":"\#(savedID)","selection":"saved","kind":"word","result":{"word":{"_0":{"headword":"saved","ipa":null,"partOfSpeech":"noun","senses":["已收藏"],"example":null,"exampleTranslation":null,"alternatives":[]}}},"timestamp":12345,"providerName":"Legacy","isSaved":true},{"id":"\#(unsavedID)","selection":"private unsaved lookup","kind":"word","result":{"word":{"_0":{"headword":"private","ipa":null,"partOfSpeech":"noun","senses":["未收藏"],"example":null,"exampleTranslation":null,"alternatives":[]}}},"timestamp":12346,"providerName":"Legacy","isSaved":false}]}"#
        try Data(legacyHistory.utf8).write(to: fileURL)

        let store = LookupHistoryStore(fileURL: fileURL)
        try await store.prepare()
        let entries = await store.entries

        XCTAssertEqual(entries.map(\.id), [UUID(uuidString: savedID)!])
        XCTAssertEqual(entries.map(\.selection), ["saved"])
        let firstMigratedBytes = try Data(contentsOf: fileURL)
        let migratedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: firstMigratedBytes) as? [String: Any]
        )
        XCTAssertEqual(migratedJSON["schemaVersion"] as? Int, 2)
        XCTAssertFalse(String(decoding: firstMigratedBytes, as: UTF8.self).contains("private unsaved lookup"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: LookupHistoryStore.migrationBackupURL(for: fileURL).path
        ))

        let reloaded = LookupHistoryStore(fileURL: fileURL)
        try await reloaded.prepare()
        let reloadedIDs = await reloaded.entries.map(\.id)

        XCTAssertEqual(try Data(contentsOf: fileURL), firstMigratedBytes)
        XCTAssertEqual(reloadedIDs, [UUID(uuidString: savedID)!])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: LookupHistoryStore.migrationBackupURL(for: fileURL).path
        ))
    }

    func testHistoryMigrationFailureBeforeReplacementPreservesOriginalAndRetryResumes() async throws {
        enum InjectedFailure: Error { case stopBeforeReplacement }

        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let original = Data(#"{"isEnabled":true,"entries":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","selection":"saved","kind":"word","result":{"word":{"_0":{"headword":"saved","ipa":null,"partOfSpeech":"noun","senses":["已收藏"],"example":null,"exampleTranslation":null,"alternatives":[]}}},"timestamp":12345,"providerName":"Legacy","isSaved":true}]}"#.utf8)
        try original.write(to: fileURL)
        let backupURL = LookupHistoryStore.migrationBackupURL(for: fileURL)
        let failingStore = LookupHistoryStore(fileURL: fileURL) { stage in
            if stage == .beforePrimaryReplacement { throw InjectedFailure.stopBeforeReplacement }
        }

        do {
            try await failingStore.prepare()
            XCTFail("Expected injected migration failure")
        } catch InjectedFailure.stopBeforeReplacement {
            // Expected.
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)

        let retryingStore = LookupHistoryStore(fileURL: fileURL)
        try await retryingStore.prepare()
        let retriedSelections = await retryingStore.entries.map(\.selection)

        XCTAssertEqual(retriedSelections, ["saved"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testHistoryMigrationBackupConflictDoesNotModifyEitherFile() async throws {
        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let original = Data(#"{"isEnabled":true,"entries":[]}"#.utf8)
        let conflictingBackup = Data("not the same history".utf8)
        try original.write(to: fileURL)
        let backupURL = LookupHistoryStore.migrationBackupURL(for: fileURL)
        try conflictingBackup.write(to: backupURL)
        let store = LookupHistoryStore(fileURL: fileURL)

        do {
            try await store.prepare()
            XCTFail("Expected backup conflict")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertEqual(try Data(contentsOf: backupURL), conflictingBackup)
    }

    func testHistoryMigrationFailureAfterReplacementRollsBackOriginalBytes() async throws {
        enum InjectedFailure: Error { case stopAfterReplacement }

        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let original = Data(#"{"isEnabled":true,"entries":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","selection":"saved","kind":"word","result":{"word":{"_0":{"headword":"saved","ipa":null,"partOfSpeech":"noun","senses":["已收藏"],"example":null,"exampleTranslation":null,"alternatives":[]}}},"timestamp":12345,"providerName":"Legacy","isSaved":true}]}"#.utf8)
        try original.write(to: fileURL)
        let backupURL = LookupHistoryStore.migrationBackupURL(for: fileURL)
        let store = LookupHistoryStore(fileURL: fileURL) { stage in
            if stage == .afterPrimaryReplacement { throw InjectedFailure.stopAfterReplacement }
        }

        do {
            try await store.prepare()
            XCTFail("Expected injected post-replacement failure")
        } catch InjectedFailure.stopAfterReplacement {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: fileURL), original)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
    }

    func testHistorySavesAndClearsAllEntries() async throws {
        let store = LookupHistoryStore(fileURL: try temporaryDirectory().appending(path: "history.json"))
        let request = try LookupRequest(selection: "That started an exchange.")
        let result = LookupResult.passage(.init(translation: "这开启了一场交流。", nuanceNote: nil, literalGloss: nil))
        let id = UUID()

        try await store.save(request: request, result: result, providerName: "Mock", id: id)
        let isSaved = await store.entries.first?.isSaved
        XCTAssertEqual(isSaved, true)

        try await store.clear()
        let isEmpty = await store.entries.isEmpty
        XCTAssertTrue(isEmpty)
    }

    func testLiveHistoryInstancesMergeSavesAndPhysicalRemoval() async throws {
        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let first = LookupHistoryStore(fileURL: fileURL)
        let second = LookupHistoryStore(fileURL: fileURL)
        let firstID = UUID()
        let secondID = UUID()

        try await first.save(request: try LookupRequest(selection: "first"), result: result(named: "first"), providerName: "Test", id: firstID)
        try await second.save(request: try LookupRequest(selection: "second"), result: result(named: "second"), providerName: "Test", id: secondID)
        try await first.remove(id: secondID)

        let firstEntries = await first.entries
        let secondEntries = await second.entries
        XCTAssertEqual(firstEntries.map(\.id), [firstID])
        XCTAssertEqual(secondEntries.map(\.id), [firstID])
    }

    func testConcurrentDistinctHistoryWritesPreserveEveryEntry() async throws {
        let fileURL = try temporaryDirectory().appending(path: "history.json")
        let stores = (0..<20).map { _ in LookupHistoryStore(fileURL: fileURL) }
        let ids = (0..<20).map { _ in UUID() }
        let requests = try stores.indices.map { try LookupRequest(selection: "word-\($0)") }
        let results = stores.indices.map { result(named: "word-\($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in stores.indices {
                group.addTask {
                    try await stores[index].save(
                        request: requests[index],
                        result: results[index],
                        providerName: "Test",
                        id: ids[index]
                    )
                }
            }
            try await group.waitForAll()
        }

        let observer = LookupHistoryStore(fileURL: fileURL)
        let entries = await observer.entries
        XCTAssertEqual(Set(entries.map(\.id)), Set(ids))
    }

    private nonisolated func result(named name: String) -> LookupResult {
        .word(.init(
            headword: name,
            pronunciations: [],
            partsOfSpeech: [.init(name: "noun", senses: [
                .init(contextLabel: nil, englishDefinition: name, chineseDefinition: name, examples: [])
            ])],
            alternatives: []
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
