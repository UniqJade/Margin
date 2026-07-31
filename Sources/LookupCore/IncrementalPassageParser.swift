import Foundation

public struct IncrementalPassageParser: Sendable {
    public private(set) var snapshot = PassagePartial(
        completedBlocks: [],
        inProgress: nil
    )
    public private(set) var isDegraded = false

    private var buffer = ""

    public init() {}

    public mutating func append(_ text: String) {
        buffer.append(text)
        guard !isDegraded else { return }

        switch Self.scan(buffer) {
        case let .snapshot(next):
            snapshot = next
        case .waiting:
            break
        case .malformed:
            isDegraded = true
        }
    }

    private enum ScanResult {
        case snapshot(PassagePartial)
        case waiting
        case malformed
    }

    private enum ParseResult<Value> {
        case value(Value, String.Index)
        case incomplete
        case malformed
    }

    private struct ParsedString {
        let value: String
        let isComplete: Bool
    }

    private static func scan(_ source: String) -> ScanResult {
        guard let keyRange = source.range(of: #""alignment_blocks""#) else {
            return .waiting
        }

        var index = skipWhitespace(in: source, from: keyRange.upperBound)
        guard index < source.endIndex else { return .waiting }
        guard source[index] == ":" else { return .malformed }
        index = skipWhitespace(in: source, from: source.index(after: index))
        guard index < source.endIndex else { return .waiting }
        guard source[index] == "[" else { return .malformed }
        index = source.index(after: index)

        var completedBlocks: [PassageAlignmentBlock] = []
        var expectsBlock = true

        while true {
            index = skipWhitespace(in: source, from: index)
            guard index < source.endIndex else {
                return .snapshot(PassagePartial(
                    completedBlocks: completedBlocks,
                    inProgress: nil
                ))
            }

            if expectsBlock {
                if source[index] == "]" {
                    return .snapshot(PassagePartial(
                        completedBlocks: completedBlocks,
                        inProgress: nil
                    ))
                }
                guard source[index] == "{" else { return .malformed }

                switch parseBlock(in: source, from: index) {
                case let .value((block, isComplete), next):
                    if isComplete {
                        completedBlocks.append(PassageAlignmentBlock(
                            sourceSentenceIDs: block.sourceSentenceIDs,
                            translation: block.text
                        ))
                        index = next
                        expectsBlock = false
                    } else {
                        return .snapshot(PassagePartial(
                            completedBlocks: completedBlocks,
                            inProgress: block
                        ))
                    }
                case .incomplete:
                    return .snapshot(PassagePartial(
                        completedBlocks: completedBlocks,
                        inProgress: nil
                    ))
                case .malformed:
                    return .malformed
                }
            } else {
                switch source[index] {
                case ",":
                    index = source.index(after: index)
                    expectsBlock = true
                case "]":
                    return .snapshot(PassagePartial(
                        completedBlocks: completedBlocks,
                        inProgress: nil
                    ))
                default:
                    return .malformed
                }
            }
        }
    }

    private static func parseBlock(
        in source: String,
        from start: String.Index
    ) -> ParseResult<(InProgressBlock, Bool)> {
        var index = source.index(after: start)
        index = skipWhitespace(in: source, from: index)

        switch parseJSONString(in: source, from: index) {
        case let .value(parsed, next):
            guard parsed.isComplete else { return .incomplete }
            guard parsed.value == "source_sentence_ids" else { return .malformed }
            index = next
        case .incomplete:
            return .incomplete
        case .malformed:
            return .malformed
        }

        index = skipWhitespace(in: source, from: index)
        guard index < source.endIndex else { return .incomplete }
        guard source[index] == ":" else { return .malformed }
        index = skipWhitespace(in: source, from: source.index(after: index))

        let sentenceIDs: [Int]
        switch parseIntegerArray(in: source, from: index) {
        case let .value(ids, next):
            sentenceIDs = ids
            index = next
        case .incomplete:
            return .incomplete
        case .malformed:
            return .malformed
        }

        index = skipWhitespace(in: source, from: index)
        guard index < source.endIndex else { return .incomplete }
        guard source[index] == "," else { return .malformed }
        index = skipWhitespace(in: source, from: source.index(after: index))

        switch parseJSONString(in: source, from: index) {
        case let .value(parsed, next):
            guard parsed.isComplete else { return .incomplete }
            guard parsed.value == "translation" else { return .malformed }
            index = next
        case .incomplete:
            return .incomplete
        case .malformed:
            return .malformed
        }

        index = skipWhitespace(in: source, from: index)
        guard index < source.endIndex else { return .incomplete }
        guard source[index] == ":" else { return .malformed }
        index = skipWhitespace(in: source, from: source.index(after: index))

        switch parseJSONString(in: source, from: index) {
        case let .value(parsed, next):
            let block = InProgressBlock(
                sourceSentenceIDs: sentenceIDs,
                text: parsed.value
            )
            guard parsed.isComplete else {
                return .value((block, false), next)
            }
            index = skipWhitespace(in: source, from: next)
            guard index < source.endIndex else {
                return .value((block, false), source.endIndex)
            }
            guard source[index] == "}" else { return .malformed }
            return .value((block, true), source.index(after: index))
        case .incomplete:
            return .incomplete
        case .malformed:
            return .malformed
        }
    }

