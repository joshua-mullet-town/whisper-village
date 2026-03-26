import Foundation
import AppKit

/// Simple in-memory last transcription cache (no SwiftData)
class LastTranscriptionService: ObservableObject {
    static let shared = LastTranscriptionService()

    @Published private(set) var lastText: String?

    private init() {}

    func store(_ text: String) {
        let cleaned = LastTranscriptionService.cleanTranscription(text)
        lastText = cleaned

        // Update cumulative stats
        if !cleaned.isEmpty {
            let words = cleaned.split(separator: " ").count
            let currentWords = UserDefaults.standard.integer(forKey: "CumulativeTotalWords")
            let currentCount = UserDefaults.standard.integer(forKey: "CumulativeTotalTranscriptions")
            UserDefaults.standard.set(currentWords + words, forKey: "CumulativeTotalWords")
            UserDefaults.standard.set(currentCount + 1, forKey: "CumulativeTotalTranscriptions")

            // Update today's count (resets daily)
            LastTranscriptionService.incrementTodayCount()
        }
    }

    /// Increment today's transcription count (resets when day changes)
    static func incrementTodayCount() {
        let defaults = UserDefaults.standard
        let todayStr = Self.todayString()
        let savedDate = defaults.string(forKey: "TodayCountDate") ?? ""
        if savedDate != todayStr {
            // New day — reset
            defaults.set(1, forKey: "TodayTranscriptionCount")
            defaults.set(todayStr, forKey: "TodayCountDate")
        } else {
            let current = defaults.integer(forKey: "TodayTranscriptionCount")
            defaults.set(current + 1, forKey: "TodayTranscriptionCount")
        }
    }

    /// Get today's count
    static func todayCount() -> Int {
        let defaults = UserDefaults.standard
        let savedDate = defaults.string(forKey: "TodayCountDate") ?? ""
        if savedDate != todayString() { return 0 }
        return defaults.integer(forKey: "TodayTranscriptionCount")
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Seed cumulative stats from production data (call once on first launch)
    static func seedCumulativeStatsIfNeeded() {
        let seeded = UserDefaults.standard.bool(forKey: "CumulativeStatsSeeded")
        if !seeded {
            // Seed with known production totals: 9893 transcriptions, ~1.13M words
            UserDefaults.standard.set(1125997, forKey: "CumulativeTotalWords")
            UserDefaults.standard.set(9893, forKey: "CumulativeTotalTranscriptions")
            UserDefaults.standard.set(true, forKey: "CumulativeStatsSeeded")
        }
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

        // Remove repeated standalone "I" (e.g., "I I I" → "I")
        result = result.replacingOccurrences(
            of: "\\b(I\\s+){2,}I\\b",
            with: "I",
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
