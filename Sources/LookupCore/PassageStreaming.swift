import Foundation

public struct InProgressBlock: Equatable, Sendable {
    public let sourceSentenceIDs: [Int]
    public let text: String

    public init(sourceSentenceIDs: [Int], text: String) {
        self.sourceSentenceIDs = sourceSentenceIDs
        self.text = text
    }
}

public struct PassagePartial: Equatable, Sendable {
    public let completedBlocks: [PassageAlignmentBlock]
    public let inProgress: InProgressBlock?

    public init(
        completedBlocks: [PassageAlignmentBlock],
        inProgress: InProgressBlock?
    ) {
        self.completedBlocks = completedBlocks
        self.inProgress = inProgress
    }

    public var prose: String {
        completedBlocks.map(\.translation).joined() + (inProgress?.text ?? "")
    }
}

public enum PassageStreamChunk: Sendable {
    case partial(PassagePartial)
    case finished(LookupResult)
}

public enum LookupStreamEvent: Sendable {
    case partial(PassagePartial)
    case fallback
    case completed(LookupOutcome)
}
