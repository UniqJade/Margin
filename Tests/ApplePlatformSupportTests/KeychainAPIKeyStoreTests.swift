import Security
import XCTest
@testable import ApplePlatformSupport

final class KeychainAPIKeyStoreTests: XCTestCase {
    func testBaseQueryIsDeviceOnlyAndDoesNotSynchronize() {
        let query = KeychainQueryBuilder.baseQuery(service: "dev.example.BooksTranslator", account: "cloud-api-key")

        XCTAssertEqual(query[kSecClass] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService] as? String, "dev.example.BooksTranslator")
        XCTAssertEqual(query[kSecAttrAccount] as? String, "cloud-api-key")
        XCTAssertEqual(query[kSecAttrSynchronizable] as? Bool, false)
        XCTAssertEqual(
            query[kSecAttrAccessible] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    func testVaultUpdatesMemoryCacheAfterSaveAndDelete() throws {
        let store = MemorySecretStore()
        let vault = APIKeyVault(store: store)

        try vault.save("sk-personal")
        XCTAssertEqual(try vault.read(), "sk-personal")
        try vault.delete()
        XCTAssertNil(try vault.read())
    }

    func testVaultReadsUnderlyingKeychainOnlyOncePerLifetime() throws {
        let store = MemorySecretStore(value: "sk-personal")
        let vault = APIKeyVault(store: store)

        XCTAssertEqual(try vault.read(), "sk-personal")
        XCTAssertEqual(try vault.read(), "sk-personal")
        XCTAssertEqual(store.readCount, 1)
    }
}

private final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private var value: String?
    private(set) var readCount = 0

    init(value: String? = nil) {
        self.value = value
    }

    func save(_ secret: String) throws { value = secret }
    func read() throws -> String? {
        readCount += 1
        return value
    }
    func delete() throws { value = nil }
}
