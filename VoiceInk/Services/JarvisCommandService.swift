import Foundation
import AppKit
import SwiftUI

/// Service for detecting and executing Jarvis voice commands
class JarvisCommandService: ObservableObject {
    static let shared = JarvisCommandService()

    /// User-configurable wake word
    @AppStorage("JarvisWakeWord") var wakeWord: String = "jarvis"

    /// Whether Jarvis is enabled
    @AppStorage("JarvisEnabled") var isEnabled: Bool = true

    private let ollamaClient = OllamaClient.shared
    private let logger = StreamingLogger.shared

    /// Result of detecting a Jarvis command
    struct DetectedCommand {
        let fullPhrase: String        // "jarvis switch to terminal"
        let commandPart: String       // "switch to terminal"
        let textBefore: String        // Text before the wake word
        let textAfter: String         // Text after the command (if any)
        let range: Range<String.Index>
    }

    /// Result of executing a command
    enum ExecutionResult {
        case sendAndContinue         // Paste + Enter, clear buffer, enter command mode
        case sendAndStop             // Paste (no Enter), stop recording
        case navigated               // Focused an app/tab, enter command mode
        case cancelled               // Discarded, stop recording
        case paused                  // Enter command mode (buffer preserved)
        case resumeListening         // Exit command mode, resume transcribing
        case failed(String)          // Error message
    }

    // MARK: - Detection

    /// Detect if text contains a Jarvis command
    /// Returns nil if no command found, or if command is incomplete (just "Jarvis" at end)
    func detectCommand(in text: String) -> DetectedCommand? {
        guard isEnabled else { return nil }

        let lowercased = text.lowercased()
        let wakeWordLower = wakeWord.lowercased()

        // Find wake word
        guard let wakeWordRange = lowercased.range(of: wakeWordLower) else {
            return nil
        }

        // Get text after wake word
        let afterWakeWord = String(text[wakeWordRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // If there's nothing after the wake word, it's incomplete
        if afterWakeWord.isEmpty {
            return nil
        }

        // Extract command (everything after wake word until end or next sentence)
        // For now, take everything after wake word
        let commandPart = afterWakeWord

        // Text before the wake word
        let textBefore = String(text[..<wakeWordRange.lowerBound]).trimmingCharacters(in: .whitespaces)

        return DetectedCommand(
            fullPhrase: "\(wakeWord) \(commandPart)",
            commandPart: commandPart,
            textBefore: textBefore,
            textAfter: "",  // For now, we consume everything after Jarvis
            range: wakeWordRange.lowerBound..<text.endIndex
        )
    }

    // MARK: - Execution

    /// Execute a detected command
    func execute(_ command: DetectedCommand) async -> ExecutionResult {
        logger.log("Jarvis executing: \"\(command.commandPart)\"")

        // First, try built-in commands (fast, no LLM needed)
        if let builtInResult = tryBuiltInCommand(command.commandPart) {
            return builtInResult
        }

        // For navigation commands, use LLM
        do {
            let context = await gatherAppContext()
            let action = try await ollamaClient.interpret(command: command.commandPart, context: context)

            switch action {
            case .send:
                return .sendAndContinue
            case .stop:
                return .sendAndStop
            case .cancel:
                return .cancelled
            case .listen:
                return .resumeListening
            case .focusApp(let name):
                await focusApp(name)
                return .navigated
            case .focusTab(let app, let window, let tab):
                await focusTab(app: app, window: window, tab: tab)
                return .navigated
            case .unknown:
                logger.log("Jarvis: Unknown command, staying in command mode")
                return .paused  // Unknown command = stay in command mode
            }
        } catch {
            logger.log("Jarvis LLM error: \(error)")
            // Fall back to built-in if LLM fails
            return .failed("LLM unavailable")
        }
    }

    /// Check if a command matches a built-in command (public, for interrupt checking)
    func isBuiltInCommand(_ command: String) -> Bool {
        return tryBuiltInCommand(command) != nil
    }

    /// Try to match a built-in command (no LLM needed)
    private func tryBuiltInCommand(_ command: String) -> ExecutionResult? {
        // Clean up the command: lowercase, remove punctuation and whitespace
        var cleaned = command.lowercased()
        // Remove all punctuation (not just at ends)
        cleaned = cleaned.components(separatedBy: CharacterSet.punctuationCharacters).joined()
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        logger.log("Built-in check: \"\(command)\" -> cleaned: \"\(cleaned)\"")

        // Check for listen/resume commands first (most common transcription errors)
        let listenVariations = ["listen", "listening", "lists", "listing", "lake", "liston", "lesson", "transcribe", "continue", "resume", "go", "start"]
        if listenVariations.contains(cleaned) || cleaned.hasPrefix("listen") {
            logger.log("Built-in match: '\(cleaned)' -> resumeListening")
            return .resumeListening
        }

        switch cleaned {
        case "send it", "send", "sent", "sendit":
            return .sendAndContinue
        case "stop", "done", "finish":
            return .sendAndStop
        case "cancel", "nevermind", "never mind", "abort":
            return .cancelled
        case "pause", "wait", "hold":
            return .paused
        default:
            return nil
        }
    }

    // MARK: - App Context

    /// Gather context about open applications
    private func gatherAppContext() async -> OllamaClient.AppContext {
        let openApps = getOpenApps()
        let itermTabs = getItermTabs()
        let chromeTabs = getChromeTabs()

        return OllamaClient.AppContext(
            openApps: openApps,
            itermTabs: itermTabs,
            chromeTabs: chromeTabs
        )
    }

    private func getOpenApps() -> [String] {
        let script = """
        tell application "System Events" to get name of every process whose background only is false
        """
        return runAppleScript(script)?.components(separatedBy: ", ") ?? []
    }

    private func getItermTabs() -> [(window: Int, tab: Int, name: String)] {
        let script = """
        tell application "iTerm2"
            set output to ""
            set winNum to 1
            repeat with w in windows
                set tabNum to 1
                repeat with t in tabs of w
                    set output to output & winNum & "," & tabNum & "," & (name of current session of t) & linefeed
                    set tabNum to tabNum + 1
                end repeat
                set winNum to winNum + 1
            end repeat
            return output
        end tell
        """

        guard let output = runAppleScript(script) else { return [] }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3,
                  let window = Int(parts[0]),
                  let tab = Int(parts[1]) else { return nil }
            let name = parts.dropFirst(2).joined(separator: ",")
            return (window, tab, name)
        }
    }

    private func getChromeTabs() -> [(window: Int, tab: Int, title: String)] {
        let script = """
        tell application "Google Chrome"
            set output to ""
            set winNum to 1
            repeat with w in windows
                set tabNum to 1
                repeat with t in tabs of w
                    set output to output & winNum & "," & tabNum & "," & (title of t) & linefeed
                    set tabNum to tabNum + 1
                end repeat
                set winNum to winNum + 1
            end repeat
            return output
        end tell
        """

        guard let output = runAppleScript(script) else { return [] }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3,
                  let window = Int(parts[0]),
                  let tab = Int(parts[1]) else { return nil }
            let title = parts.dropFirst(2).joined(separator: ",")
            return (window, tab, title)
        }
    }

