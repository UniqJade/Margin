import LookupCore
import XCTest
@testable import Margin

#if os(macOS)
import AppKit
#endif

final class ChineseTypographyNormalizerTests: XCTestCase {
    func testNormalizesChinesePunctuationAndHorizontalSpacing() {
        let input = "丘吉尔写道, 他能流利地表达意见 , 其力度无人能及!"

        XCTAssertEqual(
            ChineseTypographyNormalizer.normalize(input),
            "丘吉尔写道，他能流利地表达意见，其力度无人能及！"
        )
    }

    func testNormalizesTopLevelAndNestedQuotationMarks() {
        let input = #"他说, "他称之为 '真正的胜利'。""#

        XCTAssertEqual(
            ChineseTypographyNormalizer.normalize(input),
            "他说，“他称之为‘真正的胜利’。”"
        )
    }

    func testNormalizesCJKQuotationMarkVariantsByNestingLevel() {
        let input = "丘吉尔写道：「这是『真正的胜利』。」"

        XCTAssertEqual(
            ChineseTypographyNormalizer.normalize(input),
            "丘吉尔写道：“这是‘真正的胜利’。”"
        )
    }

    func testNormalizesEnglishStyleSingleQuotationAroundChinese() {
        let input = "他 ‘能轻松有力地表达意见’。"

        XCTAssertEqual(
            ChineseTypographyNormalizer.normalize(input),
            "他“能轻松有力地表达意见”。"
        )
    }

    func testPreservesLatinApostrophesNumbersURLsAndLatinWordSpacing() {
        let input = "O'Connor 使用 DeepSeek API 处理 3.14 和 https://example.com/a,b。"

        XCTAssertEqual(ChineseTypographyNormalizer.normalize(input), input)
    }

    func testLeavesUnmatchedQuotationGlyphUntouched() {
        let input = "他说 ‘这句话没有结束。"

        XCTAssertEqual(
            ChineseTypographyNormalizer.normalize(input),
            "他说‘这句话没有结束。"
        )
    }

    func testCanonicalCompositionAndNormalizationAreIdempotent() {
        let decomposed = "Cafe\u{301}, 中文 之间。"
        let once = ChineseTypographyNormalizer.normalize(decomposed)

        XCTAssertEqual(once, "Café, 中文之间。")
        XCTAssertEqual(ChineseTypographyNormalizer.normalize(once), once)
    }

    func testPassageVisibleContentUsesNormalizedChineseForBothModes() {
        let original = "First sentence. Second sentence."
        let passage = PassageLookupResult(
            alignmentBlocks: [
                .init(sourceSentenceIDs: [1], translation: #"他说, "第一句。""#),
                .init(sourceSentenceIDs: [2], translation: "接着, 他写了第二句。"),
            ],
            nuanceNote: nil,
            literalGloss: nil
        )

        XCTAssertEqual(
            PassageVisibleContent.text(
                for: .naturalTranslation,
                originalText: original,
                passage: passage
            ),
            "他说，“第一句。”接着，他写了第二句。"
        )
        XCTAssertEqual(
            PassageVisibleContent.text(
                for: .bilingualView,
                originalText: original,
                passage: passage
            ),
            "First sentence.\n他说，“第一句。”\n\nSecond sentence.\n接着，他写了第二句。"
        )
    }

    func testDisplayNormalizationRemovesCachedAppleBooksAttributionFooter() {
        let polluted = "正文译文。摘录来自 Churchill Winston Churchill 此内容可能受版权保护。"

        XCTAssertEqual(ChineseTypographyNormalizer.normalize(polluted), "正文译文。")
    }

    func testBilingualPresentationDropsCachedAttributionOnlyBlock() {
        let original = """
        First sentence.
        Excerpt From Example Book Example Author This material may be protected by copyright.
        """
        let passage = PassageLookupResult(
            alignmentBlocks: [
                .init(sourceSentenceIDs: [1], translation: "正文译文。"),
                .init(
                    sourceSentenceIDs: [2],
                    translation: "摘录来自 Example Book Example Author 此内容可能受版权保护。"
                ),
            ],
            nuanceNote: nil,
            literalGloss: nil
        )

        XCTAssertEqual(
            PassageVisibleContent.text(
                for: .naturalTranslation,
                originalText: original,
                passage: passage
            ),
            "正文译文。"
        )
        XCTAssertEqual(
            PassageVisibleContent.text(
                for: .bilingualView,
                originalText: original,
                passage: passage
            ),
            "First sentence.\n正文译文。"
        )
        XCTAssertEqual(
            PassageAlignmentPresentation.blocks(
                originalText: original,
                passage: passage
            ).count,
            1
        )
    }

    #if os(macOS)
    @MainActor
    func testChineseReadingTypographyPreservesSongtiAndCompressesOnlyCommaSpacing() {
        XCTAssertTrue(ChineseReadingTypography.macFont.familyName?.contains("Songti") == true)
        XCTAssertLessThan(ChineseReadingTypography.kerning(for: "，"), 0)
        XCTAssertEqual(ChineseReadingTypography.kerning(for: "。"), 0)
        XCTAssertEqual(ChineseReadingTypography.kerning(for: "“"), 0)
    }
    #endif
}
