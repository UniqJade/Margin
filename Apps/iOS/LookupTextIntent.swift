import AppIntents
import LookupCore

struct LookupTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Look Up English Text"
    static let description = IntentDescription("Translate an English word or passage into natural Simplified Chinese.")
    static let openAppWhenRun = false

    @Parameter(title: "Selected text")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await LookupRuntime.lookup(selection: text)
        return .result(dialog: IntentDialog(stringLiteral: summary(outcome.result)))
    }

    private func summary(_ result: LookupResult) -> String {
        switch result {
        case let .word(word):
            word.partsOfSpeech
                .flatMap(\.senses)
                .map(\.chineseDefinition)
                .joined(separator: "；")
        case let .passage(passage):
            passage.translation
        }
    }
}

struct MarginShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LookupTextIntent(),
            phrases: ["Look up text with \(.applicationName)"],
            shortTitle: "Look Up Text",
            systemImageName: "text.magnifyingglass"
        )
    }
}
