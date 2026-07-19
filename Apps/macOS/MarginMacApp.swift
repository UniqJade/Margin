import AppKit
import SwiftUI

@main
struct MarginMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Margin", systemImage: "text.book.closed") {
            MenuBarContent(session: appDelegate.session) {
                appDelegate.showLookupPanel()
            }
            .marginAppearance(session: appDelegate.session)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(session: appDelegate.session)
                .marginAppearance(session: appDelegate.session)
                .frame(width: 520, height: 440)
        }

        Window("Lookup history", id: "history") {
            HistoryView(session: appDelegate.session)
                .marginAppearance(session: appDelegate.session)
        }
        .defaultSize(width: 520, height: 520)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var session: LookupSession
    let showLookup: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Look up text…", systemImage: "text.magnifyingglass", action: showLookup)
            .keyboardShortcut("l")
        Button("History", systemImage: "clock.arrow.circlepath") {
            openWindow(id: "history")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        Divider()
        Text("In Apple Books: select text, then press ⌃⌥M.")
            .font(.caption)
        Divider()
        Button("Quit Margin") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
