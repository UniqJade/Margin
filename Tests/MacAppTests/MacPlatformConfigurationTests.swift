import Foundation
import XCTest
@testable import Margin

@MainActor
final class MacPlatformConfigurationTests: XCTestCase {
    func testMacUsesStandardPreferencesAndFreshLocalKeychainService() {
        XCTAssertTrue(SharedConfiguration.defaults === UserDefaults.standard)
        let configuredService = Bundle.main.object(
            forInfoDictionaryKey: "MarginMacKeychainService"
        ) as? String
        XCTAssertNotNil(configuredService)
        XCTAssertEqual(SharedConfiguration.keychainService, configuredService)
    }

    func testMacStoresLookupDataInItsApplicationSupportDirectory() throws {
        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )

        XCTAssertEqual(
            SharedConfiguration.storageDirectory.standardizedFileURL,
            applicationSupport
                .appending(path: "Margin", directoryHint: .isDirectory)
                .appending(path: "Mac-v2", directoryHint: .isDirectory)
                .standardizedFileURL
        )
    }

    func testMacPreferencesIgnoreLegacySharedKeys() throws {
        let suiteName = "MacPlatformConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("https://legacy.example/v1", forKey: "provider.endpoint")
        defaults.set("legacy-model", forKey: "provider.model")
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertEqual(preferences.endpoint, ProviderPreferences.defaultEndpoint)
        XCTAssertEqual(preferences.model, "deepseek-v4-flash")
    }
}
