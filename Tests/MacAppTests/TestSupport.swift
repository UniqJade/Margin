import ApplePlatformSupport
import Foundation
import LookupCore
import XCTest
@testable import Margin

@MainActor
extension XCTestCase {
    func makeIsolatedSession(
        lookupOperation: ((String) async throws -> LookupOutcome)? = nil,
        historySnapshotOperation: (() async throws -> LookupSession.HistorySnapshot)? = nil
    ) -> LookupSession {
        LookupSession(
            defaults: makeTemporaryDefaults(),
            vault: APIKeyVault(store: TestSecretStore()),
            lookupOperation: lookupOperation,
            historySnapshotOperation: historySnapshotOperation,
            loadInitialHistory: false,
            storageDirectory: makeTemporaryStorageDirectory()
        )
    }

    func makeTemporaryDefaults() -> UserDefaults {
        let suiteName = "MarginMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func makeTemporaryStorageDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MarginMacTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

final class TestSecretStore: SecretStore, @unchecked Sendable {
    private var value: String?

    func save(_ secret: String) throws { value = secret }
    func read() throws -> String? { value }
    func delete() throws { value = nil }
}
