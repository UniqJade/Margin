import AppKit
import XCTest
@testable import Margin

@MainActor
final class LookupPanelTests: XCTestCase {
    func testHiddenMeasurementBeforeFirstPresentationKeepsInitialHeight() {
        var state = LookupPanelHeightState()

        let update = state.record(430, panelIsVisible: false)

        XCTAssertEqual(update, .ignored)
        XCTAssertEqual(state.reportedHeight, LookupPanelSizing.initialContentHeight)
    }

    func testVisibleMeasurementCachesHeightAndRequestsResize() {
        var state = LookupPanelHeightState()

        let update = state.record(430, panelIsVisible: true)

        XCTAssertEqual(update, .resize)
        XCTAssertEqual(state.reportedHeight, 430)
    }

    func testHiddenMeasurementAfterPresentationIsCachedWithoutResize() {
        var state = LookupPanelHeightState()
        state.markPresented()

        let update = state.record(470, panelIsVisible: false)

        XCTAssertEqual(update, .cached)
        XCTAssertEqual(state.reportedHeight, 470)
    }

    func testCachedHiddenMeasurementSizesNextPresentation() {
        var state = LookupPanelHeightState()
        state.markPresented()
        _ = state.record(470, panelIsVisible: false)

        let size = LookupPanelSizing.contentSize(
            reportedHeight: state.reportedHeight,
            availableContentSize: NSSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(size, NSSize(width: 540, height: 470))
    }

    func testSizingClampsShortReportedHeightToMinimum() {
        let size = LookupPanelSizing.contentSize(
            reportedHeight: 180,
            availableContentSize: NSSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(size, NSSize(width: 540, height: 280))
    }

    func testSizingUsesNaturalReportedHeightWithinLimits() {
        let size = LookupPanelSizing.contentSize(
            reportedHeight: 430,
            availableContentSize: NSSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(size, NSSize(width: 540, height: 430))
    }

    func testSizingCapsLongReportedHeightAtMaximum() {
        let size = LookupPanelSizing.contentSize(
            reportedHeight: 900,
            availableContentSize: NSSize(width: 1_000, height: 800)
        )

        XCTAssertEqual(size, NSSize(width: 540, height: 620))
    }

    func testSizingShrinksBothDimensionsToAvailableContentSize() {
        let size = LookupPanelSizing.contentSize(
            reportedHeight: 620,
            availableContentSize: NSSize(width: 400, height: 300)
        )

        XCTAssertEqual(size, NSSize(width: 400, height: 300))
    }

    func testSizingNeverReturnsNegativeDimensions() {
        let size = LookupPanelSizing.contentSize(
            reportedHeight: -100,
            availableContentSize: NSSize(width: -400, height: -300)
        )

        XCTAssertEqual(size, .zero)
    }

    func testResizingFramePreservesTopEdgeAndContainsResult() {
        let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let current = NSRect(x: 400, y: 140, width: 540, height: 620)

        let resized = LookupPanelSizing.framePreservingTopEdge(
            currentFrame: current,
            targetFrameSize: NSSize(width: 540, height: 360),
            visibleFrame: visible
        )

        XCTAssertEqual(resized.maxY, current.maxY)
        XCTAssertTrue(visible.contains(resized))
    }

    func testResizingFrameClampsInsideVisibleFrameWithNegativeOrigin() {
        let visible = NSRect(x: -1_200, y: 100, width: 400, height: 300)
        let current = NSRect(x: -1_300, y: 350, width: 540, height: 620)

        let resized = LookupPanelSizing.framePreservingTopEdge(
            currentFrame: current,
            targetFrameSize: NSSize(width: 540, height: 620),
            visibleFrame: visible
        )

        XCTAssertEqual(resized, visible)
    }

    func testWordContentHeightUsesFixedMaximumPolicy() {
        XCTAssertEqual(LookupPanelSizing.wordContentHeight, 620)
        XCTAssertEqual(
            LookupPanelSizing.wordContentHeight,
            LookupPanelSizing.maximumContentHeight
        )
        XCTAssertEqual(
            LookupPanelController.preferredContentSize,
            NSSize(width: LookupPanelSizing.preferredWidth, height: LookupPanelSizing.wordContentHeight)
        )
    }

    func testControllerReusesOnePanelInstance() {
        let controller = LookupPanelController()
        let session = makeIsolatedSession()

        let panel = controller.panel(session: session)
        defer { panel.orderOut(nil) }

        XCTAssertTrue(panel === controller.panel(session: session))
    }

    func testFrameStaysInsideVisibleScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let frame = LookupPanelPlacement.frame(
            near: NSPoint(x: 1_430, y: 20),
            panelSize: NSSize(width: 540, height: 620),
            visibleFrame: visible
        )

        XCTAssertTrue(visible.contains(frame))
    }

    func testPanelHidesOnDeactivateAndEscape() {
        let panel = LookupPanelController().panel(session: makeIsolatedSession())
        defer { panel.orderOut(nil) }

        XCTAssertTrue(panel.hidesOnDeactivate)
        panel.orderFront(nil)
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
    }

    func testFrameHandlesEveryScreenEdgeWithNonzeroOrigin() {
        let visible = NSRect(x: -1_200, y: 100, width: 1_200, height: 800)
        let points = [
            NSPoint(x: visible.minX, y: visible.minY),
            NSPoint(x: visible.maxX, y: visible.minY),
            NSPoint(x: visible.minX, y: visible.maxY),
            NSPoint(x: visible.maxX, y: visible.maxY),
        ]

        for point in points {
            let frame = LookupPanelPlacement.frame(
                near: point,
                panelSize: NSSize(width: 540, height: 620),
                visibleFrame: visible
            )
            XCTAssertTrue(visible.contains(frame), "Expected \(frame) to fit inside \(visible) near \(point)")
        }
    }

    func testFrameShrinksPanelToSmallerVisibleScreen() {
        let visible = NSRect(x: 300, y: -200, width: 400, height: 300)

        let frame = LookupPanelPlacement.frame(
            near: NSPoint(x: 500, y: -50),
            panelSize: NSSize(width: 540, height: 620),
            visibleFrame: visible
        )

        XCTAssertEqual(frame, visible)
    }

    func testControllerRestoresPreferredContentSizeAfterSmallScreen() {
        let controller = LookupPanelController()
        let panel = controller.panel(session: makeIsolatedSession())
        defer { panel.orderOut(nil) }
        let smallVisibleFrame = NSRect(x: 300, y: -200, width: 400, height: 260)
        let largeVisibleFrame = NSRect(x: -100, y: 80, width: 1_440, height: 900)

        controller.configure(panel: panel, near: smallVisibleFrame.center, visibleFrame: smallVisibleFrame)
        XCTAssertLessThan(panel.contentMinSize.width, LookupPanelController.preferredContentSize.width)
        XCTAssertLessThan(panel.contentMinSize.height, LookupPanelSizing.minimumContentHeight)

        controller.configure(panel: panel, near: largeVisibleFrame.center, visibleFrame: largeVisibleFrame)

        XCTAssertEqual(panel.contentView!.frame.size.width, LookupPanelController.preferredContentSize.width, accuracy: 0.5)
        XCTAssertEqual(panel.contentView!.frame.size.height, LookupPanelSizing.initialContentHeight, accuracy: 0.5)
        XCTAssertEqual(
            panel.contentMinSize,
            NSSize(width: LookupPanelSizing.preferredWidth, height: LookupPanelSizing.minimumContentHeight)
        )
        XCTAssertEqual(
            panel.contentMaxSize,
            NSSize(width: LookupPanelSizing.preferredWidth, height: LookupPanelSizing.maximumContentHeight)
        )
        XCTAssertTrue(largeVisibleFrame.contains(panel.frame))
    }

    func testCenteredConfigurationCentersPreferredFrameInVisibleFrame() {
        let controller = LookupPanelController()
        let panel = controller.panel(session: makeIsolatedSession())
        defer { panel.orderOut(nil) }
        let visibleFrame = NSRect(x: -1_200, y: 100, width: 1_440, height: 900)

        controller.configureCentered(panel: panel, visibleFrame: visibleFrame)

        XCTAssertEqual(panel.frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.midY, visibleFrame.midY, accuracy: 0.5)
        XCTAssertEqual(panel.contentView!.frame.size.height, LookupPanelSizing.initialContentHeight, accuracy: 0.5)
        XCTAssertEqual(
            panel.contentMinSize,
            NSSize(width: LookupPanelSizing.preferredWidth, height: LookupPanelSizing.minimumContentHeight)
        )
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
