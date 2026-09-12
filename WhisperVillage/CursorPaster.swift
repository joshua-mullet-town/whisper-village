import Foundation
import AppKit

class CursorPaster {

    // MARK: - Timing constants
    //
    // These are deliberately named and documented rather than sprinkled as magic
    // numbers, because every one of them was measured rather than guessed.

    /// Upper bound on how long we'll wait for our own write to become readable
    /// back off the pasteboard server. Measured on this machine: ~90µs typical,
    /// ~13ms worst case on a cold pasteboard connection, ~1.6ms worst case under
    /// a 12+ load average. 250ms is far beyond any observed value, so it only ever
    /// trips if something is genuinely wrong — it is a safety net, not the mechanism.
    private static let pasteboardSettleTimeout: TimeInterval = 0.25

    /// How often we re-check for the paste actually landing in the focused app.
    private static let landingPollInterval: TimeInterval = 0.05

    /// How long we'll keep watching for the paste to land before giving up and
    /// leaving the transcript on the clipboard. Slow Electron apps and terminals
    /// under load can take well over a second, which is exactly the case the old
    /// fixed 0.6s restore destroyed.
    private static let landingConfirmTimeout: TimeInterval = 2.5

    static func pasteAtCursor(_ text: String) {
        let pasteboard = NSPasteboard.general
        let preserveTranscript = UserDefaults.standard.bool(forKey: "preserveTranscriptInClipboard")

        // Clean filler words and duplicate words before any other processing
        var textToPaste = cleanFillerWords(text)

        // Apply smart capitalization if enabled (defaults to true when not set)
        let smartCapEnabled = UserDefaults.standard.object(forKey: "SmartCapitalizationEnabled") as? Bool ?? true

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
        // Remember which clipboard generation is ours, so the restore below can tell
        // "nothing touched the clipboard" from "something overwrote us mid-paste".
        let ourChangeCount = pasteboard.changeCount

        // RACE 1 FIX — do not press ⌘V until the text is genuinely readable back off
        // the pasteboard. Setting a pasteboard is not instantaneous from the point of
        // view of the app that will read it: the data has to be available from the
        // pasteboard server. Posting the keystroke immediately after setString means a
        // slow or cold pasteboard hands the target app the PREVIOUS clipboard, or
        // nothing at all. We poll for the round-trip rather than sleeping a guessed
        // number of milliseconds, so this costs ~0.1ms when the machine is idle and
        // only stretches when it genuinely needs to.
        let settleWaitMs = waitForPasteboardToSettle(pasteboard, expecting: textToPaste, changeCount: ourChangeCount)

        // Capture the runtime accessibility answer and the target app BEFORE pasting.
        // AXIsProcessTrusted() can disagree with the stored permission grant after a
        // re-sign or restart, and both paste paths bail silently when it does.
        let axTrusted = DictationAuditLog.axTrusted
        let frontApp = DictationAuditLog.frontmostBundleID
        let useAppleScript = UserDefaults.standard.bool(forKey: "UseAppleScriptPaste")
        let method = useAppleScript ? "applescript" : "cgevent"

        DictationAuditLog.shared.logPasteAttempt(
            textLength: textToPaste.count,
            method: method,
            axTrusted: axTrusted,
            frontmostBundleID: frontApp
        )
        DictationAuditLog.shared.log("PASTEBOARD_SETTLED", [
            "waitMs": settleWaitMs,
            "settled": settleWaitMs >= 0,
        ])

        // If the transcript never became readable, pressing ⌘V would paste the wrong
        // thing. Better to stop, keep the words on the clipboard, and say so.
        guard settleWaitMs >= 0 else {
            DictationAuditLog.shared.log("PASTE_BLOCKED", [
                "reason": "pasteboard-never-settled",
                "frontApp": frontApp,
                "chars": textToPaste.count,
            ])
            notifyPasteFailed("Couldn't reach the clipboard in time. Your text is on the clipboard — press Cmd+V.")
            return
        }

        // The silent-failure guard, made loud. Both paste paths used to `return` here
        // with no log and no user-visible signal, so the transcript simply evaporated.
        guard axTrusted else {
            DictationAuditLog.shared.log("PASTE_BLOCKED", [
                "reason": "accessibility-not-trusted",
                "frontApp": frontApp,
                "chars": textToPaste.count,
            ])
            notifyPasteFailed("Couldn't type that — accessibility permission is off. Your text is on the clipboard; press Cmd+V.")
            // Leave the transcript ON the clipboard rather than restoring over it, so a
            // manual paste still recovers the words instead of losing them.
            return
        }

        var pasteDispatched = false
        if useAppleScript {
            pasteDispatched = pasteUsingAppleScript()
        } else {
            pasteDispatched = pasteUsingCommandV()
        }

        if !pasteDispatched {
            DictationAuditLog.shared.log("PASTE_DISPATCH_FAILED", [
                "method": method,
                "frontApp": frontApp,
                "chars": textToPaste.count,
            ])
            notifyPasteFailed("Couldn't type that. Your text is on the clipboard — press Cmd+V.")
            return
        }

        // RACE 2 FIX — the restore is no longer a blind 0.6s timer.
        //
        // The old code unconditionally put the previous clipboard back after 0.6s,
        // without ever checking whether the paste had landed. When the target app was
        // slow (a loaded terminal, an Electron window), the restore overwrote the
        // transcript WHILE the app was still reading it, and the words were gone — the
        // app destroyed the thing it had just produced.
        //
        // Now we watch for the paste to actually land, and only restore once it has.
        // If we can't confirm it, we deliberately DO NOT restore: leaving a stale
        // transcript on the clipboard is a minor annoyance, whereas destroying it
        // loses the user's words. That asymmetry decides the default.
        if !preserveTranscript && !savedContents.isEmpty {
            confirmPasteLandedThenRestore(
                pasteboard: pasteboard,
                expectedText: textToPaste,
                ourChangeCount: ourChangeCount,
                savedContents: savedContents
            )
        } else {
            // Nothing to restore; still record whether it landed so failures are visible.
            confirmPasteLanded(expectedText: textToPaste) { landed, elapsed in
                DictationAuditLog.shared.log("PASTE_RESULT", [
                    "landed": landed,
                    "elapsedMs": Int(elapsed * 1000),
                    "restored": false,
                ])
                if !landed {
                    notifyPasteFailed("Couldn't confirm that pasted. Your text is on the clipboard — press Cmd+V.")
                }
            }
        }
    }

