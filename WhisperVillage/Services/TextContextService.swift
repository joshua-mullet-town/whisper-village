import Foundation
import AppKit

class TextContextService {
    static let shared = TextContextService()

    // Cached context from when recording started
    private var cachedContextBeforeCursor: String?
    private var hasCachedContext: Bool = false

    private init() {}

    /// Cache the text context for later use (call when recording starts)
    func cacheCurrentContext() {
        cachedContextBeforeCursor = getTextBeforeCursor()
        hasCachedContext = true
        StreamingLogger.shared.log("[SmartCap] Cached context: \"\(cachedContextBeforeCursor?.suffix(30) ?? "nil")\"")
    }

    /// Clear the cached context (call after paste)
    func clearCachedContext() {
        cachedContextBeforeCursor = nil
        hasCachedContext = false
    }

    /// Get cached context if available, otherwise fetch fresh (slower)
    func getCachedOrFreshContext() -> String? {
        if hasCachedContext {
            return cachedContextBeforeCursor
        }
        return getTextBeforeCursor()
    }

    /// Get the text immediately before the cursor in the focused text field.
    /// Uses Accessibility API to read the focused element's value and selection.
    func getTextBeforeCursor() -> String? {
        guard AXIsProcessTrusted() else {
            StreamingLogger.shared.log("[SmartCap] AXIsProcessTrusted = false, no accessibility")
            return nil
        }

        // Get the focused UI element
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let element = focusedElement else {
            StreamingLogger.shared.log("[SmartCap] Failed to get focused element, result=\(result.rawValue)")
            return nil
        }

        let axElement = element as! AXUIElement

        // Get the full text value
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &valueRef
        )

        guard valueResult == .success, let value = valueRef as? String else {
            StreamingLogger.shared.log("[SmartCap] Failed to get kAXValueAttribute, result=\(valueResult.rawValue)")
            return nil
        }

        StreamingLogger.shared.log("[SmartCap] Full text value: \"\(value.prefix(100))...\" (len=\(value.count))")

        // Get the selected text range (cursor position)
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )

        guard rangeResult == .success, let rangeValue = rangeRef else {
            // If we can't get cursor position, assume end of text
            StreamingLogger.shared.log("[SmartCap] No cursor range, using full text")
            return value
        }

        // Extract the CFRange from the AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            StreamingLogger.shared.log("[SmartCap] Failed to extract CFRange")
            return value
        }

        StreamingLogger.shared.log("[SmartCap] Cursor at position \(range.location), selection length \(range.length)")

        // Get text before cursor
        let cursorPosition = range.location
        if cursorPosition > 0 && cursorPosition <= value.count {
            let index = value.index(value.startIndex, offsetBy: cursorPosition)
            let textBefore = String(value[..<index])
            StreamingLogger.shared.log("[SmartCap] Text before cursor: \"\(textBefore.suffix(50))\"")
            return textBefore
        }

        StreamingLogger.shared.log("[SmartCap] Cursor at start or invalid position")
        return nil
    }

    /// Determines if the first character should be lowercased based on context.
    /// Returns true if we're mid-sentence (should lowercase).
    func shouldLowercaseFirstChar(contextBefore: String?) -> Bool {
        guard let context = contextBefore, !context.isEmpty else {
            StreamingLogger.shared.log("[SmartCap] Decision: CAPITALIZE (empty context)")
            return false
        }

        // Get the last non-whitespace character
        let trimmed = context.trimmingCharacters(in: .whitespaces)
        guard let lastChar = trimmed.last else {
            StreamingLogger.shared.log("[SmartCap] Decision: CAPITALIZE (all whitespace)")
            return false
        }

        StreamingLogger.shared.log("[SmartCap] Last non-ws char: '\(lastChar)' (unicode: \(lastChar.unicodeScalars.first?.value ?? 0))")

        // Sentence-ending punctuation → capitalize
        if ".!?".contains(lastChar) {
            StreamingLogger.shared.log("[SmartCap] Decision: CAPITALIZE (sentence end punctuation)")
            return false
        }

        // Check if last non-whitespace char is a newline → new paragraph, capitalize
        // Actually we need to check the actual last character including whitespace
        if let actualLast = context.last, actualLast.isNewline {
            StreamingLogger.shared.log("[SmartCap] Decision: CAPITALIZE (newline)")
            return false
        }

        // Continuation punctuation → lowercase
        if ":;,".contains(lastChar) {
            StreamingLogger.shared.log("[SmartCap] Decision: lowercase (continuation punctuation)")
            return true
        }

        // Letter or digit (mid-word/sentence) → lowercase
        if lastChar.isLetter || lastChar.isNumber {
            StreamingLogger.shared.log("[SmartCap] Decision: lowercase (letter/digit)")
            return true
        }

        // If we end with whitespace and previous char is a letter → mid-sentence
        if context.last?.isWhitespace == true {
            StreamingLogger.shared.log("[SmartCap] Decision: lowercase (ends with whitespace)")
            return true
        }

        StreamingLogger.shared.log("[SmartCap] Decision: CAPITALIZE (default)")
        return false
    }

    /// Apply smart capitalization to text based on cursor context.
    /// If we're mid-sentence, lowercase the first character.
    /// Uses cached context if available (faster), otherwise fetches fresh.
    func applySmartCapitalization(to text: String) -> String {
        guard !text.isEmpty else { return text }

        StreamingLogger.shared.log("[SmartCap] Applying to text: \"\(text.prefix(50))...\"")
        let context = getCachedOrFreshContext()

        // Clear cache after use
        clearCachedContext()

        if shouldLowercaseFirstChar(contextBefore: context) {
            // Lowercase the first character
            var chars = Array(text)
            if let first = chars.first, first.isUppercase {
                chars[0] = Character(first.lowercased())
                let result = String(chars)
                StreamingLogger.shared.log("[SmartCap] Result: lowercased first char → \"\(result.prefix(50))...\"")
                return result
            } else {
                StreamingLogger.shared.log("[SmartCap] First char not uppercase, no change")
            }
        } else {
            StreamingLogger.shared.log("[SmartCap] Keeping original capitalization")
        }

        return text
    }
}
