import Foundation
import LookupCore
import XCTest

final class EvaluationCorpusTests: XCTestCase {
    func testCorpusIsDecodableAndCoversRequiredCategories() throws {
        let cases = try loadCorpus()
        let categories = Set(cases.map(\.category))

        XCTAssertGreaterThanOrEqual(cases.count, 10)
        XCTAssertTrue(["word", "prose", "dialogue", "idiom", "ambiguity", "punctuation", "adversarial"].allSatisfy(categories.contains))
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count)
        XCTAssertTrue(["biography", "history", "dialogue", "idiom", "injection", "xml-like"].allSatisfy(Set(cases.map(\.id)).contains))
    }

    func testAmbiguousWordsSpecifyProviderOrderedNumberedBilingualEntries() throws {
        let casesByID = Dictionary(uniqueKeysWithValues: try loadCorpus().map { ($0.id, $0) })

        for (id, expectedGroups) in [
            ("ambiguous-intimate", ["adjective", "verb"]),
            ("ambiguous-record", ["noun", "verb"]),
            ("ambiguous-close", ["adjective", "verb", "noun"]),
        ] {
            let entry = try XCTUnwrap(casesByID[id]?.expectedWordEntry, "Missing required case \(id)")
            XCTAssertEqual(entry.providerOrderPOSGroups.map(\.name), expectedGroups, "Provider order changed for \(id)")

            for group in entry.providerOrderPOSGroups {
                XCTAssertFalse(group.senses.isEmpty, "\(id) must exercise every POS group")
                XCTAssertEqual(group.senses.map(\.number), Array(1...group.senses.count))
                for sense in group.senses {
                    XCTAssertFalse(sense.englishDefinition.isEmpty)
                    XCTAssertFalse(sense.chineseDefinition.isEmpty)
                }
            }

            let examples = entry.providerOrderPOSGroups.flatMap(\.senses).flatMap(\.examples)
            XCTAssertTrue(examples.contains { !$0.english.isEmpty && !$0.chinese.isEmpty })
        }
    }

    func testRequiredAmbiguousSourcesAreWordSelectionsWithSeparateContext() throws {
        let casesByID = Dictionary(uniqueKeysWithValues: try loadCorpus().map { ($0.id, $0) })

        for (id, token) in [
            ("ambiguous-intimate", "intimate"),
            ("ambiguous-record", "record"),
            ("ambiguous-close", "close"),
        ] {
            let corpusCase = try XCTUnwrap(casesByID[id], "Missing required case \(id)")
            let request = try LookupRequest(selection: corpusCase.source)

            XCTAssertEqual(corpusCase.source, token)
            XCTAssertEqual(request.text, token)
            XCTAssertEqual(request.kind, .word)
            XCTAssertFalse(try XCTUnwrap(corpusCase.context).isEmpty)
        }
    }

    func testCorpusIncludesRepeatedHighlightedPhraseExample() throws {
        let examples = try loadCorpus()
            .compactMap(\.expectedWordEntry)
            .flatMap(\.providerOrderPOSGroups)
            .flatMap(\.senses)
            .flatMap(\.examples)

        let repeated = try XCTUnwrap(examples.first { example in
            guard let phrase = example.highlightedPhrase, !phrase.isEmpty else { return false }
            return example.english.components(separatedBy: phrase).count - 1 > 1
        })
        let example = WordExample(
            english: repeated.english,
            chinese: repeated.chinese,
            highlightedPhrase: repeated.highlightedPhrase
        )

        XCTAssertEqual(example.highlightedEnglishSegments, [
            .init(text: "The ", isHighlighted: false),
            .init(text: "close", isHighlighted: true),
            .init(text: " friends sat close together.", isHighlighted: false),
        ])
    }

    private func loadCorpus() throws -> [CorpusCase] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "evaluation-corpus", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([CorpusCase].self, from: Data(contentsOf: url))
    }
}

private struct CorpusCase: Decodable {
    let id: String
    let category: String
    let source: String
    let context: String?
    let qualityFocus: String
    let expectedWordEntry: ExpectedWordEntry?

    enum CodingKeys: String, CodingKey {
        case id, category, source, context
        case qualityFocus = "quality_focus"
        case expectedWordEntry = "expected_word_entry"
    }
}

private struct ExpectedWordEntry: Decodable {
    let providerOrderPOSGroups: [ExpectedPOSGroup]

    enum CodingKeys: String, CodingKey {
        case providerOrderPOSGroups = "provider_order_pos_groups"
    }
}

private struct ExpectedPOSGroup: Decodable {
    let name: String
    let senses: [ExpectedSense]
}

private struct ExpectedSense: Decodable {
    let number: Int
    let englishDefinition: String
    let chineseDefinition: String
    let examples: [ExpectedExample]

    enum CodingKeys: String, CodingKey {
        case number, examples
        case englishDefinition = "english_definition"
        case chineseDefinition = "chinese_definition"
    }
}

private struct ExpectedExample: Decodable {
    let english: String
    let chinese: String
    let highlightedPhrase: String?

    enum CodingKeys: String, CodingKey {
        case english, chinese
        case highlightedPhrase = "highlighted_phrase"
    }
}
