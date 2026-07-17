import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ActionViewController: UIViewController {
    private let session = LookupSession()
    private var hostingController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ActionExtensionRootView(session: session) { [weak self] in self?.done() }
            .marginAppearance(session: session)
        let host = UIHostingController(rootView: root)
        hostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        loadSelection()
    }

    private func loadSelection() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            session.lookup(selection: "")
            return
        }

        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty {
                session.lookup(selection: text)
                return
            }
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] value, _ in
                    let text: String?
                    if let value = value as? String {
                        text = value
                    } else if let value = value as? NSAttributedString {
                        text = value.string
                    } else {
                        text = nil
                    }
                    Task { @MainActor in
                        guard let self else { return }
                        self.session.lookup(selection: text ?? "")
                    }
                }
                return
            }
        }
        session.lookup(selection: "")
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: extensionContext?.inputItems, completionHandler: nil)
    }
}

private struct ActionExtensionRootView: View {
    @ObservedObject var session: LookupSession
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                LookupPanelView(session: session)
                    .frame(
                        width: min(viewport.size.width, 620),
                        height: min(viewport.size.height, 720),
                        alignment: .top
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Margin")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}
