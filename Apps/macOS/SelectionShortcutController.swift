import AppKit
import ApplicationServices
import Carbon

private let marginHotKeySignature: OSType = 0x4D415247 // "MARG"

private func marginHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<SelectionShortcutController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    controller.invokeFromApplicationEventLoop()
    return noErr
}

final class SelectionShortcutController: @unchecked Sendable {
    static let displayName = "⌃⌥M"

    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            marginHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: marginHotKeySignature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    fileprivate func invokeFromApplicationEventLoop() {
        MainActor.assumeIsolated {
            action()
        }
    }
}

@MainActor
enum SelectedTextCapture {
    static func requestAccessibilityPermissionIfNeeded() -> Bool {
        guard !AXIsProcessTrusted() else { return true }
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        return false
    }

    static func copySelection(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let originalChangeCount = pasteboard.changeCount
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard pasteboard.changeCount != originalChangeCount else {
                completion(nil)
                return
            }
            let selection = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            completion(selection?.isEmpty == false ? selection : nil)
        }
    }
}
