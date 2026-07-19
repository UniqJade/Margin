import SwiftUI

#if os(macOS)
import AppKit
import CoreText
#endif

@MainActor
enum ChineseReadingTypography {
    #if os(macOS)
    static let macFont: NSFont = {
        let referenceFont = NSFont.preferredFont(forTextStyle: .title3)
        let baseFont = NSFont(
            name: "PingFang SC",
            size: referenceFont.pointSize
        ) ?? referenceFont
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: Int(kTextSpacingType),
                    NSFontDescriptor.FeatureKey.selectorIdentifier: Int(kProportionalTextSelector),
                ],
            ],
        ])
        return NSFont(
            descriptor: descriptor,
            size: referenceFont.pointSize
        ) ?? baseFont
    }()

    static let passageFont = Font(macFont)
    #else
    static let passageFont = Font.system(.title3, design: .serif)
    #endif
}

private struct ChinesePassageTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(ChineseReadingTypography.passageFont)
            .multilineTextAlignment(.leading)
    }
}

extension View {
    func chinesePassageTypography() -> some View {
        modifier(ChinesePassageTypographyModifier())
    }
}
