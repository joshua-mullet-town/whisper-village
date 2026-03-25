import Foundation
import AppKit

/// Simple in-memory last transcription cache (no SwiftData)
class LastTranscriptionService: ObservableObject {
    static let shared = LastTranscriptionService()

    @Published private(set) var lastText: String?

    private init() {}

    func store(_ text: String) {
        lastText = LastTranscriptionService.cleanTranscription(text)
    }

    /// Clean up common transcription artifacts before storing
    static func cleanTranscription(_ text: String) -> String {
        var result = text

        // Remove filler words: "uh" and "um" (case-insensitive, word boundaries)
        // Handles: "uh", "Uh", "um", "Um" — only as standalone words
        result = result.replacingOccurrences(
            of: "\\b[Uu][hm]\\b[,.]?\\s*",
            with: "",
            options: .regularExpression
        )

        // Remove repeated "I'm" (e.g., "I'm I'm I'm" → "I'm")
        result = result.replacingOccurrences(
            of: "\\b(I'm\\s+){2,}",
            with: "I'm ",
            options: .regularExpression
        )

        // Remove repeated "a little bit" phrases (can repeat many times)
        result = result.replacingOccurrences(
            of: "(a little bit[,.]?\\s*){2,}",
            with: "a little bit ",
            options: [.regularExpression, .caseInsensitive]
        )

        // Clean up extra whitespace left behind
        result = result.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespaces)
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