    // MARK: - Navigation Actions

    @MainActor
    private func focusApp(_ name: String) {
        let script = "tell application \"\(name)\" to activate"
        _ = runAppleScript(script)
        logger.log("Jarvis: Focused app \(name)")
    }

    @MainActor
    private func focusTab(app: String, window: Int, tab: Int) {
        let script: String

        if app == "iTerm2" || app.lowercased().contains("iterm") {
            script = """
            tell application "iTerm2"
                activate
                tell window \(window)
                    select tab \(tab)
                end tell
            end tell
            """
        } else if app == "Google Chrome" || app.lowercased().contains("chrome") {
            script = """
            tell application "Google Chrome"
                activate
                set active tab index of window \(window) to \(tab)
            end tell
            """
        } else {
            // Generic app focus
            script = "tell application \"\(app)\" to activate"
        }

        _ = runAppleScript(script)
        logger.log("Jarvis: Focused \(app) window \(window) tab \(tab)")
    }

    // MARK: - Text Processing

    /// Strip a Jarvis command from transcribed text, returning only the text before the command
    func stripCommand(_ command: DetectedCommand, from text: String) -> String {
        let lowercased = text.lowercased()
        let wakeWordLower = wakeWord.lowercased()

        // Find the wake word in the text
        guard let wakeWordRange = lowercased.range(of: wakeWordLower) else {
            // Wake word not found, return original text
            return text
        }

        // Return everything before the wake word
        let textBefore = String(text[..<wakeWordRange.lowerBound])
        return textBefore.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
