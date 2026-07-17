import Foundation

enum SharedConfiguration {
#if os(macOS)
    static let keychainService = configuredValue(
        forInfoKey: "MarginMacKeychainService",
        publicFallback: "dev.example.Margin.mac.v2"
    )

    static var defaults: UserDefaults { .standard }

    static var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "Margin", directoryHint: .isDirectory)
            .appending(path: "Mac-v2", directoryHint: .isDirectory)
    }
#else
    static let appGroupIdentifier = configuredValue(
        forInfoKey: "MarginAppGroupIdentifier",
        publicFallback: "group.dev.example.BooksTranslator"
    )
    static let keychainService = configuredValue(
        forInfoKey: "MarginSharedKeychainService",
        publicFallback: "dev.example.BooksTranslator.shared"
    )

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var storageDirectory: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return groupURL.appending(path: "LookupData", directoryHint: .isDirectory)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "Margin", directoryHint: .isDirectory)
    }
#endif

    private static func configuredValue(forInfoKey key: String, publicFallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return publicFallback
        }
        return value
    }
}
