import AppKit
import Combine

enum MacAppearancePolicy {
    static func appearanceName(for appearance: MarginAppearance) -> NSAppearance.Name? {
        switch appearance {
        case .system:
            nil
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }
    }

    static func appKitAppearance(for appearance: MarginAppearance) -> NSAppearance? {
        appearanceName(for: appearance).flatMap(NSAppearance.init(named:))
    }
}

@MainActor
protocol MacApplicationAppearanceApplying: AnyObject {
    var appearance: NSAppearance? { get set }
}

extension NSApplication: MacApplicationAppearanceApplying {}

@MainActor
final class MacAppearanceCoordinator {
    private var cancellable: AnyCancellable?

    init(
        session: LookupSession,
        application: any MacApplicationAppearanceApplying = NSApplication.shared
    ) {
        cancellable = session.$appearance
            .removeDuplicates()
            .sink { appearance in
                application.appearance = MacAppearancePolicy.appKitAppearance(for: appearance)
            }
    }
}
