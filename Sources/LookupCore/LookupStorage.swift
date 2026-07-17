import CryptoKit
import Foundation

public enum LookupCacheKey {
    public static func make(request: LookupRequest, providerIdentifier: String) -> String {
        let input = [
            request.text,
            request.kind.rawValue,
            request.sourceLanguage,
            request.targetLanguage,
            request.style.rawValue,
            providerIdentifier,
        ].joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LookupCacheEntry: Codable, Equatable {
    var result: LookupResult
    var lastAccessSequence: UInt64
}

private struct LookupCacheState: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var accessSequence: UInt64 = 0
    var entries: [String: LookupCacheEntry] = [:]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case accessSequence
        case entries
    }

    init() {}

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           container.contains(.schemaVersion) {
            let version = try container.decode(Int.self, forKey: .schemaVersion)
            guard version == Self.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported lookup cache schema version \(version)."
                )
            }
            schemaVersion = version
            accessSequence = try container.decode(UInt64.self, forKey: .accessSequence)
            entries = try container.decode([String: LookupCacheEntry].self, forKey: .entries)
            return
        }

        let legacyValues = try decoder.singleValueContainer().decode([String: LookupResult].self)
        let orderedKeys = legacyValues.keys.sorted()
        accessSequence = UInt64(orderedKeys.count)
        entries = Dictionary(uniqueKeysWithValues: orderedKeys.enumerated().compactMap { offset, key in
            legacyValues[key].map {
                (key, LookupCacheEntry(result: $0, lastAccessSequence: UInt64(offset + 1)))
            }
        })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(accessSequence, forKey: .accessSequence)
        try container.encode(entries, forKey: .entries)
    }

    mutating func nextAccessSequence() -> UInt64 {
        if accessSequence == .max {
            let orderedKeys = entries.keys.sorted {
                let left = entries[$0]?.lastAccessSequence ?? 0
                let right = entries[$1]?.lastAccessSequence ?? 0
                return left == right ? $0 < $1 : left < right
            }
            for (offset, key) in orderedKeys.enumerated() {
                entries[key]?.lastAccessSequence = UInt64(offset + 1)
            }
            accessSequence = UInt64(orderedKeys.count)
        }
        accessSequence += 1
        return accessSequence
    }
}

public actor LookupCache {
    public static let defaultMaximumSizeBytes = 10_000_000

    private let storage: SidecarLockedJSONFile<LookupCacheState>
    private let maximumSizeBytes: Int
    private var state: LookupCacheState

    public init(
        fileURL: URL,
        maximumSizeBytes: Int = LookupCache.defaultMaximumSizeBytes
    ) {
        precondition(maximumSizeBytes > 0, "Cache byte limit must be positive.")
        self.storage = SidecarLockedJSONFile(fileURL: fileURL, emptyState: LookupCacheState.init)
        self.maximumSizeBytes = maximumSizeBytes
        self.state = LookupCacheState()
    }

    public func value(for key: String) -> LookupResult? {
        var recovered: LookupResult?
        do {
            let updated = try storage.update { latest in
                if latest.entries[key] != nil {
                    let sequence = latest.nextAccessSequence()
                    latest.entries[key]?.lastAccessSequence = sequence
                }
                try Self.prune(&latest, maximumSizeBytes: maximumSizeBytes)
                recovered = latest.entries[key]?.result
            }
            state = updated
            return recovered
        } catch {
            state = storage.read(fallingBackTo: state)
            return state.entries[key]?.result
        }
    }

    public func insert(_ result: LookupResult, for key: String) throws {
        let updated = try storage.update { latest in
            latest.entries[key] = LookupCacheEntry(
                result: result,
                lastAccessSequence: latest.nextAccessSequence()
            )
            try Self.prune(&latest, maximumSizeBytes: maximumSizeBytes)
        }
        state = updated
    }

    public func usageBytes() throws -> Int {
        let snapshot = try storage.withExclusiveLock { () -> (LookupCacheState, Int) in
            guard FileManager.default.fileExists(atPath: storage.fileURL.path) else {
                return (LookupCacheState(), 0)
            }
            var latest = try JSONDecoder().decode(
                LookupCacheState.self,
                from: Data(contentsOf: storage.fileURL)
            )
            try Self.prune(&latest, maximumSizeBytes: maximumSizeBytes)
            let encoded = try JSONEncoder().encode(latest)
            try encoded.write(to: storage.fileURL, options: .atomic)
            return (latest, encoded.count)
        }
        state = snapshot.0
        return snapshot.1
    }

    public func clear() throws {
        try storage.withExclusiveLock {
            guard FileManager.default.fileExists(atPath: storage.fileURL.path) else { return }
            try FileManager.default.removeItem(at: storage.fileURL)
        }
        state = LookupCacheState()
    }

    private static func prune(
        _ state: inout LookupCacheState,
        maximumSizeBytes: Int
    ) throws {
        let encoder = JSONEncoder()
        while try encoder.encode(state).count > maximumSizeBytes,
              let leastRecentlyUsedKey = state.entries.keys.min(by: { left, right in
                  let leftSequence = state.entries[left]?.lastAccessSequence ?? 0
                  let rightSequence = state.entries[right]?.lastAccessSequence ?? 0
                  return leftSequence == rightSequence ? left < right : leftSequence < rightSequence
              }) {
            state.entries.removeValue(forKey: leastRecentlyUsedKey)
        }
    }
}

