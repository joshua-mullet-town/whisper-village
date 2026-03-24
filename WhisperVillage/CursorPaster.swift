import Foundation
import AppKit

class CursorPaster {

    static func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let preserveTranscript = UserDefaults.standard.bool(forKey: "preserveTranscriptInClipboard")

        // Apply smart capitalization if enabled (defaults to true when not set)
        let smartCapEnabled = UserDefaults.standard.object(forKey: "SmartCapitalizationEnabled") as? Bool ?? true
        var textToPaste = text

        // Apply auto end punctuation if enabled (defaults to true when not set)
        let autoEndPunctEnabled = UserDefaults.standard.object(forKey: "AutoEndPunctuationEnabled") as? Bool ?? true
        if autoEndPunctEnabled {
            textToPaste = applyAutoEndPunctuation(to: textToPaste)
        }

        var savedContents: [(NSPasteboard.PasteboardType, Data)] = []

        // Only save clipboard contents if we plan to restore them
        if !preserveTranscript {
            let currentItems = pasteboard.pasteboardItems ?? []

            for item in currentItems {
                for type in item.types {
                    if let data = item.data(forType: type) {
                        savedContents.append((type, data))
                    }
                }
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(textToPaste, forType: .string)

        if UserDefaults.standard.bool(forKey: "UseAppleScriptPaste") {
            _ = pasteUsingAppleScript()
        } else {
            pasteUsingCommandV()
        }

        // DIAGNOSTIC: Check if we can read focused element via AX API (for future polling approach)
        checkFocusedElementReadability(expectedText: textToPaste)

        // Only restore clipboard if preserve setting is disabled
        if !preserveTranscript {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !savedContents.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in savedContents {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }
    
    private static func pasteUsingAppleScript() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }
        
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            _ = scriptObject.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
    
    private static func pasteUsingCommandV() {
        guard AXIsProcessTrusted() else {
            return
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }

    // Simulate pressing the Return / Enter key
    static func pressEnter() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }

    // Delete a specific number of characters (backspace N times)
    static func deleteCharacters(count: Int) {
        guard AXIsProcessTrusted() else { return }
        guard count > 0 else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        for _ in 0..<count {
            // Virtual key 0x33 = Delete/Backspace
            let backspaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
            let backspaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
            backspaceDown?.post(tap: .cghidEventTap)
            backspaceUp?.post(tap: .cghidEventTap)
        }
    }

    // Add a period at the end if no ending punctuation present
    private static func applyAutoEndPunctuation(to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Check if already ends with sentence-ending punctuation
        if let lastChar = trimmed.last, ".!?".contains(lastChar) {
            return text
        }

        // Add period at the end (preserve trailing whitespace if any)
        let trailingWhitespace = text.hasSuffix(" ") ? " " : ""
        return trimmed + "." + trailingWhitespace
    }

    // DIAGNOSTIC: Check if we can read the focused element via Accessibility API
    // This helps determine if polling approach would work for double-tap send
    private static func checkFocusedElementReadability(expectedText: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Small delay to let paste start
            let systemWide = AXUIElementCreateSystemWide()
            var focusedApp: AnyObject?

            let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

            if result == .success, let app = focusedApp {
                var focusedElement: AnyObject?
                let elemResult = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

                if elemResult == .success, let element = focusedElement {
                    var value: AnyObject?
                    let valueResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value)

                    if valueResult == .success, let textValue = value as? String {
                        let contains = textValue.contains(expectedText)
                        StreamingLogger.shared.log("🔍 AX API DIAGNOSTIC: Can read focused element ✅ | Contains pasted text: \(contains) | App role available")
                    } else {
                        StreamingLogger.shared.log("🔍 AX API DIAGNOSTIC: Cannot read value ❌ | Error: \(valueResult.rawValue)")
                    }
                } else {
                    StreamingLogger.shared.log("🔍 AX API DIAGNOSTIC: Cannot get focused element ❌ | Error: \(elemResult.rawValue)")
                }
            } else {
                StreamingLogger.shared.log("🔍 AX API DIAGNOSTIC: Cannot get focused app ❌ | Error: \(result.rawValue)")
            }
        }
    }
}
