import SwiftUI

extension View {
    /// Reports the natural (content-driven) height of a view whenever it changes.
    ///
    /// Used by the macOS lookup panel to size itself to its content. The height is
    /// rounded up so a fractional layout never leaves a hairline of clipped content.
    func onNaturalHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { geometry in
            ceil(geometry.size.height)
        } action: { height in
            guard height > 0 else { return }
            action(height)
        }
    }
}
