import AppKit
import ApplePlatformSupport

@MainActor
struct SelectionCaptureClient {
    let requestAccessibilityPermissionIfNeeded: @MainActor () -> Bool
    let copySelection: @MainActor (@escaping (String?) -> Void) -> Void

    static let live = SelectionCaptureClient(
        requestAccessibilityPermissionIfNeeded: SelectedTextCapture.requestAccessibilityPermissionIfNeeded,
        copySelection: SelectedTextCapture.copySelection
    )
}

struct AppLaunchEnvironment {
    let isHostedUnitTest: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        isHostedUnitTest = environment["MARGIN_HOSTED_TEST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

struct CaptureGenerationGate {
    private var generation: UInt = 0

    mutating func begin() -> UInt {
        generation &+= 1
        return generation
    }

    mutating func invalidate() { generation &+= 1 }

    func isCurrent(_ token: UInt) -> Bool { token == generation }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    let session: LookupSession
    let launchEnvironment: AppLaunchEnvironment
    private let hostedSessionResources: HostedSessionResources?
    private let selectionCapture: SelectionCaptureClient
    private lazy var panelController = LookupPanelController { [weak self] in
        self?.captureGeneration.invalidate()
    }
    private var selectionShortcut: SelectionShortcutController?
    private var captureGeneration = CaptureGenerationGate()

    override convenience init() {
        self.init(environment: AppLaunchEnvironment())
    }

    init(
        environment: AppLaunchEnvironment,
        session suppliedSession: LookupSession? = nil,
        selectionCapture: SelectionCaptureClient = .live
    ) {
        launchEnvironment = environment
        self.selectionCapture = selectionCapture
        if let suppliedSession {
            hostedSessionResources = nil
            session = suppliedSession
        } else if environment.isHostedUnitTest {
            let resources = HostedSessionResources()
            hostedSessionResources = resources
            session = LookupSession(
                defaults: resources.defaults,
                vault: APIKeyVault(store: NoopSecretStore()),
                loadInitialHistory: false,
                storageDirectory: resources.storageDirectory
            )
        } else {
            hostedSessionResources = nil
            session = LookupSession()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !launchEnvironment.isHostedUnitTest else { return }
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
        selectionShortcut = SelectionShortcutController { [weak self] in
            self?.captureAppleBooksSelection()
        }
        showLookupPanel()
    }

    func showLookupPanel() {
        captureGeneration.invalidate()
        showLookupPanelPreservingCapture()
    }

    private func showLookupPanelPreservingCapture() {
        panelController.show(session: session)
    }

    private func captureAppleBooksSelection() {
        let captureToken = captureGeneration.begin()
        guard selectionCapture.requestAccessibilityPermissionIfNeeded() else { return }

        selectionCapture.copySelection { [weak self] selection in
            guard let self else { return }
            completeCapture(token: captureToken, selection: selection)
        }
    }

    private func completeCapture(token: UInt, selection: String?) {
        guard captureGeneration.isCurrent(token) else { return }
        showLookupPanelPreservingCapture()
        guard let selection else {
            session.presentFailure(String(localized: "Apple Books did not copy a selection. Select a word or passage, then press ⌃⌥M again."))
            return
        }
        session.lookup(selection: selection)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLookupPanel()
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        captureGeneration.invalidate()
    }

    @objc func lookupSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        captureGeneration.invalidate()
        guard let selection = pasteboard.string(forType: .string), !selection.isEmpty else {
            error.pointee = String(localized: "Apple Books did not provide selected text.") as NSString
            return
        }
        showLookupPanelPreservingCapture()
        session.lookup(selection: selection)
    }

    var isLookupPanelVisible: Bool { panelController.isVisible }

    func hideLookupPanelForTesting() { panelController.hide() }

    func beginCaptureForTesting() -> UInt { captureGeneration.begin() }
    func completeCaptureForTesting(token: UInt, selection: String?) {
        completeCapture(token: token, selection: selection)
    }
    func dismissLookupPanelForTesting() { panelController.dismiss() }
    func captureAppleBooksSelectionForTesting() { captureAppleBooksSelection() }
}

private final class HostedSessionResources {
    let defaults: UserDefaults
    let storageDirectory: URL
    private let suiteName: String

    init() {
        suiteName = "dev.example.BooksTranslator.hosted-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        storageDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MarginHostedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: storageDirectory)
    }
}

private struct NoopSecretStore: SecretStore {
    func save(_ secret: String) throws {}
    func read() throws -> String? { nil }
    func delete() throws {}
}
