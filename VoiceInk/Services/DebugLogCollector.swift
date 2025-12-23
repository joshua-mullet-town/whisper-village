import Foundation
import AppKit
import AVFoundation

/// Collects debug information for troubleshooting user issues
class DebugLogCollector {
    static let shared = DebugLogCollector()

    private init() {}

    /// Slack webhook URL for #debug-logs channel (loaded from secrets.plist)
    private var slackWebhookURL: String? = {
        if let secretsPath = Bundle.main.path(forResource: "secrets", ofType: "plist"),
           let secrets = NSDictionary(contentsOfFile: secretsPath),
           let url = secrets["DebugLogsWebhookURL"] as? String, !url.isEmpty {
            return url
        }
        return nil
    }()

    /// Collect all debug information as a formatted string
    func collectDebugInfo() -> String {
        var info: [String] = []

        // Header
        info.append("═══════════════════════════════════════")
        info.append("WHISPER VILLAGE DEBUG REPORT")
        info.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        info.append("═══════════════════════════════════════")

        // App Info
        info.append("")
        info.append("── APP INFO ──")
        info.append("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")
        info.append("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")")
        info.append("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")

        // System Info
        info.append("")
        info.append("── SYSTEM INFO ──")
        info.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        info.append("RAM: \(getSystemRAM())")
        info.append("Chip: \(getProcessorInfo())")

        // Permissions
        info.append("")
        info.append("── PERMISSIONS ──")
        info.append("Microphone: \(getMicrophonePermissionStatus())")
        info.append("Accessibility: \(AXIsProcessTrusted() ? "GRANTED" : "DENIED")")

        // All Settings - dump everything relevant
        info.append("")
        info.append("── ALL SETTINGS ──")
        let defaults = UserDefaults.standard

        // Transcription
        info.append("DefaultTranscriptionModel: \(defaults.string(forKey: "DefaultTranscriptionModel") ?? "not set")")
        info.append("SelectedLanguage: \(defaults.string(forKey: "SelectedLanguage") ?? "en")")
        info.append("StreamingModeEnabled: \(defaults.bool(forKey: "StreamingModeEnabled"))")

        // Live Preview
        info.append("LivePreviewEnabled: \(defaults.bool(forKey: "LivePreviewEnabled"))")
        info.append("LivePreviewStyle: \(defaults.string(forKey: "LivePreviewStyle") ?? "not set")")

        // Recorder
        info.append("RecorderType: \(defaults.string(forKey: "RecorderType") ?? "not set")")
        info.append("NotchAlwaysVisible: \(defaults.bool(forKey: "NotchAlwaysVisible"))")

        // Auto Formatting
        info.append("SmartCapitalizationEnabled: \(defaults.bool(forKey: "SmartCapitalizationEnabled"))")
        info.append("AutoEndPunctuationEnabled: \(defaults.bool(forKey: "AutoEndPunctuationEnabled"))")
        info.append("IsMLCleanupEnabled: \(defaults.bool(forKey: "IsMLCleanupEnabled"))")
        info.append("MLCleanupFillerEnabled: \(defaults.bool(forKey: "MLCleanupFillerEnabled"))")
        info.append("MLCleanupRepetitionEnabled: \(defaults.bool(forKey: "MLCleanupRepetitionEnabled"))")

        // AI Polish
        info.append("AIPolishProvider: \(defaults.string(forKey: "AIPolishProvider") ?? "not set")")
        info.append("GroqPolishModel: \(defaults.string(forKey: "GroqPolishModel") ?? "not set")")
        info.append("CerebrasPolishModel: \(defaults.string(forKey: "CerebrasPolishModel") ?? "not set")")
        info.append("OpenAIPolishModel: \(defaults.string(forKey: "OpenAIPolishModel") ?? "not set")")
        info.append("HasGroqAPIKey: \(defaults.string(forKey: "GroqAPIKey")?.isEmpty == false)")
        info.append("HasCerebrasAPIKey: \(defaults.string(forKey: "CerebrasAPIKey")?.isEmpty == false)")
        info.append("HasOpenAIAPIKey: \(defaults.string(forKey: "OpenAIAPIKey")?.isEmpty == false)")

        // Command Mode
        info.append("CommandModeEnabled: \(defaults.bool(forKey: "CommandModeEnabled"))")
        info.append("CommandModeTriggerWord: \(defaults.string(forKey: "CommandModeTriggerWord") ?? "not set")")

        // Sound & Feedback
        info.append("SoundEnabled: \(defaults.bool(forKey: "SoundEnabled"))")
        info.append("SystemMuteEnabled: \(defaults.bool(forKey: "SystemMuteEnabled"))")

        // App Behavior
        info.append("IsMenuBarOnly: \(defaults.bool(forKey: "IsMenuBarOnly"))")
        info.append("autoUpdateCheck: \(defaults.bool(forKey: "autoUpdateCheck"))")
        info.append("hasCompletedOnboarding: \(defaults.bool(forKey: "hasCompletedOnboarding"))")

        // Migrations
        info.append("SettingsMigration_v1.9.3: \(defaults.bool(forKey: "SettingsMigration_v1.9.3_LivePreviewBox"))")
        info.append("SettingsMigration_v1.9.4: \(defaults.bool(forKey: "SettingsMigration_v1.9.4_StreamingMode"))")

        // Recent Streaming Logs (last 100 lines)
        info.append("")
        info.append("── STREAMING LOGS (last 100 lines) ──")
        let logs = getRecentStreamingLogs(lineCount: 100)
        if logs.isEmpty {
            info.append("(no logs found)")
        } else {
            info.append(logs)
        }

        info.append("")
        info.append("═══════════════════════════════════════")
        info.append("END OF DEBUG REPORT")
        info.append("═══════════════════════════════════════")

        return info.joined(separator: "\n")
    }

