import AppKit
import SwiftUI

@MainActor
final class LookupPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
        orderOut(sender)
    }
}

enum LookupPanelPlacement {
    static func frame(near point: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSRect {
        let gap: CGFloat = 14
        let size = NSSize(
            width: min(max(panelSize.width, 0), max(visibleFrame.width, 0)),
            height: min(max(panelSize.height, 0), max(visibleFrame.height, 0))
        )
        let preferredY = point.y - size.height - gap
        let alternateY = point.y + gap
        let candidateY = preferredY >= visibleFrame.minY ? preferredY : alternateY
        let maxX = visibleFrame.maxX - size.width
        let maxY = visibleFrame.maxY - size.height
        let x = min(max(point.x + gap, visibleFrame.minX), maxX)
        let y = min(max(candidateY, visibleFrame.minY), maxY)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

/// Pure, unit-tested policy for how large the lookup panel's content should be and
/// how a resize repositions the panel while keeping its top edge anchored.
enum LookupPanelSizing {
    static let preferredWidth: CGFloat = 540
    static let minimumContentHeight: CGFloat = 280
    static let maximumContentHeight: CGFloat = 620
    static let initialContentHeight: CGFloat = 360
    static let wordContentHeight: CGFloat = 620

    /// Clamps a measured content height into the panel's allowed range while never
    /// exceeding the space actually available on screen, and never returning a
    /// negative dimension.
    static func contentSize(reportedHeight: CGFloat, availableContentSize: NSSize) -> NSSize {
        let availableWidth = max(availableContentSize.width, 0)
        let availableHeight = max(availableContentSize.height, 0)

        let width = min(preferredWidth, availableWidth)
        let lowerBound = max(reportedHeight, min(minimumContentHeight, availableContentSize.height))
        let upperBound = min(maximumContentHeight, availableHeight)
        let height = max(0, min(lowerBound, upperBound))

        return NSSize(width: max(0, width), height: height)
    }

    /// Resizes to `targetFrameSize` (never larger than the visible frame) while keeping
    /// the panel's top edge fixed, then clamps the whole rectangle inside the screen.
    static func framePreservingTopEdge(
        currentFrame: NSRect,
        targetFrameSize: NSSize,
        visibleFrame: NSRect
    ) -> NSRect {
        let width = min(max(targetFrameSize.width, 0), max(visibleFrame.width, 0))
        let height = min(max(targetFrameSize.height, 0), max(visibleFrame.height, 0))

        let topEdge = currentFrame.maxY
        var originX = currentFrame.minX
        var originY = topEdge - height
        originX = min(max(originX, visibleFrame.minX), visibleFrame.maxX - width)
        originY = min(max(originY, visibleFrame.minY), visibleFrame.maxY - height)

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}

enum LookupPanelHeightUpdate: Equatable {
    case ignored
    case cached
    case resize
}

struct LookupPanelHeightState {
    private(set) var reportedHeight = LookupPanelSizing.initialContentHeight
    private(set) var hasPresentedPanel = false

    mutating func markPresented() {
        hasPresentedPanel = true
    }

    mutating func record(_ height: CGFloat, panelIsVisible: Bool) -> LookupPanelHeightUpdate {
        guard abs(reportedHeight - height) >= 1 else { return .ignored }
        guard panelIsVisible || hasPresentedPanel else { return .ignored }

        reportedHeight = height
        return panelIsVisible ? .resize : .cached
    }
}

@MainActor
final class LookupPanelController: NSObject, NSWindowDelegate {
    static let preferredContentSize = NSSize(
        width: LookupPanelSizing.preferredWidth,
        height: LookupPanelSizing.wordContentHeight
    )
    private var lookupPanel: LookupPanel?
    private let onDismiss: () -> Void
    private var heightState = LookupPanelHeightState()

    init(onDismiss: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    func panel(session: LookupSession) -> LookupPanel {
        if let lookupPanel {
            return lookupPanel
        }

        let panel = LookupPanel(
            contentRect: NSRect(origin: .zero, size: Self.preferredContentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Margin"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.contentMinSize = NSSize(
            width: LookupPanelSizing.preferredWidth,
            height: LookupPanelSizing.minimumContentHeight
        )
        panel.contentMaxSize = NSSize(
            width: LookupPanelSizing.preferredWidth,
            height: LookupPanelSizing.maximumContentHeight
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.onDismiss() }
        let rootView = MarginRootView(
            session: session,
            onDismiss: { [weak self, weak panel] in
                self?.onDismiss()
                panel?.orderOut(nil)
            },
            onPreferredHeightChange: { [weak self, weak panel] height in
                guard let self, let panel else { return }
                self.updatePreferredHeight(height, for: panel)
            }
        )
        .marginAppearance(session: session)
        panel.contentViewController = NSHostingController(rootView: rootView)
        lookupPanel = panel
        return panel
    }

    func show(session: LookupSession) {
        let panel = panel(session: session)
        let mouseLocation = NSEvent.mouseLocation

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            configure(panel: panel, near: mouseLocation, visibleFrame: screen.visibleFrame)
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            configureCentered(panel: panel, visibleFrame: screen.visibleFrame)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        heightState.markPresented()
    }

    func configure(panel: LookupPanel, near point: NSPoint, visibleFrame: NSRect) {
        let targetFrameSize = prepareSizing(panel: panel, visibleFrame: visibleFrame)
        let frame = LookupPanelPlacement.frame(
            near: point,
            panelSize: targetFrameSize,
            visibleFrame: visibleFrame
        )
        panel.setFrame(frame, display: true)
    }

    func configureCentered(panel: LookupPanel, visibleFrame: NSRect) {
        let targetFrameSize = prepareSizing(panel: panel, visibleFrame: visibleFrame)
        let origin = NSPoint(
            x: visibleFrame.midX - targetFrameSize.width / 2,
            y: visibleFrame.midY - targetFrameSize.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: targetFrameSize), display: true)
    }

    /// Establishes the panel's min/max content bounds for the current screen and returns
    /// the frame size for the initial (unmeasured) content height.
    private func prepareSizing(panel: LookupPanel, visibleFrame: NSRect) -> NSSize {
        let availableFrameRect = NSRect(
            origin: .zero,
            size: NSSize(width: max(visibleFrame.width, 0), height: max(visibleFrame.height, 0))
        )
        let availableContentSize = panel.contentRect(forFrameRect: availableFrameRect).size
        let availableWidth = max(availableContentSize.width, 0)
        let availableHeight = max(availableContentSize.height, 0)

        panel.contentMinSize = NSSize(
            width: min(LookupPanelSizing.preferredWidth, availableWidth),
            height: min(LookupPanelSizing.minimumContentHeight, availableHeight)
        )
        panel.contentMaxSize = NSSize(
            width: min(LookupPanelSizing.preferredWidth, availableWidth),
            height: min(LookupPanelSizing.maximumContentHeight, availableHeight)
        )

        let targetContentSize = LookupPanelSizing.contentSize(
            reportedHeight: heightState.reportedHeight,
            availableContentSize: availableContentSize
        )
        return panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
    }

    /// Applies a freshly measured natural content height, resizing the visible panel to
    /// fit its content while keeping the top edge anchored. Ignores sub-point changes to
    /// avoid a measure/resize feedback loop.
    private func updatePreferredHeight(_ height: CGFloat, for panel: LookupPanel) {
        guard heightState.record(height, panelIsVisible: panel.isVisible) == .resize else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let availableContentSize = panel.contentRect(forFrameRect: screen.visibleFrame).size
        let targetContentSize = LookupPanelSizing.contentSize(
            reportedHeight: height,
            availableContentSize: availableContentSize
        )
        let targetFrameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: targetContentSize)
        ).size
        let targetFrame = LookupPanelSizing.framePreservingTopEdge(
            currentFrame: panel.frame,
            targetFrameSize: targetFrameSize,
            visibleFrame: screen.visibleFrame
        )
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(targetFrame, display: true, animate: animate)
    }

    var isVisible: Bool { lookupPanel?.isVisible == true }

    func hide() { lookupPanel?.orderOut(nil) }

    func dismiss() {
        onDismiss()
        lookupPanel?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onDismiss()
        return true
    }
}