    private static func parseIntegerArray(
        in source: String,
        from start: String.Index
    ) -> ParseResult<[Int]> {
        guard start < source.endIndex else { return .incomplete }
        guard source[start] == "[" else { return .malformed }
        var index = source.index(after: start)
        var values: [Int] = []
        var expectsValue = true

        while true {
            index = skipWhitespace(in: source, from: index)
            guard index < source.endIndex else { return .incomplete }

            if expectsValue {
                if source[index] == "]" {
                    return values.isEmpty
                        ? .malformed
                        : .value(values, source.index(after: index))
                }
                guard source[index].isNumber else { return .malformed }
                let numberStart = index
                while index < source.endIndex, source[index].isNumber {
                    index = source.index(after: index)
                }
                guard let value = Int(source[numberStart..<index]), value > 0 else {
                    return .malformed
                }
                values.append(value)
                expectsValue = false
            } else {
                switch source[index] {
                case ",":
                    index = source.index(after: index)
                    expectsValue = true
                case "]":
                    return .value(values, source.index(after: index))
                default:
                    return .malformed
                }
            }
        }
    }

    private static func parseJSONString(
        in source: String,
        from start: String.Index
    ) -> ParseResult<ParsedString> {
        guard start < source.endIndex else { return .incomplete }
        guard source[start] == "\"" else { return .malformed }

        var index = source.index(after: start)
        var decoded = ""

        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                return .value(
                    ParsedString(value: decoded, isComplete: true),
                    source.index(after: index)
                )
            }
            if character == "\\" {
                switch parseEscape(in: source, from: index) {
                case let .value(value, next):
                    decoded.append(value)
                    index = next
                    continue
                case .incomplete:
                    return .value(
                        ParsedString(value: decoded, isComplete: false),
                        source.endIndex
                    )
                case .malformed:
                    return .malformed
                }
            }
            if character.unicodeScalars.contains(where: { $0.value < 0x20 }) {
                return .malformed
            }
            decoded.append(character)
            index = source.index(after: index)
        }

        return .value(
            ParsedString(value: decoded, isComplete: false),
            source.endIndex
        )
    }

    private static func parseEscape(
        in source: String,
        from slash: String.Index
    ) -> ParseResult<Character> {
        let escapeIndex = source.index(after: slash)
        guard escapeIndex < source.endIndex else { return .incomplete }

        let simple: [Character: Character] = [
            "\"": "\"",
            "\\": "\\",
            "/": "/",
            "b": "\u{8}",
            "f": "\u{c}",
            "n": "\n",
            "r": "\r",
            "t": "\t",
        ]
        if let value = simple[source[escapeIndex]] {
            return .value(value, source.index(after: escapeIndex))
        }
        guard source[escapeIndex] == "u" else { return .malformed }

        switch parseHexQuad(in: source, afterU: escapeIndex) {
        case let .value(first, next):
            if (0xD800...0xDBFF).contains(first) {
                guard next < source.endIndex else { return .incomplete }
                guard source[next] == "\\" else { return .malformed }
                let secondU = source.index(after: next)
                guard secondU < source.endIndex else { return .incomplete }
                guard source[secondU] == "u" else { return .malformed }

                switch parseHexQuad(in: source, afterU: secondU) {
                case let .value(second, end):
                    guard (0xDC00...0xDFFF).contains(second) else {
                        return .malformed
                    }
                    let scalarValue = 0x10000
                        + ((first - 0xD800) << 10)
                        + (second - 0xDC00)
                    guard let scalar = Unicode.Scalar(scalarValue) else {
                        return .malformed
                    }
                    return .value(Character(String(scalar)), end)
                case .incomplete:
                    return .incomplete
                case .malformed:
                    return .malformed
                }
            }
            guard !(0xDC00...0xDFFF).contains(first),
                  let scalar = Unicode.Scalar(first) else {
                return .malformed
            }
            return .value(Character(String(scalar)), next)
        case .incomplete:
            return .incomplete
        case .malformed:
            return .malformed
        }
    }

    private static func parseHexQuad(
        in source: String,
        afterU uIndex: String.Index
    ) -> ParseResult<UInt32> {
        var index = source.index(after: uIndex)
        var digits = ""
        for _ in 0..<4 {
            guard index < source.endIndex else { return .incomplete }
            let character = source[index]
            guard character.isHexDigit else { return .malformed }
            digits.append(character)
            index = source.index(after: index)
        }
        guard let value = UInt32(digits, radix: 16) else { return .malformed }
        return .value(value, index)
    }

    private static func skipWhitespace(
        in source: String,
        from start: String.Index
    ) -> String.Index {
        var index = start
        while index < source.endIndex, source[index].isWhitespace {
            index = source.index(after: index)
        }
        return index
    }
}
