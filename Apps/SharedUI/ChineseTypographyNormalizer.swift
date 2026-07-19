import Foundation

enum ChineseTypographyNormalizer {
    private struct OpenQuote {
        let index: Int
        let character: Character
        let depth: Int
    }

    private static let punctuationMap: [Character: Character] = [
        ",": "，",
        ";": "；",
        ":": "：",
        "?": "？",
        "!": "！",
        ".": "。",
    ]
    private static let pairedClosingQuote: [Character: Character] = [
        "“": "”",
        "‘": "’",
        "「": "」",
        "『": "』",
    ]
    private static let ambiguousQuotes: Set<Character> = ["\"", "'"]
    private static let closingQuotes = Set(pairedClosingQuote.values)
    private static let normalizedOpeningQuotes: Set<Character> = ["“", "‘"]
    private static let normalizedClosingQuotes: Set<Character> = ["”", "’"]
    private static let chinesePunctuation: Set<Character> = [
        "，", "。", "；", "：", "？", "！", "、",
        "）", "】", "》",
    ]

    static func normalize(_ text: String) -> String {
        let canonical = text.precomposedStringWithCanonicalMapping
        var characters = Array(canonical)
        normalizeQuotationMarks(in: &characters)
        normalizePunctuation(in: &characters)
        removeUnwantedHorizontalSpacing(in: &characters)
        return String(characters)
    }

    private static func normalizeQuotationMarks(in characters: inout [Character]) {
        var stack: [OpenQuote] = []
        var replacements: [Int: Character] = [:]

        for index in characters.indices {
            let character = characters[index]
            if isLatinApostrophe(at: index, in: characters) {
                continue
            }

            if pairedClosingQuote[character] != nil {
                stack.append(OpenQuote(index: index, character: character, depth: stack.count))
                continue
            }

            if closingQuotes.contains(character) {
                guard let opening = stack.last,
                      pairedClosingQuote[opening.character] == character else {
                    continue
                }
                stack.removeLast()
                recordQuoteReplacements(
                    opening: opening,
                    closingIndex: index,
                    in: characters,
                    replacements: &replacements
                )
                continue
            }

            guard ambiguousQuotes.contains(character) else { continue }
            if let opening = stack.last, opening.character == character {
                stack.removeLast()
                recordQuoteReplacements(
                    opening: opening,
                    closingIndex: index,
                    in: characters,
                    replacements: &replacements
                )
            } else {
                stack.append(OpenQuote(index: index, character: character, depth: stack.count))
            }
        }

        for (index, replacement) in replacements {
            characters[index] = replacement
        }
    }

    private static func recordQuoteReplacements(
        opening: OpenQuote,
        closingIndex: Int,
        in characters: [Character],
        replacements: inout [Int: Character]
    ) {
        guard hasChineseContext(
            from: opening.index,
            through: closingIndex,
            in: characters
        ) else {
            return
        }
        let isOuterLevel = opening.depth.isMultiple(of: 2)
        replacements[opening.index] = isOuterLevel ? "“" : "‘"
        replacements[closingIndex] = isOuterLevel ? "”" : "’"
    }

    private static func hasChineseContext(
        from openingIndex: Int,
        through closingIndex: Int,
        in characters: [Character]
    ) -> Bool {
        if characters[(openingIndex + 1)..<closingIndex].contains(where: isIdeographic) {
            return true
        }
        if let previous = previousVisibleCharacter(before: openingIndex, in: characters),
           isIdeographic(previous) {
            return true
        }
        if let next = nextVisibleCharacter(after: closingIndex, in: characters),
           isIdeographic(next) {
            return true
        }
        return false
    }

    private static func normalizePunctuation(in characters: inout [Character]) {
        for index in characters.indices {
            let character = characters[index]
            guard let replacement = punctuationMap[character],
                  let previous = previousVisibleCharacter(before: index, in: characters),
                  isIdeographic(previous) || normalizedClosingQuotes.contains(previous) else {
                continue
            }

            if character == ".",
               let next = nextVisibleCharacter(after: index, in: characters),
               isASCIILetterOrDigit(next) {
                continue
            }
            characters[index] = replacement
        }
    }

    private static func removeUnwantedHorizontalSpacing(in characters: inout [Character]) {
        characters = characters.enumerated().compactMap { index, character in
            guard isHorizontalWhitespace(character),
                  let previous = previousVisibleCharacter(before: index, in: characters),
                  let next = nextVisibleCharacter(after: index, in: characters),
                  shouldRemoveWhitespace(between: previous, and: next) else {
                return character
            }
            return nil
        }
    }

    private static func shouldRemoveWhitespace(
        between previous: Character,
        and next: Character
    ) -> Bool {
        if isIdeographic(previous), isIdeographic(next) {
            return true
        }
        if chinesePunctuation.contains(previous) {
            return true
        }
        if isIdeographic(previous),
           chinesePunctuation.contains(next) || normalizedOpeningQuotes.contains(next)
                || normalizedClosingQuotes.contains(next) {
            return true
        }
        if normalizedOpeningQuotes.contains(previous), isIdeographic(next) {
            return true
        }
        if normalizedClosingQuotes.contains(previous),
           isIdeographic(next) || chinesePunctuation.contains(next) {
            return true
        }
        return false
    }

    private static func isLatinApostrophe(
        at index: Int,
        in characters: [Character]
    ) -> Bool {
        guard characters[index] == "'" || characters[index] == "’",
              index > characters.startIndex,
              index < characters.index(before: characters.endIndex) else {
            return false
        }
        return isASCIILetterOrDigit(characters[index - 1])
            && isASCIILetterOrDigit(characters[index + 1])
    }

    private static func previousVisibleCharacter(
        before index: Int,
        in characters: [Character]
    ) -> Character? {
        guard index > characters.startIndex else { return nil }
        for candidate in stride(from: index - 1, through: characters.startIndex, by: -1) {
            if !isHorizontalWhitespace(characters[candidate]) {
                return characters[candidate]
            }
        }
        return nil
    }

    private static func nextVisibleCharacter(
        after index: Int,
        in characters: [Character]
    ) -> Character? {
        guard index < characters.index(before: characters.endIndex) else { return nil }
        for candidate in characters.index(after: index)..<characters.endIndex {
            if !isHorizontalWhitespace(characters[candidate]) {
                return characters[candidate]
            }
        }
        return nil
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t" || character == "\u{00A0}" || character == "\u{3000}"
    }

    private static func isIdeographic(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic
        }
    }

    private static func isASCIILetterOrDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.isASCII else {
            return false
        }
        return (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
            || (48...57).contains(scalar.value)
    }
}