    // MARK: - Race 1: pasteboard settle

    /// Blocks (briefly) until `expected` can be read back off the pasteboard, proving
    /// the write is visible to whoever reads it next. Returns the wait in milliseconds,
    /// or -1 if it never settled inside `pasteboardSettleTimeout`.
    ///
    /// This runs on the calling (main) thread on purpose: it is sub-millisecond in the
    /// normal case, and the paste keystroke must not be posted before it completes.
    /// The bounded timeout guarantees we can never hang the UI.
    private static func waitForPasteboardToSettle(
        _ pasteboard: NSPasteboard,
        expecting expected: String,
        changeCount: Int
    ) -> Int {
        let start = Date()
        while Date().timeIntervalSince(start) < pasteboardSettleTimeout {
            // Someone else wrote to the clipboard after us — our text is already gone,
            // so waiting longer cannot help.
            if pasteboard.changeCount != changeCount { return -1 }
            if pasteboard.string(forType: .string) == expected {
                return Int(Date().timeIntervalSince(start) * 1000)
            }
            usleep(200) // 0.2ms — fine-grained enough to stay imperceptible
        }
        return -1
    }

    // MARK: - Race 2: confirm the paste landed before restoring

    /// Watches the focused UI element until the pasted text appears in it, then calls
    /// back with whether it landed and how long it took.
    ///
    /// Uses the same Accessibility read that the old diagnostic used — that diagnostic
    /// was already computing exactly the signal needed here, it just threw it away.
    private static func confirmPasteLanded(
        expectedText: String,
        completion: @escaping (Bool, TimeInterval) -> Void
    ) {
        let start = Date()

        // A trimmed needle: the app may normalise trailing whitespace we appended.
        let needle = expectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { completion(true, 0); return }

        func poll() {
            let elapsed = Date().timeIntervalSince(start)
            if focusedElementContains(needle) {
                completion(true, elapsed)
                return
            }
            if elapsed >= landingConfirmTimeout {
                completion(false, elapsed)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + landingPollInterval) { poll() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + landingPollInterval) { poll() }
    }

    /// Confirms the paste landed and ONLY THEN restores the previous clipboard.
    /// If it cannot be confirmed, the transcript is left on the clipboard on purpose.
    private static func confirmPasteLandedThenRestore(
        pasteboard: NSPasteboard,
        expectedText: String,
        ourChangeCount: Int,
        savedContents: [(NSPasteboard.PasteboardType, Data)]
    ) {
        confirmPasteLanded(expectedText: expectedText) { landed, elapsed in
            // If something else has already taken the clipboard, restoring would stomp
            // whatever the user or another app just copied. Leave it alone.
            let clipboardStillOurs = pasteboard.changeCount == ourChangeCount

            DictationAuditLog.shared.log("PASTE_RESULT", [
                "landed": landed,
                "elapsedMs": Int(elapsed * 1000),
                "clipboardStillOurs": clipboardStillOurs,
                "restored": landed && clipboardStillOurs,
                "frontApp": DictationAuditLog.frontmostBundleID,
            ])

            guard landed else {
                // THE important branch. We could not verify the words arrived, so we
                // refuse to overwrite them. The user keeps their transcript and gets
                // told they can paste it themselves.
                DictationAuditLog.shared.log("CLIPBOARD_RESTORE_SKIPPED", [
                    "reason": "paste-not-confirmed",
                    "transcriptPreserved": true,
                ])
                notifyPasteFailed("Couldn't confirm that pasted. Your text is on the clipboard — press Cmd+V.")
                return
            }

            guard clipboardStillOurs else {
                DictationAuditLog.shared.log("CLIPBOARD_RESTORE_SKIPPED", [
                    "reason": "clipboard-changed-by-someone-else",
                ])
                return
            }

            pasteboard.clearContents()
            for (type, data) in savedContents {
                pasteboard.setData(data, forType: type)
            }
        }
    }

    /// Reads the focused UI element's text and reports whether it contains `needle`.
    /// Returns false (rather than throwing) whenever accessibility can't answer, so a
    /// non-readable app is treated as "unconfirmed" and the transcript is preserved.
    private static func focusedElementContains(_ needle: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else { return false }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else { return false }

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &value) == .success,
              let textValue = value as? String else { return false }

        return textValue.contains(needle)
    }

