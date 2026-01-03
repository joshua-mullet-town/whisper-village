import Foundation

/// Manages Claude Code summary hooks that generate session summaries using local Ollama
/// Follows the same pattern as GoalModeManager - clones repo and runs install.sh
@MainActor
class SummaryHookManager: ObservableObject {
    static let shared = SummaryHookManager()

    enum InstallStatus {
        case checking
        case installed
        case notInstalled

        var label: String {
            switch self {
            case .checking: return "Checking..."
            case .installed: return "Installed"
            case .notInstalled: return "Not Installed"
            }
        }

        var color: String {
            switch self {
            case .checking: return "gray"
            case .installed: return "green"
            case .notInstalled: return "orange"
            }
        }
    }

    @Published var isInstalled = false
    @Published var isOllamaRunning = false
    @Published var latestSummary: String?
    @Published var isChecking = false
    @Published var isProcessing = false
    @Published var progressMessage = ""
    @Published var errorMessage: String?

    private let repoURL = "https://github.com/joshua-mullet-town/claude-summary-hooks.git"

    private var summaryHooksDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("code")
            .appendingPathComponent("claude-summary-hooks")
    }

    private var hooksDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/hooks")
    }

    private var claudeSettingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    private init() {
        // Do quick synchronous check for files first
        checkInstallStatusSync()

        // Then do slow checks in background (non-blocking)
        Task.detached(priority: .background) { [weak self] in
            await self?.checkSlowStatus()
        }
    }

    func checkStatus() {
        // Quick sync check
        checkInstallStatusSync()

        // Slow checks in background
        Task.detached(priority: .background) { [weak self] in
            await self?.checkSlowStatus()
        }
    }

    /// Quick synchronous check - just file existence
    private func checkInstallStatusSync() {
        let stopHookPath = hooksDirectory.appendingPathComponent("stop.py")
        let userPromptHookPath = hooksDirectory.appendingPathComponent("user_prompt_submit.py")

        let filesExist = FileManager.default.fileExists(atPath: stopHookPath.path) &&
                        FileManager.default.fileExists(atPath: userPromptHookPath.path)

        // Optimistic: if files exist, assume installed (settings check is slow)
        isInstalled = filesExist
    }

    /// Slow checks that run in background
    private func checkSlowStatus() async {
        // Check Ollama status (network call)
        await checkOllamaStatus()

        // Verify settings.json config
        let hooksConfigured = await isHookConfigured()

        // Update install status based on full check
        await MainActor.run {
            let stopHookPath = hooksDirectory.appendingPathComponent("stop.py")
            let userPromptHookPath = hooksDirectory.appendingPathComponent("user_prompt_submit.py")
            let filesExist = FileManager.default.fileExists(atPath: stopHookPath.path) &&
                            FileManager.default.fileExists(atPath: userPromptHookPath.path)
            isInstalled = filesExist && hooksConfigured
        }

        // Get latest summary (filesystem scan)
        await updateLatestSummary()
    }

    private func checkInstallStatus() async {
        // Check if the hook files exist
        let stopHookPath = hooksDirectory.appendingPathComponent("stop.py")
        let userPromptHookPath = hooksDirectory.appendingPathComponent("user_prompt_submit.py")

        let filesExist = FileManager.default.fileExists(atPath: stopHookPath.path) &&
                        FileManager.default.fileExists(atPath: userPromptHookPath.path)

        // Also check if hooks are configured in settings.json
        let hooksConfigured = await isHookConfigured()

        isInstalled = filesExist && hooksConfigured
    }

    private func isHookConfigured() async -> Bool {
        guard FileManager.default.fileExists(atPath: claudeSettingsPath.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: claudeSettingsPath)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hooks = json["hooks"] as? [String: Any],
               let stopHooks = hooks["Stop"] as? [[String: Any]] {
                // Check if any stop hook contains stop.py
                for hook in stopHooks {
                    if let hooksList = hook["hooks"] as? [[String: Any]] {
                        for h in hooksList {
                            if let command = h["command"] as? String,
                               command.contains("stop.py") {
                                return true
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error reading Claude settings: \(error)")
        }
        return false
    }

    func checkOllamaStatus() async {
        let process = Process()
        process.launchPath = "/usr/bin/curl"
        process.arguments = ["-s", "--connect-timeout", "2", "--max-time", "3", "http://localhost:11434/api/tags"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0,
               let data = try? pipe.fileHandleForReading.readToEnd(),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if phi3:3.8b model is available
                if let models = json["models"] as? [[String: Any]] {
                    isOllamaRunning = models.contains { model in
                        if let name = model["name"] as? String {
                            return name.hasPrefix("phi3") || name.contains("phi3:3.8b")
                        }
                        return false
                    }
                } else {
                    isOllamaRunning = false
                }
            } else {
                isOllamaRunning = false
            }
        } catch {
            isOllamaRunning = false
        }
    }

    func installHooks() async throws {
        isProcessing = true
        errorMessage = nil

        do {
            // Step 1: Check for jq
            progressMessage = "Checking dependencies..."
            let jqCheck = try await runCommand("/usr/bin/which", arguments: ["jq"])
            if jqCheck.isEmpty {
                errorMessage = "jq is required. Run: brew install jq"
                isProcessing = false
                return
            }

            // Step 2: Clone or update repo
            let codeDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code")

            // Create ~/code if it doesn't exist
            if !FileManager.default.fileExists(atPath: codeDir.path) {
                try FileManager.default.createDirectory(at: codeDir, withIntermediateDirectories: true)
            }

            if FileManager.default.fileExists(atPath: summaryHooksDir.path) {
                progressMessage = "Updating claude-summary-hooks..."
                _ = try await runCommand("/usr/bin/git", arguments: ["-C", summaryHooksDir.path, "pull"])
            } else {
                progressMessage = "Cloning claude-summary-hooks..."
                _ = try await runCommand("/usr/bin/git", arguments: ["clone", repoURL, summaryHooksDir.path])
            }

            // Step 3: Run install script
            progressMessage = "Running installer..."
            let installScript = summaryHooksDir.appendingPathComponent("install.sh")
            _ = try await runCommand("/bin/bash", arguments: [installScript.path])

            progressMessage = "Done!"
            await checkInstallStatus()
            await checkOllamaStatus()

        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }

    func uninstallHooks() async throws {
        isProcessing = true
        errorMessage = nil
        progressMessage = "Removing summary hooks..."

        do {
            // Run uninstall script if it exists
            let uninstallScript = summaryHooksDir.appendingPathComponent("uninstall.sh")
            if FileManager.default.fileExists(atPath: uninstallScript.path) {
                _ = try await runCommand("/bin/bash", arguments: [uninstallScript.path])
            } else {
                // Manual removal if no uninstall script
                let stopHookPath = hooksDirectory.appendingPathComponent("stop.py")
                let userPromptHookPath = hooksDirectory.appendingPathComponent("user_prompt_submit.py")

                try? FileManager.default.removeItem(at: stopHookPath)
                try? FileManager.default.removeItem(at: userPromptHookPath)

                // Remove claude-summary command
                let commandPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local/bin/claude-summary")
                try? FileManager.default.removeItem(at: commandPath)
            }

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Uninstall failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }

    func updateLatestSummary() async {
        // Skip the expensive directory scan - just check current working directory
        // Users can run `claude-summary` command for live viewing

        // Try to find summary in whisper-village project (current dev context)
        let knownPaths = [
            FileManager.default.currentDirectoryPath,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("code/whisper-village").path
        ]

        for basePath in knownPaths {
            let summaryPath = URL(fileURLWithPath: basePath)
                .appendingPathComponent(".claude/SUMMARY.txt")

            if let content = try? String(contentsOf: summaryPath) {
                await MainActor.run {
                    latestSummary = content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return
            }
        }
    }

    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: command)
            task.arguments = arguments

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if task.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "SummaryHookManager",
                        code: Int(task.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Command failed" : output]
                    ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
