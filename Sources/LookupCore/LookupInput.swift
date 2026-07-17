import Foundation

public enum LookupKind: String, Codable, Sendable {
    case word
    case passage
}

public enum LookupInputError: Error, Equatable, LocalizedError, Sendable {
    case emptySelection
    case selectionTooLong(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            String(localized: "Select an English word or passage first.", bundle: .module)
        case let .selectionTooLong(limit):
            String(localized: "Keep the selection under \(limit) characters.", bundle: .module)
        }
    }
}

public enum LookupInputNormalizer {
    public static let characterLimit = 2_000

    public static func normalize(_ selection: String) throws -> String {
        let normalized = selection
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            throw LookupInputError.emptySelection
        }
        guard normalized.count <= characterLimit else {
            throw LookupInputError.selectionTooLong(limit: characterLimit)
        }
        return normalized
    }
}

public enum LookupClassifier {
    private static let wordPattern = #"^[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*$"#

    public static func classify(_ normalizedText: String) -> LookupKind {
        normalizedText.range(of: wordPattern, options: .regularExpression) == nil ? .passage : .word
    }
}
