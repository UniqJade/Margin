import Foundation
import NaturalLanguage

public enum TranslationStyle: String, Codable, Sendable {
    case naturalPublishedProse
}

public struct LookupRequest: Codable, Equatable, Sendable {
    public let text: String
    public let kind: LookupKind
    public let sourceLanguage: String
    public let targetLanguage: String
    public let style: TranslationStyle

    public init(selection: String) throws {
        let normalized = try LookupInputNormalizer.normalize(selection)
        self.init(
            text: normalized,
            kind: LookupClassifier.classify(normalized),
            sourceLanguage: "en",
            targetLanguage: "zh-Hans",
            style: .naturalPublishedProse
        )
    }

    public init(
        text: String,
        kind: LookupKind,
        sourceLanguage: String,
        targetLanguage: String,
        style: TranslationStyle
    ) {
        self.text = text
        self.kind = kind
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.style = style
    }
}

public struct WordPronunciation: Codable, Equatable, Sendable {
    public let region: String?
    public let ipa: String

    public init(region: String?, ipa: String) {
        self.region = region
        self.ipa = ipa
    }
}

public struct WordExample: Codable, Equatable, Sendable {
    public let english: String
    public let chinese: String
    public let highlightedPhrase: String?

    public init(english: String, chinese: String, highlightedPhrase: String?) {
        self.english = english
        self.chinese = chinese
        self.highlightedPhrase = highlightedPhrase
    }
}

public struct WordSense: Codable, Equatable, Sendable {
    public let contextLabel: String?
    public let englishDefinition: String?
    public let chineseDefinition: String
    public let examples: [WordExample]

    public init(
        contextLabel: String?,
        englishDefinition: String?,
        chineseDefinition: String,
        examples: [WordExample]
    ) {
        self.contextLabel = contextLabel
        self.englishDefinition = englishDefinition
        self.chineseDefinition = chineseDefinition
        self.examples = examples
    }
}

public struct WordPartOfSpeech: Codable, Equatable, Sendable {
    public let name: String
    public let senses: [WordSense]

    public init(name: String, senses: [WordSense]) {
        self.name = name
        self.senses = senses
    }
}

public struct WordLookupResult: Codable, Equatable, Sendable {
    public let headword: String
    public let pronunciations: [WordPronunciation]
    public let partsOfSpeech: [WordPartOfSpeech]
    public let alternatives: [String]

    public init(
        headword: String,
        pronunciations: [WordPronunciation],
        partsOfSpeech: [WordPartOfSpeech],
        alternatives: [String]
    ) {
        self.headword = headword
        self.pronunciations = pronunciations
        self.partsOfSpeech = partsOfSpeech
        self.alternatives = alternatives
    }

    private enum CodingKeys: String, CodingKey {
        case headword
        case pronunciations
        case partsOfSpeech
        case alternatives
        case ipa
        case partOfSpeech
        case senses
        case example
        case exampleTranslation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let headword = try container.decode(String.self, forKey: .headword)
        let alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []

        if container.contains(.partsOfSpeech) {
            self.init(
                headword: headword,
                pronunciations: try container.decode([WordPronunciation].self, forKey: .pronunciations),
                partsOfSpeech: try container.decode([WordPartOfSpeech].self, forKey: .partsOfSpeech),
                alternatives: alternatives
            )
            return
        }

        let representation = Self.legacyRepresentation(
            ipa: try container.decodeIfPresent(String.self, forKey: .ipa),
            partOfSpeech: try container.decodeIfPresent(String.self, forKey: .partOfSpeech),
            senses: try container.decodeIfPresent([String].self, forKey: .senses) ?? [],
            example: try container.decodeIfPresent(String.self, forKey: .example),
            exampleTranslation: try container.decodeIfPresent(String.self, forKey: .exampleTranslation)
        )
        self.init(
            headword: headword,
            pronunciations: representation.pronunciations,
            partsOfSpeech: representation.partsOfSpeech,
            alternatives: alternatives
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headword, forKey: .headword)
        try container.encode(pronunciations, forKey: .pronunciations)
        try container.encode(partsOfSpeech, forKey: .partsOfSpeech)
        try container.encode(alternatives, forKey: .alternatives)
    }