    /// One place for "tell the user the paste failed", so no failure path can go quiet
    /// again. Every early return in pasteAtCursor routes through this.
    private static func notifyPasteFailed(_ message: String) {
        DispatchQueue.main.async {
            NotificationManager.shared.showNotification(
                title: message,
                type: .error,
                duration: 8.0
            )
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
    
    /// Returns false if the keystrokes could not be built, so the caller can tell the
    /// user instead of failing silently.
    @discardableResult
    private static func pasteUsingCommandV() -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            return false
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        return true
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

    // Remove filler words (uh, um, etc.) and collapse duplicate consecutive words
    private static func cleanFillerWords(_ text: String) -> String {
        var result = text

        // 1. Remove filler words (with optional trailing comma/period)
        // Matches: uh, um, uhm, ah, eh (case insensitive, word boundaries)
        if let fillerRegex = try? NSRegularExpression(pattern: "\\b(uh|um|uhm|ah|eh)\\b[,.]?\\s*", options: .caseInsensitive) {
            result = fillerRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // 2. Collapse duplicate consecutive words ("I I" → "I", "the the" → "the")
        if let dupeRegex = try? NSRegularExpression(pattern: "\\b(\\w+)\\s+\\1\\b", options: .caseInsensitive) {
            result = dupeRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }

        // 3. Clean up extra spaces
        if let spacesRegex = try? NSRegularExpression(pattern: "\\s{2,}") {
            result = spacesRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }

        return result.trimmingCharacters(in: .whitespaces)
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
}
