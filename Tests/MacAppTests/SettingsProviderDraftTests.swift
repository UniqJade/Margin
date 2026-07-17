import XCTest
@testable import Margin

final class SettingsProviderDraftTests: XCTestCase {
    func testCustomConfigurationIsPreservedInDraft() {
        let draft = ProviderSettingsDraft(
            endpoint: "https://compatible.example/v1",
            model: "custom-model"
        )

        XCTAssertEqual(draft.endpoint, "https://compatible.example/v1")
        XCTAssertEqual(draft.model, "custom-model")
        XCTAssertFalse(draft.isUsingDeepSeek)
    }

    func testResetToDeepSeekRestoresCertifiedDefaults() {
        var draft = ProviderSettingsDraft(
            endpoint: "https://compatible.example/v1",
            model: "custom-model"
        )

        draft.resetToDeepSeek()

        XCTAssertEqual(draft.endpoint, "https://api.deepseek.com")
        XCTAssertEqual(draft.model, "deepseek-v4-flash")
        XCTAssertTrue(draft.isUsingDeepSeek)
    }
}
