import AVFoundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LookupActionBar: View {
    let primaryText: String
    let isSaved: Bool
    let onToggleSaved: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Divider()
            HStack(spacing: 6) {
                actionButton("Copy", systemImage: "doc.on.doc") { copy(primaryText) }
                actionButton("Speak", systemImage: "speaker.wave.2") {
                    SpeechController.shared.speak(primaryText)
                }
                actionButton(
                    isSaved ? "Unsave" : "Save",
                    systemImage: isSaved ? "bookmark.fill" : "bookmark",
                    action: onToggleSaved
                )
                .accessibilityValue(Text(savedAccessibilityValue))
                Spacer()
                actionButton("Retry", systemImage: "arrow.clockwise", action: onRetry)
            }
            .labelStyle(.iconOnly)
        }
    }

    private var savedAccessibilityValue: LocalizedStringResource {
        isSaved ? "Saved" : "Not saved"
    }

    private func actionButton(
        _ title: LocalizedStringResource,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
            .buttonStyle(.borderless)
            .help(Text(title))
            .accessibilityLabel(Text(title))
    }

    private func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

@MainActor
private final class SpeechController {
    static let shared = SpeechController()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
    }
}
