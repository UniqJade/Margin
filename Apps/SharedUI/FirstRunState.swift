import Combine
import Foundation

@MainActor
final class FirstRunState: ObservableObject {
    static let completedDefaultsKey = "margin.first-run.completed.v1"

    @Published private(set) var isComplete: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = SharedConfiguration.defaults) {
        self.defaults = defaults

        if let storedCompletion = defaults.object(forKey: Self.completedDefaultsKey) as? Bool {
            isComplete = storedCompletion
        } else {
            let migratedCompletion = defaults.object(forKey: ProviderPreferences.endpointDefaultsKey) != nil
                && defaults.object(forKey: ProviderPreferences.modelDefaultsKey) != nil
            isComplete = migratedCompletion
            if migratedCompletion {
                defaults.set(true, forKey: Self.completedDefaultsKey)
            }
        }
    }

    func complete() {
        guard !isComplete else { return }
        isComplete = true
        defaults.set(true, forKey: Self.completedDefaultsKey)
    }

    func reopen() {
        guard isComplete else { return }
        isComplete = false
        defaults.set(false, forKey: Self.completedDefaultsKey)
    }
}
