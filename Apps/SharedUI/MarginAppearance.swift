import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarginAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultsKey = "margin.appearance"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MarginTheme {
    static let accent = adaptiveColor(
        light: (red: 0xD9, green: 0x77, blue: 0x45),
        dark: (red: 0xE7, green: 0x89, blue: 0x58)
    )
    static let accentForeground = adaptiveColor(
        light: (red: 0xB9, green: 0x54, blue: 0x25),
        dark: (red: 0xE7, green: 0x89, blue: 0x58)
    )
    static let canvas = adaptiveColor(
        light: (red: 0xFA, green: 0xF9, blue: 0xF7),
        dark: (red: 0x17, green: 0x16, blue: 0x14)
    )
    static let elevatedSurface = adaptiveColor(
        light: (red: 0xF1, green: 0xF0, blue: 0xED),
        dark: (red: 0x22, green: 0x20, blue: 0x1D)
    )

    private typealias RGB = (red: Int, green: Int, blue: Int)

    private static func adaptiveColor(light: RGB, dark: RGB) -> Color {
        #if canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat(rgb.red) / 255,
                green: CGFloat(rgb.green) / 255,
                blue: CGFloat(rgb.blue) / 255,
                alpha: 1
            )
        })
        #elseif canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(rgb.red) / 255,
                green: CGFloat(rgb.green) / 255,
                blue: CGFloat(rgb.blue) / 255,
                alpha: 1
            )
        })
        #endif
    }
}

private struct MarginAppearanceModifier: ViewModifier {
    @ObservedObject var session: LookupSession

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .tint(MarginTheme.accent)
        #else
        content
            .preferredColorScheme(session.appearance.preferredColorScheme)
            .tint(MarginTheme.accent)
        #endif
    }
}

extension View {
    func marginAppearance(session: LookupSession) -> some View {
        modifier(MarginAppearanceModifier(session: session))
    }
}
