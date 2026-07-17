import XCTest
@testable import Margin

@MainActor
final class ProviderAndFirstRunStateTests: XCTestCase {
    func testFreshPreferencesUseDeepSeekDefaults() {
        let preferences = ProviderPreferences(defaults: makeTemporaryDefaults())

        XCTAssertEqual(preferences.endpoint, "https://api.deepseek.com")
        XCTAssertEqual(preferences.model, "deepseek-v4-flash")
    }

    func testSavedProviderConfigurationTakesPrecedenceOverDeepSeekDefaults() {
        let defaults = makeTemporaryDefaults()
        defaults.set("https://compatible.example/v1", forKey: ProviderPreferences.endpointDefaultsKey)
        defaults.set("custom-model", forKey: ProviderPreferences.modelDefaultsKey)

        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertEqual(preferences.endpoint, "https://compatible.example/v1")
        XCTAssertEqual(preferences.model, "custom-model")
    }

    func testFreshFirstRunStateIsIncomplete() {
        let state = FirstRunState(defaults: makeTemporaryDefaults())

        XCTAssertFalse(state.isComplete)
    }

    func testCompletingFirstRunPublishesAndPersists() {
        let defaults = makeTemporaryDefaults()
        let state = FirstRunState(defaults: defaults)

        state.complete()

        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(defaults.object(forKey: FirstRunState.completedDefaultsKey) as? Bool, true)
        XCTAssertTrue(FirstRunState(defaults: defaults).isComplete)
    }

    func testSavedProviderConfigurationMigratesAsCompletedFirstRun() {
        let defaults = makeTemporaryDefaults()
        defaults.set("https://compatible.example/v1", forKey: ProviderPreferences.endpointDefaultsKey)
        defaults.set("custom-model", forKey: ProviderPreferences.modelDefaultsKey)

        XCTAssertTrue(FirstRunState(defaults: defaults).isComplete)
        XCTAssertEqual(defaults.object(forKey: FirstRunState.completedDefaultsKey) as? Bool, true)
    }

    func testPartialSavedProviderConfigurationDoesNotSkipFirstRun() {
        let defaults = makeTemporaryDefaults()
        defaults.set("https://compatible.example/v1", forKey: ProviderPreferences.endpointDefaultsKey)

        XCTAssertFalse(FirstRunState(defaults: defaults).isComplete)
    }

    func testExplicitIncompleteStateOverridesSavedProviderMigration() {
        let defaults = makeTemporaryDefaults()
        defaults.set(false, forKey: FirstRunState.completedDefaultsKey)
        defaults.set("https://compatible.example/v1", forKey: ProviderPreferences.endpointDefaultsKey)
        defaults.set("custom-model", forKey: ProviderPreferences.modelDefaultsKey)

        XCTAssertFalse(FirstRunState(defaults: defaults).isComplete)
    }
}
