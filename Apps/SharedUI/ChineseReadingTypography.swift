import SwiftUI

#if os(macOS)
import AppKit
#endif

@MainActor
enum ChineseReadingTypography {
    #if os(macOS)
    static let macFont: NSFont = {
        let referenceFont = NSFont.preferredFont(forTextStyle: .title3)
        return NSFont(
            name: "Songti SC",
            size: referenceFont.pointSize
        ) ?? referenceFont
    }()

    private static let compressedCommaKerning = -(macFont.pointSize * 0.3)

    static func kerning(for character: Character) -> CGFloat {
        character == "，" ? compressedCommaKerning : 0
    }

    static func passageText(_ text: String) -> Text {
        text.reduce(Text("")) { result, character in
            result + Text(String(character)).kerning(kerning(for: character))
        }
        .font(Font(macFont))
    }
    #else
    static func passageText(_ text: String) -> Text {
        Text(text)
            .font(.system(.title3, design: .serif))
    }
    #endif
}
