import Foundation

class WordReplacementService {
    static let shared = WordReplacementService()

    private init() {}

    /// Common Whisper transcription errors that should always be fixed.
    /// These run on every transcription regardless of user settings.
    private let builtInFixes: [(pattern: String, replacement: String)] = [
        // Whisper often drops the 'm' from contractions like "I'm"
        ("\\bI'(?=\\s|$)", "I'm"),
    ]

    /// Applies built-in fixes for common Whisper transcription errors.
    /// Always runs, independent of user word replacement settings.
    func applyBuiltInFixes(to text: String) -> String {
        var modifiedText = text

        for fix in builtInFixes {
            if let regex = try? NSRegularExpression(pattern: fix.pattern, options: .caseInsensitive) {
                let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                modifiedText = regex.stringByReplacingMatches(
                    in: modifiedText,
                    options: [],
                    range: range,
                    withTemplate: fix.replacement
                )
            }
        }

        return modifiedText
    }

    func applyReplacements(to text: String) -> String {
        guard let replacements = UserDefaults.standard.dictionary(forKey: "wordReplacements") as? [String: String],
              !replacements.isEmpty else {
            return text
        }

        var modifiedText = text

        for (original, replacement) in replacements {
            let isPhrase = original.contains(" ") || original.trimmingCharacters(in: .whitespacesAndNewlines) != original

            if isPhrase || !usesWordBoundaries(for: original) {
                modifiedText = modifiedText.replacingOccurrences(of: original, with: replacement, options: .caseInsensitive)
            } else {
                // Use word boundaries for spaced languages
                // Note: \b doesn't work after non-word chars like apostrophes
                // For patterns ending in non-word chars, use lookahead instead
                let escapedOriginal = NSRegularExpression.escapedPattern(for: original)
                let endsWithNonWordChar = original.last.map { !$0.isLetter && !$0.isNumber } ?? false
                let endBoundary = endsWithNonWordChar ? "(?=\\s|$)" : "\\b"
                let pattern = "\\b\(escapedOriginal)\(endBoundary)"

                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(modifiedText.startIndex..., in: modifiedText)
                    modifiedText = regex.stringByReplacingMatches(
                        in: modifiedText,
                        options: [],
                        range: range,
                        withTemplate: replacement
                    )
                }
            }
        }

        return modifiedText
    }

    private func usesWordBoundaries(for text: String) -> Bool {
        // Returns false for languages without spaces (CJK, Thai), true for spaced languages
        let nonSpacedScripts: [ClosedRange<UInt32>] = [
            0x3040...0x309F, // Hiragana
            0x30A0...0x30FF, // Katakana
            0x4E00...0x9FFF, // CJK Unified Ideographs
            0xAC00...0xD7AF, // Hangul Syllables
            0x0E00...0x0E7F, // Thai
        ]

        for scalar in text.unicodeScalars {
            for range in nonSpacedScripts {
                if range.contains(scalar.value) {
                    return false
                }
            }
        }

        return true
    }
}
