import Foundation
import Security

public protocol SecretStore: Sendable {
    func save(_ secret: String) throws
    func read() throws -> String?
    func delete() throws
}

public final class APIKeyVault: @unchecked Sendable {
    private enum CacheState {
        case unloaded
        case loaded(String?)
    }

    private let store: any SecretStore
    private let lock = NSLock()
    private var cacheState = CacheState.unloaded

    public init(store: any SecretStore) {
        self.store = store
    }

    public func save(_ apiKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try store.save(apiKey)
        cacheState = .loaded(apiKey)
    }

    public func read() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if case let .loaded(apiKey) = cacheState { return apiKey }
        let apiKey = try store.read()
        cacheState = .loaded(apiKey)
        return apiKey
    }

    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        try store.delete()
        cacheState = .loaded(nil)
    }
}

public enum KeychainStoreError: Error, LocalizedError, Sendable {
    case operationFailed
    case invalidStoredValue

    public var errorDescription: String? {
        switch self {
        case .operationFailed:
            String(localized: "The API key could not be saved securely.", bundle: .module)
        case .invalidStoredValue:
            String(localized: "The saved API key could not be read. Delete it and enter it again.", bundle: .module)
        }
    }
}

enum KeychainQueryBuilder {
    static func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}

public final class KeychainAPIKeyStore: SecretStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String, account: String = "cloud-api-key") {
        self.service = service
        self.account = account
    }

    public func save(_ secret: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainStoreError.invalidStoredValue
        }
        var query = KeychainQueryBuilder.baseQuery(service: service, account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed
        }
        query[kSecValueData] = data
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw KeychainStoreError.operationFailed
        }
    }

    public func read() throws -> String? {
        var query = KeychainQueryBuilder.baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidStoredValue
        }
        return value
    }

    public func delete() throws {
        let status = SecItemDelete(KeychainQueryBuilder.baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed
        }
    }
}