public struct LookupHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let selection: String
    public let kind: LookupKind
    public let result: LookupResult
    public let timestamp: Date
    public let providerName: String
    public var isSaved: Bool
}

private struct LookupHistoryState: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var isEnabled = true
    var entries: [LookupHistoryEntry] = []
}

private struct LegacyLookupHistoryState: Codable {
    var isEnabled = true
    var entries: [LookupHistoryEntry] = []
}

enum LookupHistoryMigrationStage: Sendable {
    case beforePrimaryReplacement
    case afterPrimaryReplacement
}

private enum LookupHistoryMigrationError: Error {
    case backupConflict
    case backupVerificationFailed
    case migratedFileVerificationFailed
    case rollbackFailed
}

public actor LookupHistoryStore {
    private let storage: SidecarLockedJSONFile<LookupHistoryState>
    private let migrationHook: (@Sendable (LookupHistoryMigrationStage) throws -> Void)?
    private var state: LookupHistoryState
    private var isPrepared = false

    public init(fileURL: URL) {
        self.storage = SidecarLockedJSONFile(fileURL: fileURL, emptyState: LookupHistoryState.init)
        self.migrationHook = nil
        self.state = LookupHistoryState()
    }

    init(
        fileURL: URL,
        migrationHook: @escaping @Sendable (LookupHistoryMigrationStage) throws -> Void
    ) {
        self.storage = SidecarLockedJSONFile(fileURL: fileURL, emptyState: LookupHistoryState.init)
        self.migrationHook = migrationHook
        self.state = LookupHistoryState()
    }

    static func migrationBackupURL(for fileURL: URL) -> URL {
        fileURL.appendingPathExtension("v1-migration-backup")
    }

    public func prepare() throws {
        try prepareIfNeeded()
    }

    public var entries: [LookupHistoryEntry] {
        try? prepareIfNeeded()
        state = storage.read(fallingBackTo: state)
        return state.entries
    }

    @discardableResult
    public func save(
        request: LookupRequest,
        result: LookupResult,
        providerName: String,
        date: Date = .now,
        id: UUID = UUID()
    ) throws -> UUID {
        try prepareIfNeeded()
        let updated = try storage.update { latest in
            guard !latest.entries.contains(where: { $0.id == id }) else { return }
            latest.entries.insert(LookupHistoryEntry(
                id: id,
                selection: request.text,
                kind: request.kind,
                result: result,
                timestamp: date,
                providerName: providerName,
                isSaved: true
            ), at: 0)
        }
        state = updated
        return id
    }

    public func remove(id: UUID) throws {
        try prepareIfNeeded()
        let updated = try storage.update { latest in
            latest.entries.removeAll(where: { $0.id == id })
        }
        state = updated
    }

    public func clear() throws {
        try prepareIfNeeded()
        let updated = try storage.update { $0.entries = [] }
        state = updated
    }

    private func prepareIfNeeded() throws {
        guard !isPrepared else { return }
        let preparedState = try storage.withExclusiveLock {
            try Self.loadOrMigrate(
                fileURL: storage.fileURL,
                migrationHook: migrationHook
            )
        }
        state = preparedState
        isPrepared = true
    }

    private static func loadOrMigrate(
        fileURL: URL,
        migrationHook: (@Sendable (LookupHistoryMigrationStage) throws -> Void)?
    ) throws -> LookupHistoryState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LookupHistoryState()
        }

        let originalData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        if let current = try? decoder.decode(LookupHistoryState.self, from: originalData),
           current.schemaVersion == LookupHistoryState.currentSchemaVersion {
            let sanitized = LookupHistoryState(
                isEnabled: current.isEnabled,
                entries: savedEntriesDeduplicated(current.entries)
            )
            if sanitized != current {
                try JSONEncoder().encode(sanitized).write(to: fileURL, options: .atomic)
            }
            try cleanupInterruptedBackupIfSafe(currentState: sanitized, fileURL: fileURL)
            return sanitized
        }

        let legacy = try decoder.decode(LegacyLookupHistoryState.self, from: originalData)
        let migrated = LookupHistoryState(
            isEnabled: legacy.isEnabled,
            entries: savedEntriesDeduplicated(legacy.entries)
        )
        let backupURL = migrationBackupURL(for: fileURL)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            guard try Data(contentsOf: backupURL) == originalData else {
                throw LookupHistoryMigrationError.backupConflict
            }
        } else {
            try originalData.write(to: backupURL, options: .atomic)
        }
        guard try Data(contentsOf: backupURL) == originalData else {
            throw LookupHistoryMigrationError.backupVerificationFailed
        }

        try migrationHook?(.beforePrimaryReplacement)
        let migratedData = try JSONEncoder().encode(migrated)
        do {
            try migratedData.write(to: fileURL, options: .atomic)
            try migrationHook?(.afterPrimaryReplacement)
            let verified = try decoder.decode(LookupHistoryState.self, from: Data(contentsOf: fileURL))
            guard verified == migrated else {
                throw LookupHistoryMigrationError.migratedFileVerificationFailed
            }
        } catch {
            do {
                try originalData.write(to: fileURL, options: .atomic)
                guard try Data(contentsOf: fileURL) == originalData else {
                    throw LookupHistoryMigrationError.rollbackFailed
                }
            } catch {
                throw LookupHistoryMigrationError.rollbackFailed
            }
            throw error
        }

        try? FileManager.default.removeItem(at: backupURL)
        return migrated
    }

    private static func cleanupInterruptedBackupIfSafe(
        currentState: LookupHistoryState,
        fileURL: URL
    ) throws {
        let backupURL = migrationBackupURL(for: fileURL)
        guard FileManager.default.fileExists(atPath: backupURL.path),
              let backupData = try? Data(contentsOf: backupURL),
              let legacy = try? JSONDecoder().decode(LegacyLookupHistoryState.self, from: backupData) else {
            return
        }
        let expected = LookupHistoryState(
            isEnabled: legacy.isEnabled,
            entries: savedEntriesDeduplicated(legacy.entries)
        )
        if expected == currentState {
            try? FileManager.default.removeItem(at: backupURL)
        }
    }

    private static func savedEntriesDeduplicated(
        _ entries: [LookupHistoryEntry]
    ) -> [LookupHistoryEntry] {
        var seen = Set<UUID>()
        return entries.filter { entry in
            entry.isSaved && seen.insert(entry.id).inserted
        }
    }
}
