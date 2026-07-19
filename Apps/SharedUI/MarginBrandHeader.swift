import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MarginBrandHeader: View {
    let onDismiss: (() -> Void)?
    let closeAccessibilityLabel: LocalizedStringResource

    init(
        onDismiss: (() -> Void)?,
        closeAccessibilityLabel: LocalizedStringResource = "Close"
    ) {
        self.onDismiss = onDismiss
        self.closeAccessibilityLabel = closeAccessibilityLabel
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            brandIcon
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("MARGIN")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(2.4)
                Text("Context without leaving the page")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel(Text(closeAccessibilityLabel))
            }
        }
    }

    @ViewBuilder
    private var brandIcon: some View {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        #else
        Image(systemName: "text.book.closed")
            .resizable()
            .scaledToFit()
            .foregroundStyle(MarginTheme.accentForeground)
            .padding(5)
        #endif
    }
}
