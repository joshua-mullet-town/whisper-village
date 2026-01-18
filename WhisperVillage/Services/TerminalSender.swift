import Foundation
import AppKit

/// Sends text to the last focused terminal window (iTerm2 or Terminal.app)
/// Uses AppleScript for reliable terminal input
class TerminalSender {

    static let shared = TerminalSender()

    /// Supported terminal applications
    private let terminalBundleIDs = [
        "com.googlecode.iterm2",      // iTerm2
        "com.apple.Terminal"           // Terminal.app
    ]

    private init() {}

    /// Send text to the most recently active terminal and optionally press Enter
    /// Uses AppleScript to directly write to the terminal
    /// - Parameters:
    ///   - text: The text to send
    ///   - pressEnter: Whether to press Enter after sending (default: true)
    /// - Returns: True if text was sent successfully
    @discardableResult
    func sendToTerminal(_ text: String, pressEnter: Bool = true) -> Bool {
        // Find the most recently active terminal app
        guard let terminalApp = findLastActiveTerminal() else {
            StreamingLogger.shared.log("TerminalSender: No terminal app found")
            return false
        }

        let bundleID = terminalApp.bundleIdentifier ?? ""
        StreamingLogger.shared.log("TerminalSender: Sending to \(terminalApp.localizedName ?? "terminal") (\(bundleID))")
        StreamingLogger.shared.log("TerminalSender: Text to send: '\(text)'")
        StreamingLogger.shared.log("TerminalSender: pressEnter=\(pressEnter)")

        // Use AppleScript to send text directly to the terminal
        let success: Bool
        if bundleID == "com.googlecode.iterm2" {
            success = sendToiTerm2(text: text, withNewline: pressEnter)
        } else if bundleID == "com.apple.Terminal" {
            success = sendToTerminalApp(text: text, withNewline: pressEnter)
        } else {
            StreamingLogger.shared.log("TerminalSender: Unknown terminal app")
            return false
        }

        StreamingLogger.shared.log("TerminalSender: AppleScript returned success=\(success)")
        return success
    }

    /// Send text to iTerm2 using AppleScript
    private func sendToiTerm2(text: String, withNewline: Bool) -> Bool {
        // Escape special characters for AppleScript string
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // iTerm2's "write text" command:
        // - Default behavior (no "newline NO"): adds newline, simulates pressing Enter
        // - With "newline NO": just writes text without Enter
        let script: String
        if withNewline {
            // Default: write text adds newline (presses Enter)
            script = """
            tell application "iTerm2"
                tell current session of current window
                    write text "\(escapedText)"
                end tell
            end tell
            """
        } else {
            // Without newline
            script = """
            tell application "iTerm2"
                tell current session of current window
                    write text "\(escapedText)" newline NO
                end tell
            end tell
            """
        }

        StreamingLogger.shared.log("TerminalSender: Running iTerm2 AppleScript (withNewline=\(withNewline))")
        return runAppleScript(script)
    }

    /// Send text to Terminal.app using AppleScript
    private func sendToTerminalApp(text: String, withNewline: Bool) -> Bool {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // For Terminal.app, we use "do script" which runs the text as a command
        // If we don't want newline, we need a different approach
        let script: String
        if withNewline {
            script = """
            tell application "Terminal"
                do script "\(escapedText)" in front window
            end tell
            """
        } else {
            // For no newline, we use System Events to type
            script = """
            tell application "Terminal" to activate
            delay 0.1
            tell application "System Events"
                keystroke "\(escapedText)"
            end tell
            """
        }

        StreamingLogger.shared.log("TerminalSender: Running Terminal.app AppleScript")
        return runAppleScript(script)
    }

    /// Execute an AppleScript and return success/failure
    private func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            if let error = error {
                StreamingLogger.shared.log("TerminalSender: AppleScript error: \(error)")
                return false
            }
            return true
        }
        StreamingLogger.shared.log("TerminalSender: Failed to create AppleScript")
        return false
    }

    /// Find the most recently active terminal application
    private func findLastActiveTerminal() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        // Filter to only terminal apps that are running
        let terminals = runningApps.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return terminalBundleIDs.contains(bundleID)
        }

        // If only one terminal running, use it
        if terminals.count == 1 {
            return terminals.first
        }

        // If multiple terminals, prefer iTerm2 (most likely for developers)
        // In the future, we could track which was most recently focused
        if let iTerm = terminals.first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" }) {
            return iTerm
        }

        return terminals.first
    }
}
