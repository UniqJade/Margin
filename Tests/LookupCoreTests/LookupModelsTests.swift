import XCTest
@testable import LookupCore

final class LookupModelsTests: XCTestCase {
    private let richWord = WordLookupResult(
        headword: "exchange",
        pronunciations: [
            WordPronunciation(region: "UK", ipa: "/ɪksˈtʃeɪndʒ/"),
            WordPronunciation(region: "US", ipa: "/ɪksˈtʃeɪndʒ/")
        ],
        partsOfSpeech: [
            WordPartOfSpeech(
                name: "adjective",
                senses: [
                    WordSense(
                        contextLabel: "commerce",
                        englishDefinition: "relating to an exchange",
                        chineseDefinition: "交易的",
                        examples: []
                    )
                ]
            ),
            WordPartOfSpeech(
                name: "noun",
                senses: [
                    WordSense(
                        contextLabel: nil,
                        englishDefinition: "a conversation or discussion",
                        chineseDefinition: "交流",
                        examples: [
                            WordExample(
                                english: "That started an exchange.",
                                chinese: "这开启了一场交流。",
                                highlightedPhrase: "an exchange"
                            )
                        ]
                    ),
                    WordSense(
                        contextLabel: "goods",
                        englishDefinition: "the act of giving one thing and receiving another",
                        chineseDefinition: "交换",
                        examples: []
                    )
                ]
            )
        ],
        alternatives: ["交锋"]
    )

    func testRequestFactoryNormalizesAndClassifiesSelection() throws {
        let request = try LookupRequest(selection: "  cyanide-laced \n")

        XCTAssertEqual(request.text, "cyanide-laced")
        XCTAssertEqual(request.kind, .word)
        XCTAssertEqual(request.sourceLanguage, "en")
        XCTAssertEqual(request.targetLanguage, "zh-Hans")
        XCTAssertEqual(request.style, .naturalPublishedProse)
    }

    func testRequestFactoryRemovesChineseAppleBooksAttributionFooter() throws {
        let request = try LookupRequest(selection: """
        On 31 May 1940, Churchill flew to Paris.

        摘录来自
        Churchill
        Winston Churchill
        此内容可能受版权保护。
        """)

        XCTAssertEqual(request.text, "On 31 May 1940, Churchill flew to Paris.")
        XCTAssertEqual(request.kind, .passage)
    }

    func testRequestFactoryRemovesEnglishAppleBooksAttributionFooter() throws {
        let request = try LookupRequest(selection: """
        That started an exchange.

        Excerpt From
        Example Book
        Example Author
        This material may be protected by copyright.
        """)

        XCTAssertEqual(request.text, "That started an exchange.")
    }

    func testRequestFactoryPreservesIncompleteAttributionLikeText() throws {
        let selection = "The essay discusses the phrase Excerpt From without a copyright notice."

        XCTAssertEqual(try LookupRequest(selection: selection).text, selection)
    }

    func testAttributionCleanerRequiresSourceMetadataAndIsIdempotent() {
        let incomplete = "正文。摘录来自 此内容可能受版权保护。"
        XCTAssertEqual(AppleBooksAttributionCleaner.removingFooter(from: incomplete), incomplete)

        let polluted = "正文。摘录来自 Example Book 此内容可能受版权保护。"
        let cleaned = AppleBooksAttributionCleaner.removingFooter(from: polluted)
        XCTAssertEqual(cleaned, "正文。")
        XCTAssertEqual(AppleBooksAttributionCleaner.removingFooter(from: cleaned), cleaned)
    }

