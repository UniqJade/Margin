import Foundation

public protocol TranslationProvider: Sendable {
    var displayName: String { get }
    func translate(_ request: LookupRequest) async throws -> LookupResult
}

public enum ProviderLookupPolicy: String, Codable, Equatable, Sendable {
    case standard
    case naturalOnly
}

public enum TranslationProgress: String, Codable, Equatable, Sendable {
    case readingContext
    case refiningNaturalTranslation
}

public enum TranslationResponseIssue: String, Codable, Equatable, Sendable {
    case emptyResponse
    case truncatedResponse
    case malformedEnvelope
    case malformedJSON
    case invalidStructure
    case invalidAlignment
    case invalidLanguage

    public var title: String {
        switch self {
        case .emptyResponse:
            String(localized: "The translation service returned an empty result.", bundle: .module)
        case .truncatedResponse:
            String(localized: "The translation result was incomplete.", bundle: .module)
        case .malformedEnvelope, .malformedJSON, .invalidStructure:
            String(localized: "The translation result used an unreadable format.", bundle: .module)
        case .invalidAlignment:
            String(localized: "The semantic alignment was incomplete.", bundle: .module)
        case .invalidLanguage:
            String(localized: "The translation result did not contain usable Chinese text.", bundle: .module)
        }
    }
}

public struct TranslationResponseError: Error, Equatable, LocalizedError, Sendable {
    public let issue: TranslationResponseIssue
    public let stage: String
    public let detail: String?

    public init(issue: TranslationResponseIssue, stage: String, detail: String? = nil) {
        self.issue = issue
        self.stage = stage
        self.detail = detail
    }

    public var errorDescription: String? { issue.title }

    public var technicalDescription: String {
        if let detail, !detail.isEmpty {
            return "Stage: \(stage) · \(detail)"
        }
        return "Stage: \(stage) · Issue: \(issue.rawValue)"
    }
}

public struct TranslationDiagnostic: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case success
        case failure
    }

    public let timestamp: Date
    public let stage: String
    public let outcome: Outcome
    public let statusCode: Int?
    public let finishReason: String?
    public let issue: TranslationResponseIssue?
    public let detail: String?
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        timestamp: Date = Date(),
        stage: String,
        outcome: Outcome,
        statusCode: Int? = nil,
        finishReason: String? = nil,
        issue: TranslationResponseIssue? = nil,
        detail: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.timestamp = timestamp
        self.stage = stage
        self.outcome = outcome
        self.statusCode = statusCode
        self.finishReason = finishReason
        self.issue = issue
        self.detail = detail
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum TranslationProviderEvent: Equatable, Sendable {
    case progress(TranslationProgress)
    case diagnostic(TranslationDiagnostic)
}

public enum TranslationProviderError: Error, Equatable, LocalizedError, Sendable {
    case invalidCredentials
    case rateLimited
    case serviceUnavailable
    case networkUnavailable
    case invalidResponse
    case cancelled
    case misconfigured

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            String(localized: "The API key was rejected. Check it in Settings.", bundle: .module)
        case .rateLimited:
            String(localized: "The translation service is busy. Try again shortly.", bundle: .module)
        case .serviceUnavailable:
            String(localized: "The translation service is temporarily unavailable.", bundle: .module)
        case .networkUnavailable:
            String(localized: "Connect to the internet and try again.", bundle: .module)
        case .invalidResponse:
            String(localized: "The translation could not be read. Try again.", bundle: .module)
        case .cancelled:
            String(localized: "The lookup was cancelled.", bundle: .module)
        case .misconfigured:
            String(localized: "Complete the translation provider settings first.", bundle: .module)
        }
    }
}
