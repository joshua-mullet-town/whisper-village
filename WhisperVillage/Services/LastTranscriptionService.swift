import Foundation
import AppKit

/// Simple in-memory last transcription cache (no SwiftData)
class LastTranscriptionService: ObservableObject {
    static let shared = LastTranscriptionService()

    @Published private(set) var lastText: String?

    private init() {}

    func store(_ text: String) {
        lastText = text
    }

    func pasteLastTranscription() {
        guard let text = lastText, !text.isEmpty else {
            Task { @MainActor in
                NotificationManager.shared.showNotification(
                    title: "No transcription available",
                    type: .error
                )
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            CursorPaster.pasteAtCursor(text + " ")
        }
    }

    func copyLastTranscription() {
        guard let text = lastText, !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