    private static func legacyRepresentation(
        ipa: String?,
        partOfSpeech: String?,
        senses: [String],
        example: String?,
        exampleTranslation: String?
    ) -> (pronunciations: [WordPronunciation], partsOfSpeech: [WordPartOfSpeech]) {
        let legacyExample: WordExample?
        if example != nil || exampleTranslation != nil {
            legacyExample = WordExample(
                english: example ?? "",
                chinese: exampleTranslation ?? "",
                highlightedPhrase: nil
            )
        } else {
            legacyExample = nil
        }
        let wordSenses = senses.enumerated().map { index, definition in
            WordSense(
                contextLabel: nil,
                englishDefinition: nil,
                chineseDefinition: definition,
                examples: index == 0 ? [legacyExample].compactMap { $0 } : []
            )
        }

        return (
            pronunciations: ipa.map { [WordPronunciation(region: nil, ipa: $0)] } ?? [],
            partsOfSpeech: [
                WordPartOfSpeech(name: partOfSpeech ?? "word", senses: wordSenses)
            ]
        )
    }
}

public struct PassageSourceSentence: Codable, Equatable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

public enum PassageSentenceSegmenter {
    public static func segment(_ text: String) -> [PassageSourceSentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        let fullRange = text.startIndex..<text.endIndex
        let segments = tokenizer.tokens(for: fullRange).compactMap { range -> String? in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : sentence
        }
        let normalizedSegments: [String]
        if segments.isEmpty {
            let fallback = text.trimmingCharacters(in: .whitespacesAndNewlines)
            normalizedSegments = fallback.isEmpty ? [] : [fallback]
        } else {
            normalizedSegments = segments
        }
        return normalizedSegments.enumerated().map {
            PassageSourceSentence(id: $0.offset + 1, text: $0.element)
        }
    }
}

public struct PassageAlignmentBlock: Codable, Equatable, Sendable, Hashable {
    public let sourceSentenceIDs: [Int]
    public let translation: String

    public init(sourceSentenceIDs: [Int], translation: String) {
        self.sourceSentenceIDs = sourceSentenceIDs
        self.translation = translation
    }
}

public struct PassageLookupResult: Codable, Equatable, Sendable {
    public let translation: String
    public let alignmentBlocks: [PassageAlignmentBlock]
    public let nuanceNote: String?
    public let literalGloss: String?

    public init(translation: String, nuanceNote: String?, literalGloss: String?) {
        self.translation = translation
        self.alignmentBlocks = []
        self.nuanceNote = nuanceNote
        self.literalGloss = literalGloss
    }

    public init(
        alignmentBlocks: [PassageAlignmentBlock],
        nuanceNote: String?,
        literalGloss: String?
    ) {
        self.translation = alignmentBlocks.map(\.translation).joined()
        self.alignmentBlocks = alignmentBlocks
        self.nuanceNote = nuanceNote
        self.literalGloss = literalGloss
    }

    private enum CodingKeys: String, CodingKey {
        case translation
        case alignmentBlocks
        case nuanceNote
        case literalGloss
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alignmentBlocks = try container.decodeIfPresent(
            [PassageAlignmentBlock].self,
            forKey: .alignmentBlocks
        ) ?? []
        let nuanceNote = try container.decodeIfPresent(String.self, forKey: .nuanceNote)
        let literalGloss = try container.decodeIfPresent(String.self, forKey: .literalGloss)

        if alignmentBlocks.isEmpty {
            self.init(
                translation: try container.decode(String.self, forKey: .translation),
                nuanceNote: nuanceNote,
                literalGloss: literalGloss
            )
        } else {
            self.init(
                alignmentBlocks: alignmentBlocks,
                nuanceNote: nuanceNote,
                literalGloss: literalGloss
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(translation, forKey: .translation)
        try container.encode(alignmentBlocks, forKey: .alignmentBlocks)
        try container.encodeIfPresent(nuanceNote, forKey: .nuanceNote)
        try container.encodeIfPresent(literalGloss, forKey: .literalGloss)
    }
}

public enum LookupResult: Codable, Equatable, Sendable {
    case word(WordLookupResult)
    case passage(PassageLookupResult)
}
