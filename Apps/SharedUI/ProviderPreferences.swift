import Foundation

struct ProviderPreferences: Sendable {
    static let defaultEndpoint = "https://api.deepseek.com"
    static let defaultModel = "deepseek-v4-flash"
#if os(macOS)
    static let endpointDefaultsKey = "mac.v2.provider.endpoint"
    static let modelDefaultsKey = "mac.v2.provider.model"
#else
    static let endpointDefaultsKey = "provider.endpoint"
    static let modelDefaultsKey = "provider.model"
#endif

    var endpoint: String
    var model: String

    init(defaults: UserDefaults = SharedConfiguration.defaults) {
        endpoint = defaults.string(forKey: Self.endpointDefaultsKey) ?? Self.defaultEndpoint
        model = defaults.string(forKey: Self.modelDefaultsKey) ?? Self.defaultModel
    }

    func save(defaults: UserDefaults = SharedConfiguration.defaults) {
        defaults.set(endpoint, forKey: Self.endpointDefaultsKey)
        defaults.set(model, forKey: Self.modelDefaultsKey)
    }
}