    func testRichWordResultRoundTripsThroughJSON() throws {
        let result = LookupResult.word(richWord)

        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(LookupResult.self, from: data), result)
    }

    func testLegacyWordResultDecodesIntoOnePartOfSpeech() throws {
        let legacy = #"{"headword":"exchange","ipa":"/ɪksˈtʃeɪndʒ/","partOfSpeech":"noun","senses":["交流","交换"],"example":"That started an exchange.","exampleTranslation":"这开启了一场交流。","alternatives":["交锋"]}"#

        let word = try JSONDecoder().decode(WordLookupResult.self, from: Data(legacy.utf8))

        XCTAssertEqual(word.pronunciations, [.init(region: nil, ipa: "/ɪksˈtʃeɪndʒ/")])
        XCTAssertEqual(word.partsOfSpeech.map(\.name), ["noun"])
        XCTAssertEqual(word.partsOfSpeech[0].senses.map(\.chineseDefinition), ["交流", "交换"])
        XCTAssertNil(word.partsOfSpeech[0].senses[0].englishDefinition)
        XCTAssertEqual(word.partsOfSpeech[0].senses[0].examples.first?.english, "That started an exchange.")
        XCTAssertEqual(word.partsOfSpeech[0].senses[0].examples.first?.chinese, "这开启了一场交流。")
        XCTAssertTrue(word.partsOfSpeech[0].senses[1].examples.isEmpty)
    }

    func testLegacyWordResultWithoutPartOfSpeechUsesWordGroup() throws {
        let legacy = #"{"headword":"exchange","senses":["交流"],"alternatives":[]}"#

        let word = try JSONDecoder().decode(WordLookupResult.self, from: Data(legacy.utf8))

        XCTAssertEqual(word.partsOfSpeech.map(\.name), ["word"])
    }

    func testLegacyWordResultPreservesEnglishOnlyExample() throws {
        let legacy = #"{"headword":"exchange","senses":["交流"],"example":"That started an exchange.","alternatives":[]}"#

        let word = try JSONDecoder().decode(WordLookupResult.self, from: Data(legacy.utf8))

        XCTAssertEqual(
            word.partsOfSpeech[0].senses[0].examples,
            [.init(english: "That started an exchange.", chinese: "", highlightedPhrase: nil)]
        )
    }

    func testLegacyWordResultPreservesChineseOnlyExample() throws {
        let legacy = #"{"headword":"exchange","senses":["交流"],"exampleTranslation":"这开启了一场交流。","alternatives":[]}"#

        let word = try JSONDecoder().decode(WordLookupResult.self, from: Data(legacy.utf8))

        XCTAssertEqual(
            word.partsOfSpeech[0].senses[0].examples,
            [.init(english: "", chinese: "这开启了一场交流。", highlightedPhrase: nil)]
        )
    }

    func testWordResultEncodesOnlyNewRepresentation() throws {
        let data = try JSONEncoder().encode(richWord)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(object["pronunciations"])
        XCTAssertNotNil(object["partsOfSpeech"])
        XCTAssertNil(object["ipa"])
        XCTAssertNil(object["partOfSpeech"])
        XCTAssertNil(object["senses"])
        XCTAssertNil(object["example"])
        XCTAssertNil(object["exampleTranslation"])
    }

    func testPartOfSpeechPresentationIsStableAndSanitized() {
        XCTAssertEqual(WordPartOfSpeech(name: "adjective", senses: []).abbreviation, "adj.")
        XCTAssertEqual(WordPartOfSpeech(name: "noun", senses: []).abbreviation, "n.")
        XCTAssertEqual(WordPartOfSpeech(name: "verb", senses: []).abbreviation, "v.")
        XCTAssertEqual(WordPartOfSpeech(name: "phrasal verb", senses: []).anchorID, "pos-phrasal-verb")
    }

    func testPartOfSpeechAnchorIDsAreUniqueAndStableInProviderOrder() {
        let groups = [
            WordPartOfSpeech(name: "phrasal verb", senses: []),
            WordPartOfSpeech(name: "phrasal-verb", senses: []),
            WordPartOfSpeech(name: "phrasal verb", senses: []),
            WordPartOfSpeech(name: " -- ", senses: []),
            WordPartOfSpeech(name: "?!", senses: []),
        ]
        let expected = [
            "pos-phrasal-verb",
            "pos-phrasal-verb-2",
            "pos-phrasal-verb-3",
            "pos-word",
            "pos-word-2",
        ]

        XCTAssertEqual(groups.uniqueAnchorIDs, expected)
        XCTAssertEqual(groups.uniqueAnchorIDs, expected)
    }

    func testPartOfSpeechAnchorIDsAvoidNaturalSlugSuffixCollisions() {
        let duplicateBeforeNaturalSlug = ["noun", "noun", "noun 2"].map {
            WordPartOfSpeech(name: $0, senses: [])
        }
        let naturalSlugBeforeDuplicate = ["noun", "noun 2", "noun"].map {
            WordPartOfSpeech(name: $0, senses: [])
        }

        XCTAssertEqual(
            duplicateBeforeNaturalSlug.uniqueAnchorIDs,
            ["pos-noun", "pos-noun-2", "pos-noun-2-2"]
        )
        XCTAssertEqual(
            naturalSlugBeforeDuplicate.uniqueAnchorIDs,
            ["pos-noun", "pos-noun-2", "pos-noun-3"]
        )
        XCTAssertEqual(
            Set(duplicateBeforeNaturalSlug.uniqueAnchorIDs).count,
            duplicateBeforeNaturalSlug.count
        )
        XCTAssertEqual(
            Set(naturalSlugBeforeDuplicate.uniqueAnchorIDs).count,
            naturalSlugBeforeDuplicate.count
        )
    }

    func testPartOfSpeechAnchorIDCanonicalizesEquivalentUnicode() {
        let composed = WordPartOfSpeech(name: "café", senses: [])
        let decomposed = WordPartOfSpeech(name: "cafe\u{301}", senses: [])

        XCTAssertEqual(composed.anchorID, "pos-cafe")
        XCTAssertEqual(decomposed.anchorID, composed.anchorID)
    }

    func testUnknownPartOfSpeechAbbreviationIsSafeAndBounded() {
        let abbreviation = WordPartOfSpeech(name: "  UnKnown-Type?! ", senses: []).abbreviation

        XCTAssertEqual(abbreviation, "unknownt")
        XCTAssertLessThanOrEqual(abbreviation.count, 8)
        XCTAssertTrue(abbreviation.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains))
        XCTAssertEqual(WordPartOfSpeech(name: " --?! ", senses: []).abbreviation, "word")
    }

    func testHighlightedPhraseMustExistInsideEnglishExample() {
        let valid = WordExample(
            english: "We are on intimate terms.",
            chinese: "我们关系密切。",
            highlightedPhrase: "intimate terms"
        )
        let invalid = WordExample(
            english: "We are close friends.",
            chinese: "我们是密友。",
            highlightedPhrase: "intimate terms"
        )
        let caseVariant = WordExample(
            english: "We are on intimate terms.",
            chinese: "我们关系密切。",
            highlightedPhrase: "INTIMATE TERMS"
        )
        let empty = WordExample(english: "Example", chinese: "例子", highlightedPhrase: "")
        let whitespaceOnly = WordExample(english: "Example", chinese: "例子", highlightedPhrase: " \n ")

        XCTAssertEqual(valid.validatedHighlightedPhrase, "intimate terms")
        XCTAssertNil(invalid.validatedHighlightedPhrase)
        XCTAssertEqual(caseVariant.validatedHighlightedPhrase, "INTIMATE TERMS")
        XCTAssertNil(empty.validatedHighlightedPhrase)
        XCTAssertNil(whitespaceOnly.validatedHighlightedPhrase)
    }

    func testHighlightedEnglishSegmentsBoldOnlyFirstExplicitMatch() {
        let example = WordExample(
            english: "Please close the book before you close the drawer.",
            chinese: "请先合上书，再关上抽屉。",
            highlightedPhrase: "close"
        )

        XCTAssertEqual(example.highlightedEnglishSegments, [
            .init(text: "Please ", isHighlighted: false),
            .init(text: "close", isHighlighted: true),
            .init(text: " the book before you close the drawer.", isHighlighted: false),
        ])
    }

    func testHighlightedEnglishSegmentsMatchCaseAndDiacriticsUsingSourceRanges() {
        let example = WordExample(
            english: "The CAFÉ café stayed open.",
            chinese: "这家咖啡馆一直营业。",
            highlightedPhrase: "cafe"
        )

        XCTAssertEqual(example.highlightedEnglishSegments, [
            .init(text: "The ", isHighlighted: false),
            .init(text: "CAFÉ", isHighlighted: true),
            .init(text: " café stayed open.", isHighlighted: false),
        ])
    }

    func testHighlightedEnglishSegmentsUseOnePlainRunWhenPhraseDoesNotMatch() {
        let example = WordExample(
            english: "We are close friends.",
            chinese: "我们是密友。",
            highlightedPhrase: "intimate"
        )

        XCTAssertEqual(example.highlightedEnglishSegments, [
            .init(text: "We are close friends.", isHighlighted: false)
        ])
    }

    func testAlignedPassageResultRoundTripsThroughJSONAndDerivesTranslation() throws {
        let result = LookupResult.passage(
            PassageLookupResult(
                alignmentBlocks: [
                    PassageAlignmentBlock(
                        sourceSentenceIDs: [1],
                        translation: "这开启了一场关于苹果早期历史的交流，"
                    ),
                    PassageAlignmentBlock(
                        sourceSentenceIDs: [2, 3],
                        translation: "也让我开始为一本可能写成的书搜集材料。"
                    ),
                ],
                nuanceNote: "exchange 在此指持续的讨论。",
                literalGloss: "那开启了一场交流。"
            )
        )

        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(LookupResult.self, from: data), result)
        guard case let .passage(passage) = result else { return XCTFail("Expected passage") }
        XCTAssertEqual(
            passage.translation,
            "这开启了一场关于苹果早期历史的交流，也让我开始为一本可能写成的书搜集材料。"
        )
    }

    func testLegacyPassageResultDecodesWithoutInventingAlignment() throws {
        let legacy = #"{"translation":"这是一段旧译文。","nuanceNote":null,"literalGloss":null}"#

        let passage = try JSONDecoder().decode(PassageLookupResult.self, from: Data(legacy.utf8))

        XCTAssertEqual(passage.translation, "这是一段旧译文。")
        XCTAssertTrue(passage.alignmentBlocks.isEmpty)
    }

    func testPassageSentenceSegmenterPreservesSentenceOrderAndPunctuation() {
        let sentences = PassageSentenceSegmenter.segment(
            #"He asked, “Really?” She nodded. Then they left together."#
        )

        XCTAssertEqual(sentences.map(\.id), [1, 2, 3])
        XCTAssertEqual(sentences.map(\.text), [
            #"He asked, “Really?”"#,
            "She nodded.",
            "Then they left together.",
        ])
    }
}
