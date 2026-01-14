import Foundation
import os

/// Catches crashes and reports them on next launch
final class CrashReporter {
    static let shared = CrashReporter()

    private let logger = Logger(subsystem: "town.mullet.WhisperVillage", category: "CrashReporter")
    private let crashFileURL: URL
    private let sessionFileURL: URL
    private let stateFileURL: URL

    /// Webhook URL for crash reporting (loaded from secrets.plist)
    /// Leave nil to disable automatic reporting
    var webhookURL: String? = {
        // Load from secrets.plist (gitignored)
        if let secretsPath = Bundle.main.path(forResource: "secrets", ofType: "plist"),
           let secrets = NSDictionary(contentsOfFile: secretsPath),
           let url = secrets["CrashWebhookURL"] as? String, !url.isEmpty {
            return url
        }
        return nil
    }()

    /// Called when a crash is detected from previous session
    var onCrashDetected: ((CrashReport) -> Void)?

    /// Cached settings context (written to file for crash reports)
    private var cachedSettingsContext: String = ""

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let crashDir = appSupport.appendingPathComponent("WhisperVillage/Crashes", isDirectory: true)
        try? FileManager.default.createDirectory(at: crashDir, withIntermediateDirectories: true)

        crashFileURL = crashDir.appendingPathComponent("last_crash.json")
        sessionFileURL = crashDir.appendingPathComponent("session_active.flag")
        stateFileURL = crashDir.appendingPathComponent("session_state.txt")
    }

    // MARK: - Public API

    /// Call this EARLY in app launch (before UI)
    func initialize() {
        #if DEBUG
        // Skip crash detection in Debug builds - dev workflow kills app constantly
        // which triggers false "crash" reports every launch
        logger.info("🛡️ CrashReporter skipped (Debug build)")
        return
        #else
        // Check if previous session crashed
        checkForPreviousCrash()

        // Mark this session as active
        markSessionActive()

        // Capture initial settings state (will be updated when settings change)
        captureSettingsState()

        // Install crash handlers
        installCrashHandlers()

        logger.info("🛡️ CrashReporter initialized")
        #endif
    }

    /// Call this when app terminates normally
    func markCleanShutdown() {
        try? FileManager.default.removeItem(at: sessionFileURL)
        try? FileManager.default.removeItem(at: stateFileURL)
        logger.info("✅ Clean shutdown recorded")
    }

    /// Capture current settings and save to file (call periodically or on state changes)
    func captureSettingsState() {
        let defaults = UserDefaults.standard

        var lines: [String] = []
        lines.append("=== Settings Snapshot ===")

        // Core Recording Settings
        lines.append("RecorderType: \(defaults.string(forKey: "RecorderType") ?? "unknown")")
        lines.append("StreamingMode: \(defaults.bool(forKey: "StreamingModeEnabled"))")
        lines.append("LivePreview: \(defaults.bool(forKey: "LivePreviewEnabled"))")
        lines.append("NotchAlwaysVisible: \(defaults.bool(forKey: "NotchAlwaysVisible"))")
        lines.append("PushToTalkMode: \(defaults.bool(forKey: "UsePushToTalk"))")

        // Jarvis Mode
        lines.append("JarvisEnabled: \(defaults.bool(forKey: "JarvisEnabled"))")
        lines.append("JarvisWakeWord: \(defaults.string(forKey: "JarvisWakeWord") ?? "jarvis")")

        // Transcription Settings
        lines.append("TranscriptionProvider: \(defaults.string(forKey: "TranscriptionProvider") ?? "local")")
        lines.append("SelectedModel: \(defaults.string(forKey: "SelectedModel") ?? "unknown")")
        lines.append("SelectedLanguage: \(defaults.string(forKey: "SelectedLanguage") ?? "en")")
        lines.append("IsVADEnabled: \(defaults.bool(forKey: "IsVADEnabled"))")

        // Text Processing
        lines.append("IsTextFormattingEnabled: \(defaults.bool(forKey: "IsTextFormattingEnabled"))")
        lines.append("SmartCapitalization: \(defaults.bool(forKey: "SmartCapitalizationEnabled"))")
        lines.append("AutoEndPunctuation: \(defaults.bool(forKey: "AutoEndPunctuationEnabled"))")
        lines.append("AppendTrailingSpace: \(defaults.bool(forKey: "AppendTrailingSpace"))")
        lines.append("EnhancementEnabled: \(defaults.bool(forKey: "EnhancementEnabled"))")

        // Experimental Features
        lines.append("ExperimentalFeatures: \(defaults.bool(forKey: "isExperimentalFeaturesEnabled"))")

        // Sound Settings
        lines.append("SoundFeedback: \(defaults.bool(forKey: "isSoundFeedbackEnabled"))")

        // Cleanup Settings
        lines.append("AudioCleanup: \(defaults.bool(forKey: "IsAudioCleanupEnabled"))")
        lines.append("TranscriptionCleanup: \(defaults.bool(forKey: "IsTranscriptionCleanupEnabled"))")

        lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")

        cachedSettingsContext = lines.joined(separator: "\n")

        // Write to file so it's available if we crash
        try? cachedSettingsContext.write(to: stateFileURL, atomically: true, encoding: .utf8)
    }

    /// Read saved settings state from file (for crash reports)
    private func readSavedSettingsState() -> String? {
        try? String(contentsOf: stateFileURL, encoding: .utf8)
    }

    /// Manually report an error (non-fatal)
    func reportError(_ error: Error, context: String? = nil) {
        let report = CrashReport(
            type: .error,
            message: error.localizedDescription,
            context: context,
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )

        sendReport(report)
    }

    // MARK: - Crash Detection

    private func checkForPreviousCrash() {
        // Method 1: Check for crash file (written during crash)
        if FileManager.default.fileExists(atPath: crashFileURL.path) {
            if let data = try? Data(contentsOf: crashFileURL),
               let report = try? JSONDecoder().decode(CrashReport.self, from: data) {
                logger.warning("💥 Previous crash detected: \(report.message)")
                handleCrashReport(report)
                try? FileManager.default.removeItem(at: crashFileURL)
            }
        }

        // Method 2: Check if session flag exists (means we didn't shut down cleanly)
        if FileManager.default.fileExists(atPath: sessionFileURL.path) {
            logger.warning("💥 Previous session didn't shut down cleanly (possible crash)")

            // Read saved settings state from previous session
            let savedContext = readSavedSettingsState()

            let report = CrashReport(
                type: .unexpectedTermination,
                message: "App terminated unexpectedly",
                context: savedContext,
                timestamp: Date(),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                stackTrace: nil
            )
            handleCrashReport(report)
            try? FileManager.default.removeItem(at: sessionFileURL)
            try? FileManager.default.removeItem(at: stateFileURL)
        }
    }

    private func markSessionActive() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? timestamp.write(to: sessionFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Crash Handlers

    private func installCrashHandlers() {
        // Swift/ObjC exception handler
        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.shared.handleException(exception)
        }

        // Signal handlers for hard crashes
        signal(SIGABRT) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGSEGV) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGBUS) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGFPE) { signal in CrashReporter.shared.handleSignal(signal) }
        signal(SIGILL) { signal in CrashReporter.shared.handleSignal(signal) }
    }

    private func handleException(_ exception: NSException) {
        let report = CrashReport(
            type: .exception,
            message: "\(exception.name.rawValue): \(exception.reason ?? "Unknown")",
            context: cachedSettingsContext.isEmpty ? nil : cachedSettingsContext,
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            stackTrace: exception.callStackSymbols.joined(separator: "\n")
        )

        saveCrashReport(report)
    }

    private func handleSignal(_ signal: Int32) {
        let signalName: String
        switch signal {
        case SIGABRT: signalName = "SIGABRT"
        case SIGSEGV: signalName = "SIGSEGV"
        case SIGBUS: signalName = "SIGBUS"
        case SIGFPE: signalName = "SIGFPE"
        case SIGILL: signalName = "SIGILL"
        default: signalName = "SIGNAL(\(signal))"
        }

        let report = CrashReport(
            type: .signal,
            message: "Received \(signalName)",
            context: cachedSettingsContext.isEmpty ? nil : cachedSettingsContext,
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            stackTrace: Thread.callStackSymbols.joined(separator: "\n")
        )

        saveCrashReport(report)

        // Re-raise signal to let default handler run (shows crash dialog)
        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
    }

    private func saveCrashReport(_ report: CrashReport) {
        // In signal handler - must be minimal, synchronous, no allocations
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: crashFileURL, options: .atomic)
        }
    }

    // MARK: - Reporting

    private func handleCrashReport(_ report: CrashReport) {
        // Notify callback
        onCrashDetected?(report)

        // Auto-send if webhook configured
        sendReport(report)
    }

    private func sendReport(_ report: CrashReport) {
        guard let webhookURL = webhookURL, let url = URL(string: webhookURL) else {
            logger.info("📝 Crash report not sent (no webhook configured)")
            return
        }

        // Build fields array
        var fields: [[String: Any]] = [
            ["title": "Crash Type", "value": report.type.rawValue, "short": true],
            ["title": "App Version", "value": "\(report.appVersion) (\(report.buildNumber))", "short": true],
            ["title": "OS", "value": report.osVersion, "short": true],
            ["title": "Time", "value": ISO8601DateFormatter().string(from: report.timestamp), "short": true],
            ["title": "Message", "value": report.message, "short": false]
        ]

        // Add stack trace if available
        if let stackTrace = report.stackTrace, !stackTrace.isEmpty {
            let truncatedStack = String(stackTrace.prefix(1500))
            fields.append(["title": "Stack Trace", "value": "```\(truncatedStack)```", "short": false])
        } else {
            fields.append(["title": "Stack Trace", "value": "_Not available (detected on next launch)_", "short": false])
        }

        // Add context (settings) if available
        fields.append(["title": "Settings Context", "value": report.context ?? "None", "short": false])

        let attachment: [String: Any] = [
            "color": report.type == .error ? "#FFA500" : "#ff0000",
            "title": "💥 Whisper Village Crash Report",
            "fields": fields,
            "footer": "Whisper Village Crash Reporter"
        ]

        let payload: [String: Any] = ["attachments": [attachment]]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                self?.logger.error("❌ Failed to send crash report: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                self?.logger.info("✅ Crash report sent successfully")
            }
        }.resume()
    }
}

// MARK: - Models

struct CrashReport: Codable {
    enum CrashType: String, Codable {
        case signal = "Signal Crash"
        case exception = "Exception"
        case error = "Error"
        case unexpectedTermination = "Unexpected Termination"
    }

    let type: CrashType
    let message: String
    let context: String?
    let timestamp: Date
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let stackTrace: String?
}
