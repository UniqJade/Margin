import SwiftUI

@main
struct MarginIOSApp: App {
    @StateObject private var session = LookupSession()

    var body: some Scene {
        WindowGroup {
            IOSRootView(session: session)
                .marginAppearance(session: session)
        }
    }
}

private struct IOSRootView: View {
    @ObservedObject var session: LookupSession
    @ObservedObject private var firstRunState: FirstRunState

    init(session: LookupSession) {
        self.session = session
        firstRunState = session.firstRunState
    }

    @ViewBuilder
    var body: some View {
        if !firstRunState.isComplete {
            FirstRunSetupView(state: firstRunState) { apiKey in
                try await session.saveAndTestDeepSeek(apiKey: apiKey)
            }
        } else {
            TabView {
                NavigationStack {
                    LookupPanelView(session: session)
                        .navigationTitle("Margin")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label("Lookup", systemImage: "text.magnifyingglass") }

                HistoryView(session: session)
                    .tabItem { Label("Saved", systemImage: "bookmark") }

                NavigationStack {
                    SettingsView(session: session)
                        .navigationTitle("Settings")
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