    /// Get recent streaming logs from file
    private func getRecentStreamingLogs(lineCount: Int) -> String {
        let logFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WhisperVillage/streaming.log")

        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return "(could not read log file)"
        }

        let lines = content.components(separatedBy: .newlines)
        let recentLines = lines.suffix(lineCount)
        return recentLines.joined(separator: "\n")
    }

    /// Get system RAM
    private func getSystemRAM() -> String {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let gb = Double(physicalMemory) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }

    /// Get processor info
    private func getProcessorInfo() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// Get microphone permission status
    private func getMicrophonePermissionStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "GRANTED"
        case .denied:
            return "DENIED"
        case .restricted:
            return "RESTRICTED"
        case .notDetermined:
            return "NOT_DETERMINED"
        @unknown default:
            return "UNKNOWN"
        }
    }

    /// Send debug logs to Slack
    func sendToSlack(userName: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let webhookURL = slackWebhookURL else {
            completion(.failure(NSError(domain: "DebugLogCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Webhook not configured"])))
            return
        }

        let debugInfo = collectDebugInfo()
        let displayName = userName?.isEmpty == false ? userName! : "Anonymous User"

        // Format for Slack
        let slackMessage: [String: Any] = [
            "text": "Debug Report from \(displayName)",
            "blocks": [
                [
                    "type": "header",
                    "text": [
                        "type": "plain_text",
                        "text": "🔍 Debug Report from \(displayName)",
                        "emoji": true
                    ]
                ],
                [
                    "type": "section",
                    "text": [
                        "type": "mrkdwn",
                        "text": "```\(debugInfo.prefix(2900))```" // Slack has limits
                    ]
                ]
            ]
        ]

        guard let url = URL(string: webhookURL) else {
            completion(.failure(NSError(domain: "DebugLogCollector", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid webhook URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: slackMessage)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "DebugLogCollector", code: 3, userInfo: [NSLocalizedDescriptionKey: "Slack returned non-200 status"])))
            }
        }.resume()
    }

    /// Copy debug info to clipboard
    func copyToClipboard() {
        let debugInfo = collectDebugInfo()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugInfo, forType: .string)
    }
}
