import Foundation

/// Removes the attribution footer that Apple Books appends when copied text is shared.
///
/// The match is intentionally conservative: a recognized source marker, nonempty
/// source metadata, and a recognized copyright notice must all appear together at
/// the very end of the text.
public enum AppleBooksAttributionCleaner {
    private struct FooterPattern {
        let marker: String
        let notices: [String]
    }

    private static let patterns = [
        FooterPattern(
            marker: "摘录来自",
            notices: [
                "此内容可能受版权保护。",
                "此内容可能受版权保护.",
            ]
        ),
        FooterPattern(
            marker: "Excerpt From",
            notices: [
                "This material may be protected by copyright.",
            ]
        ),
    ]

    private static let allowedPrecedingCharacters: Set<Character> = [
        " ", "\t", "\n", "\r",
        ".", "!", "?", "。", "！", "？",
        "\"", "'", "”", "’", "」", "』",
    ]

    private static let maximumFooterLength = 500

    public static func removingFooter(from text: String) -> String {
        for pattern in patterns {
            guard let markerRange = text.range(
                of: pattern.marker,
                options: [.backwards, .literal]
            ),
            hasValidBoundary(before: markerRange.lowerBound, in: text),
            text[markerRange.lowerBound...].count <= maximumFooterLength,
            hasCompleteFooter(
                after: markerRange.upperBound,
                in: text,
                notices: pattern.notices
            ) else {
                continue
            }

            return text[..<markerRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    static func removingFooter(from result: LookupResult) -> LookupResult {
        guard case let .passage(passage) = result else { return result }

        if passage.alignmentBlocks.isEmpty {
            return .passage(PassageLookupResult(
                translation: removingFooter(from: passage.translation),
                nuanceNote: passage.nuanceNote.map(removingFooter(from:)),
                literalGloss: passage.literalGloss.map(removingFooter(from:))
            ))
        }

        let blocks = passage.alignmentBlocks.compactMap { block -> PassageAlignmentBlock? in
            let cleaned = removingFooter(from: block.translation)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return PassageAlignmentBlock(
                sourceSentenceIDs: block.sourceSentenceIDs,
                translation: cleaned
            )
        }
        return .passage(PassageLookupResult(
            alignmentBlocks: blocks,
            nuanceNote: passage.nuanceNote.map(removingFooter(from:)),
            literalGloss: passage.literalGloss.map(removingFooter(from:))
        ))
    }

    private static func hasValidBoundary(
        before markerIndex: String.Index,
        in text: String
    ) -> Bool {
        guard markerIndex != text.startIndex else { return true }
        return allowedPrecedingCharacters.contains(text[text.index(before: markerIndex)])
    }

    private static func hasCompleteFooter(
        after markerEnd: String.Index,
        in text: String,
        notices: [String]
    ) -> Bool {
        for notice in notices {
            guard let noticeRange = text.range(
                of: notice,
                options: [.backwards, .literal],
                range: markerEnd..<text.endIndex
            ) else {
                continue
            }

            let metadata = text[markerEnd..<noticeRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trailingText = text[noticeRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !metadata.isEmpty, trailingText.isEmpty {
                return true
            }
        }
        return false
    }
}
