import XCTest
@testable import LookupCore

final class PassagePartialTests: XCTestCase {
    func testProseIsCompletedBlocksThenInProgress() {
        let partial = PassagePartial(
            completedBlocks: [
                PassageAlignmentBlock(
                    sourceSentenceIDs: [1],
                    translation: "第一句。"
                )
            ],
            inProgress: InProgressBlock(
                sourceSentenceIDs: [2],
                text: "第二句进行中"
            )
        )

        XCTAssertEqual(partial.prose, "第一句。第二句进行中")
    }
}

final class IncrementalPassageParserTests: XCTestCase {
    private func feed(_ chunks: [String]) -> IncrementalPassageParser {
        var parser = IncrementalPassageParser()
        for chunk in chunks {
            parser.append(chunk)
        }
        return parser
    }

    func testSingleCompleteBlock() {
        let json = #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"这是第一句。"}],"nuance_note":null,"literal_gloss":null}"#
        let parser = feed([json])

        XCTAssertFalse(parser.isDegraded)
        XCTAssertEqual(
            parser.snapshot.completedBlocks,
            [PassageAlignmentBlock(
                sourceSentenceIDs: [1],
                translation: "这是第一句。"
            )]
        )
        XCTAssertNil(parser.snapshot.inProgress)
    }

    func testInProgressTranslationExposesIDsAndPartialText() {
        let parser = feed([
            #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"这是第"#
        ])

        XCTAssertFalse(parser.isDegraded)
        XCTAssertEqual(
            parser.snapshot.inProgress,
            InProgressBlock(sourceSentenceIDs: [1], text: "这是第")
        )
    }

    func testProseGrowsMonotonicallyAcrossArbitraryChunkBoundaries() {
        let json = #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"巷尾那栋老屋"},{"source_sentence_ids":[2],"translation":"已空置多年。"}],"nuance_note":null,"literal_gloss":null}"#
        let expected = "巷尾那栋老屋已空置多年。"
        var parser = IncrementalPassageParser()
        var previous = ""

        for character in json {
            parser.append(String(character))
            let prose = parser.snapshot.prose
            XCTAssertTrue(expected.hasPrefix(prose))
            XCTAssertGreaterThanOrEqual(prose.count, previous.count)
            previous = prose
        }

        XCTAssertEqual(parser.snapshot.prose, expected)
        XCTAssertEqual(parser.snapshot.completedBlocks.count, 2)
    }

    func testHandlesEscapesInTranslation() {
        let json = #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"他说\"你好\"，然后\n离开。"}],"nuance_note":null,"literal_gloss":null}"#
        let parser = feed([json])

        XCTAssertEqual(
            parser.snapshot.completedBlocks.first?.translation,
            "他说\"你好\"，然后\n离开。"
        )
    }

    func testHandlesUnicodeEscapeSplitAcrossChunks() {
        let head = #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"A\u4e2"#
        let tail = #"d B"}],"nuance_note":null,"literal_gloss":null}"#
        let parser = feed([head, tail])

        XCTAssertFalse(parser.isDegraded)
        XCTAssertEqual(
            parser.snapshot.completedBlocks.first?.translation,
            "A中 B"
        )
    }

    func testHandlesSurrogatePairEscapeSplitAtEveryOffset() {
        let prefix = #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"笑"#
        let suffix = #""}],"nuance_note":null,"literal_gloss":null}"#
        let escaped = #"\uD83D\uDE00"#

        for cut in 0...escaped.count {
            let index = escaped.index(escaped.startIndex, offsetBy: cut)
            let parser = feed([
                prefix + String(escaped[..<index]),
                String(escaped[index...]) + suffix,
            ])

            XCTAssertFalse(parser.isDegraded, "cut \(cut)")
            XCTAssertEqual(
                parser.snapshot.completedBlocks.first?.translation,
                "笑😀",
                "cut \(cut)"
            )
        }
    }

    func testUnpairedSurrogateDegrades() {
        let parser = feed([
            #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"x\uD83Dy"}],"nuance_note":null,"literal_gloss":null}"#
        ])

        XCTAssertTrue(parser.isDegraded)
    }

    func testMultipleSourceSentenceIDsInOneBlock() {
        let json = #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[2,3],"translation":"合并两句。"}],"nuance_note":null,"literal_gloss":null}"#
        let parser = feed([json])

        XCTAssertEqual(
            parser.snapshot.completedBlocks.first?.sourceSentenceIDs,
            [2, 3]
        )
    }

    func testToleratesPrettyPrintedWhitespace() {
        let json = """
        {
          "kind": "passage",
          "alignment_blocks": [
            {
              "source_sentence_ids": [1],
              "translation": "排版容错。"
            }
          ],
          "nuance_note": null,
          "literal_gloss": null
        }
        """
        let parser = feed([json])

        XCTAssertFalse(parser.isDegraded)
        XCTAssertEqual(
            parser.snapshot.completedBlocks.first?.translation,
            "排版容错。"
        )
    }

    func testDegradesOnMalformedStructureAndStopsUpdating() {
        var parser = IncrementalPassageParser()
        parser.append(
            #"{"kind":"passage","alignment_blocks":[{"source_sentence_ids":[1],"translation":"ok。"}"#
        )
        let before = parser.snapshot
        parser.append(#", GARBAGE ¬json"#)

        XCTAssertTrue(parser.isDegraded)
        XCTAssertEqual(parser.snapshot, before)
    }
}
