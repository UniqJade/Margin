import Foundation

public struct WordTextSegment: Equatable, Sendable {
    public let text: String
    public let isHighlighted: Bool

    public init(text: String, isHighlighted: Bool) {
        self.text = text
        self.isHighlighted = isHighlighted
    }
}

public extension WordPartOfSpeech {
    var abbreviation: String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalizedName {
        case "adjective": return "adj."
        case "noun": return "n."
        case "verb": return "v."
        case "adverb": return "adv."
        case "preposition": return "prep."
        case "pronoun": return "pron."
        case "conjunction": return "conj."
        case "interjection": return "interj."
        case "phrasal verb": return "phr. v."
        default:
            let pieces = normalizedName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            let sanitized = pieces.filter { !$0.isEmpty }.joined()
            return sanitized.isEmpty ? "word" : String(sanitized.prefix(8))
        }
    }

    var anchorID: String {
        let normalizedName = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let pieces = normalizedName.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let slug = pieces.filter { !$0.isEmpty }.joined(separator: "-")
        return "pos-\(slug.isEmpty ? "word" : slug)"
    }
}

public extension Collection where Element == WordPartOfSpeech {
    var uniqueAnchorIDs: [String] {
        var usedIDs: Set<String> = []
        return map { group in
            let baseID = group.anchorID
            var candidate = baseID
            var suffix = 2
            while !usedIDs.insert(candidate).inserted {
                candidate = "\(baseID)-\(suffix)"
                suffix += 1
            }
            return candidate
        }
    }
}

public extension WordExample {
    var validatedHighlightedPhrase: String? {
        guard let highlightedPhrase,
              !highlightedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              english.range(of: highlightedPhrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
            return nil
        }
        return highlightedPhrase
    }

    /// Splits the English example around the first explicit matching phrase only.
    var highlightedEnglishSegments: [WordTextSegment] {
        guard let phrase = validatedHighlightedPhrase,
              let range = english.range(
                of: phrase,
                options: [.caseInsensitive, .diacriticInsensitive]
              ) else {
            return english.isEmpty ? [] : [.init(text: english, isHighlighted: false)]
        }

        var segments: [WordTextSegment] = []
        let prefix = String(english[..<range.lowerBound])
        let match = String(english[range])
        let suffix = String(english[range.upperBound...])
        if !prefix.isEmpty { segments.append(.init(text: prefix, isHighlighted: false)) }
        if !match.isEmpty { segments.append(.init(text: match, isHighlighted: true)) }
        if !suffix.isEmpty { segments.append(.init(text: suffix, isHighlighted: false)) }
        return segments
    }
}
