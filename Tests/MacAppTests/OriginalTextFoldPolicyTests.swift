import XCTest
import LookupCore
@testable import Margin

final class OriginalTextFoldPolicyTests: XCTestCase {
    func testEqualFullAndCollapsedHeightsAreNotTruncated() {
        XCTAssertFalse(
            OriginalTextFoldPolicy.isTruncated(fullHeight: 80, collapsedHeight: 80)
        )
    }

    func testFullHeightBeyondCollapsedHeightIsTruncated() {
        XCTAssertTrue(
            OriginalTextFoldPolicy.isTruncated(fullHeight: 120, collapsedHeight: 80)
        )
    }

    func testSubpixelHeightNoiseIsNotTruncated() {
        XCTAssertFalse(
            OriginalTextFoldPolicy.isTruncated(fullHeight: 80.4, collapsedHeight: 80)
        )
    }

    func testNewFoldStateStartsCollapsedAndUnmeasured() {
        let state = OriginalTextFoldState()

        XCTAssertFalse(state.isExpanded)
        XCTAssertEqual(state.fullHeight, 0)
        XCTAssertEqual(state.collapsedHeight, 0)
    }

    func testOriginalTextPresentationIdentityChangesWithText() {
        let first = OriginalTextPresentationIdentity(text: "First passage")
        let second = OriginalTextPresentationIdentity(text: "Second passage")

        XCTAssertNotEqual(first, second)
    }

    func testPassagePresentationIdentityChangesWithOriginalText() {
        let first = makePassageIdentity(originalText: "First passage", translation: "第一段")
        let second = makePassageIdentity(originalText: "Second passage", translation: "第一段")

        XCTAssertNotEqual(first, second)
    }

    func testPassagePresentationIdentityChangesWithTranslationResult() {
        let first = makePassageIdentity(originalText: "Same passage", translation: "第一版")
        let second = makePassageIdentity(originalText: "Same passage", translation: "第二版")

        XCTAssertNotEqual(first, second)
    }

    func testNewPassagePresentationStateStartsCollapsedAndUnmeasured() {
        let state = PassagePresentationState()

        XCTAssertEqual(state.readingMode, .naturalTranslation)
        XCTAssertFalse(state.showsLiteralView)
        XCTAssertEqual(state.readingHeight, 0)
        XCTAssertEqual(state.actionHeight, 0)
    }

    func testPassagePresentationIdentityChangesWithSemanticAlignment() {
        let first = makePassageIdentity(
            originalText: "Same passage",
            translation: "同一译文",
            alignmentBlocks: [.init(sourceSentenceIDs: [1], translation: "同一译文")]
        )
        let second = makePassageIdentity(
            originalText: "Same passage",
            translation: "同一译文",
            alignmentBlocks: [.init(sourceSentenceIDs: [1, 2], translation: "同一译文")]
        )

        XCTAssertNotEqual(first, second)
    }

    func testVisibleTextFollowsReadingMode() {
        let original = "First sentence. Second sentence."
        let passage = PassageLookupResult(
            alignmentBlocks: [
                .init(sourceSentenceIDs: [1], translation: "第一句。"),
                .init(sourceSentenceIDs: [2], translation: "第二句。"),
            ],
            nuanceNote: nil,
            literalGloss: nil
        )

        XCTAssertEqual(
            PassageVisibleContent.text(for: .naturalTranslation, originalText: original, passage: passage),
            "第一句。第二句。"
        )
        XCTAssertEqual(
            PassageVisibleContent.text(for: .semanticAlignment, originalText: original, passage: passage),
            "First sentence.\n第一句。\n\nSecond sentence.\n第二句。"
        )
    }

    private func makePassageIdentity(
        originalText: String,
        translation: String,
        alignmentBlocks: [PassageAlignmentBlock] = []
    ) -> PassagePresentationIdentity {
        PassagePresentationIdentity(
            originalText: originalText,
            translation: translation,
            alignmentBlocks: alignmentBlocks,
            nuanceNote: nil,
            literalGloss: "Literal",
            providerName: "DeepSeek",
            wasCached: false,
            outcomeID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
    }
}
