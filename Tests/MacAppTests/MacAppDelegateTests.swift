import AppKit
import LookupCore
import XCTest
@testable import Margin

@MainActor
final class MacAppDelegateTests: XCTestCase {
    func testNormalLaunchDoesNotRequestAccessibilityPermission() {
        var permissionRequestCount = 0
        let selectionCapture = SelectionCaptureClient(
            requestAccessibilityPermissionIfNeeded: {
                permissionRequestCount += 1
                return false
            },
            copySelection: { _ in XCTFail("Launch must not try to copy a selection") }
        )
        let delegate = MacAppDelegate(
            environment: AppLaunchEnvironment(environment: [:]),
            session: makeIsolatedSession(),
            selectionCapture: selectionCapture
        )
        defer { delegate.hideLookupPanelForTesting() }

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApplication.shared)
        )

        XCTAssertEqual(permissionRequestCount, 0)
    }

    func testDeniedShortcutRequestsSystemPermissionOnceWithoutCopyingSelection() {
        var permissionRequestCount = 0
        var copyRequestCount = 0
        let selectionCapture = SelectionCaptureClient(
            requestAccessibilityPermissionIfNeeded: {
                permissionRequestCount += 1
                return false
            },
            copySelection: { _ in copyRequestCount += 1 }
        )
        let delegate = MacAppDelegate(
            environment: AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"]),
            session: makeIsolatedSession(),
            selectionCapture: selectionCapture
        )

        delegate.captureAppleBooksSelectionForTesting()

        XCTAssertEqual(permissionRequestCount, 1)
        XCTAssertEqual(copyRequestCount, 0)
        XCTAssertNil(NSApplication.shared.modalWindow)
    }

    func testObjectiveCNoArgumentInitializerCreatesIsolatedHostedSession() {
        let selector = #selector(NSObject.init)
        XCTAssertNotNil(class_getInstanceMethod(MacAppDelegate.self, selector))

        let delegate = MacAppDelegate.init()

        XCTAssertTrue(delegate.launchEnvironment.isHostedUnitTest)
        XCTAssertEqual(delegate.session.preferences.endpoint, ProviderPreferences.defaultEndpoint)
        XCTAssertEqual(delegate.session.preferences.model, "deepseek-v4-flash")
    }

    func testHostedTestDetectionIsDeterministic() {
        XCTAssertTrue(AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"]).isHostedUnitTest)
        XCTAssertTrue(AppLaunchEnvironment(environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"]).isHostedUnitTest)
        XCTAssertFalse(AppLaunchEnvironment(environment: [:]).isHostedUnitTest)
    }

    func testCaptureGenerationOnlyAcceptsLatestTokenAndInvalidation() {
        var gate = CaptureGenerationGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))

        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(second))
    }

    func testReopenAlwaysShowsLookupPanelWhenAnotherWindowIsVisible() {
        let delegate = MacAppDelegate(
            environment: AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"])
        )
        defer { delegate.hideLookupPanelForTesting() }

        _ = delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: true)

        XCTAssertTrue(delegate.isLookupPanelVisible)
    }

    func testHostedDelegateConstructsSessionWithIsolatedDefaultPreferences() throws {
        let unrelatedSuiteName = "MacAppDelegateTests.\(UUID().uuidString)"
        let unrelatedDefaults = try XCTUnwrap(UserDefaults(suiteName: unrelatedSuiteName))
        unrelatedDefaults.set("https://unrelated.example/v1", forKey: "provider.endpoint")
        unrelatedDefaults.set("unrelated-model", forKey: "provider.model")
        addTeardownBlock { unrelatedDefaults.removePersistentDomain(forName: unrelatedSuiteName) }

        let delegate = MacAppDelegate(environment: AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"]))

        XCTAssertEqual(delegate.session.preferences.endpoint, ProviderPreferences.defaultEndpoint)
        XCTAssertEqual(delegate.session.preferences.model, "deepseek-v4-flash")
        XCTAssertTrue(delegate.launchEnvironment.isHostedUnitTest)
    }

    func testManualShowInvalidatesDelayedCaptureCompletion() async throws {
        let operation = CaptureRecordingLookupOperation()
        let session = makeIsolatedSession(lookupOperation: { selection in
            try await operation.perform(selection)
        })
        let delegate = MacAppDelegate(
            environment: AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"]),
            session: session
        )
        defer { delegate.hideLookupPanelForTesting() }

        let token = delegate.beginCaptureForTesting()
        delegate.showLookupPanel()
        delegate.completeCaptureForTesting(token: token, selection: "stale")
        await Task.yield()

        let selections = await operation.selections
        XCTAssertEqual(selections, [])
        XCTAssertEqual(session.selection, "")
        XCTAssertEqual(session.phase, .idle)
    }

    func testPanelDismissInvalidatesDelayedCaptureCompletion() async throws {
        let operation = CaptureRecordingLookupOperation()
        let session = makeIsolatedSession(lookupOperation: { selection in
            try await operation.perform(selection)
        })
        let delegate = MacAppDelegate(
            environment: AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"]),
            session: session
        )

        let token = delegate.beginCaptureForTesting()
        delegate.dismissLookupPanelForTesting()
        delegate.completeCaptureForTesting(token: token, selection: "stale")
        await Task.yield()

        let selections = await operation.selections
        XCTAssertEqual(selections, [])
    }

    func testResigningActiveInvalidatesDelayedCaptureWithoutStartingLookup() async throws {
        let operation = CaptureRecordingLookupOperation()
        let session = makeIsolatedSession(lookupOperation: { selection in
            try await operation.perform(selection)
        })
        let delegate = MacAppDelegate(
            environment: AppLaunchEnvironment(environment: ["MARGIN_HOSTED_TEST": "1"]),
            session: session
        )
        defer { delegate.hideLookupPanelForTesting() }

        let token = delegate.beginCaptureForTesting()
        delegate.applicationDidResignActive(
            Notification(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        )
        delegate.completeCaptureForTesting(token: token, selection: "stale")
        await Task.yield()

        let selections = await operation.selections
        XCTAssertEqual(selections, [])
        XCTAssertEqual(session.selection, "")
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(delegate.isLookupPanelVisible)
    }
}

private actor CaptureRecordingLookupOperation {
    private(set) var selections: [String] = []

    func perform(_ selection: String) async throws -> LookupOutcome {
        selections.append(selection)
        throw CancellationError()
    }
}
