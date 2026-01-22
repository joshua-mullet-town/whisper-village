import SwiftUI

// MARK: - Claude Code Section

struct ClaudeCodeSection: View {
    @StateObject private var goalModeManager = GoalModeManager()
    @StateObject private var broncoBrowserManager = BroncoBrowserManager()
    @StateObject private var worktreeManager = WorktreeCommandManager()
    @StateObject private var summaryHookManager = SummaryHookManager.shared

    var body: some View {
        SettingsSection(
            icon: "terminal.fill",
            title: "Claude Code",
            subtitle: "Developer tools and integrations"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Goal Mode
                GoalModeRow(manager: goalModeManager)

                Divider()

                // Session Summaries
                SummaryHookRow(manager: summaryHookManager)

                Divider()

                // Worktree Command
                WorktreeCommandRow(manager: worktreeManager)

                Divider()

                // Bronco Browser
                BroncoBrowserRow(manager: broncoBrowserManager)
            }
        }
    }
}

// MARK: - Goal Mode Row

private struct GoalModeRow: View {
    @ObservedObject var manager: GoalModeManager
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Goal Mode")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        StatusBadge(status: manager.status)

                        Button(action: { showingInfo.toggle() }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                            GoalModeInfoPopover()
                        }
                    }

                    Text("Autonomous goal-driven loops for Claude Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                ActionButton(manager: manager)
            }

            if manager.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(manager.progressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = manager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if manager.status == .installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Type /goal in Claude Code to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: GoalModeManager.InstallStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    @ObservedObject var manager: GoalModeManager

    var body: some View {
        Button(action: {
            Task {
                switch manager.status {
                case .notInstalled:
                    await manager.install()
                case .installed:
                    await manager.uninstall()
                case .checking:
                    break
                }
            }
        }) {
            HStack(spacing: 4) {
                if manager.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: manager.status == .installed ? "trash" : "arrow.down.circle")
                        .font(.system(size: 11))
                }
                Text(manager.status == .installed ? "Remove" : "Install")
                    .font(.subheadline)
            }
            .frame(width: 80)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(manager.isProcessing || manager.status == .checking)
    }
}

// MARK: - Goal Mode Info Popover

private struct GoalModeInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Goal Mode")
                    .font(.headline)
            }

            // What it does
            VStack(alignment: .leading, spacing: 6) {
                Text("What it does")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Lets Claude Code work autonomously toward a goal you define. Instead of stopping after each response, it keeps going until the goal is verified complete or it gets stuck.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // How to use
            VStack(alignment: .leading, spacing: 6) {
                Text("How to use")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("In Claude Code, type /goal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Describe what you want to accomplish")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Walk away - Claude will work until done")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Example
            VStack(alignment: .leading, spacing: 6) {
                Text("Example")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\"Fix all TypeScript errors in the project\"")
                        .font(.caption)
                        .italic()
                        .foregroundColor(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Claude will find errors, fix them one by one, run the build to verify, and only stop when the build passes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            // Safety note
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Safety: You set a max iteration limit. Claude marks itself \"stuck\" if it can't proceed, so you're always in control.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Goal Mode Manager

@MainActor
class GoalModeManager: ObservableObject {
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

        var color: Color {
            switch self {
            case .checking: return .gray
            case .installed: return .green
            case .notInstalled: return .orange
            }
        }
    }

    @Published var status: InstallStatus = .checking
    @Published var isProcessing = false
    @Published var progressMessage = ""
    @Published var errorMessage: String?

    private let repoURL = "https://github.com/joshua-mullet-town/goal-mode.git"
    private var goalModeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("code")
            .appendingPathComponent("goal-mode")
    }
    private var claudeSettingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
    }
    private var claudeCommandsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("commands")
    }

    init() {
        // Quick sync check first
        checkInstallStatusSync()

        // Slow check in background
        Task.detached(priority: .background) { [weak self] in
            await self?.checkInstallStatusAsync()
        }
    }

    /// Quick synchronous check - just file existence
    private func checkInstallStatusSync() {
        let commandInstalled = FileManager.default.fileExists(
            atPath: claudeCommandsDir.appendingPathComponent("goal.md").path
        )
        // Optimistic: if command file exists, assume installed
        status = commandInstalled ? .installed : .notInstalled
    }

    func checkInstallStatus() async {
        checkInstallStatusSync()
        await checkInstallStatusAsync()
    }

    /// Slow async check - reads settings.json
    private func checkInstallStatusAsync() async {
        let hookInstalled = await isHookInstalled()
        let commandInstalled = FileManager.default.fileExists(
            atPath: claudeCommandsDir.appendingPathComponent("goal.md").path
        )

        await MainActor.run {
            if hookInstalled && commandInstalled {
                status = .installed
            } else {
                status = .notInstalled
            }
        }
    }

    private func isHookInstalled() async -> Bool {
        guard FileManager.default.fileExists(atPath: claudeSettingsPath.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: claudeSettingsPath)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hooks = json["hooks"] as? [String: Any],
               let stopHooks = hooks["Stop"] as? [[String: Any]] {
                // Check if any stop hook contains goal-stop.sh
                for hook in stopHooks {
                    if let hooksList = hook["hooks"] as? [[String: Any]] {
                        for h in hooksList {
                            if let command = h["command"] as? String,
                               command.contains("goal-stop.sh") {
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

    func install() async {
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

            if FileManager.default.fileExists(atPath: goalModeDir.path) {
                progressMessage = "Updating goal-mode..."
                _ = try await runCommand("/usr/bin/git", arguments: ["-C", goalModeDir.path, "pull"])
            } else {
                progressMessage = "Cloning goal-mode..."
                _ = try await runCommand("/usr/bin/git", arguments: ["clone", repoURL, goalModeDir.path])
            }

            // Step 3: Run install script
            progressMessage = "Running installer..."
            let installScript = goalModeDir.appendingPathComponent("install.sh")
            _ = try await runCommand("/bin/bash", arguments: [installScript.path])

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }

    func uninstall() async {
        isProcessing = true
        errorMessage = nil
        progressMessage = "Removing goal-mode..."

        do {
            // Step 1: Remove slash command
            let commandPath = claudeCommandsDir.appendingPathComponent("goal.md")
            if FileManager.default.fileExists(atPath: commandPath.path) {
                try FileManager.default.removeItem(at: commandPath)
            }

            // Step 2: Remove hook from settings.json
            if FileManager.default.fileExists(atPath: claudeSettingsPath.path) {
                let data = try Data(contentsOf: claudeSettingsPath)
                if var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   var hooks = json["hooks"] as? [String: Any] {
                    // Remove Stop hooks that contain goal-stop.sh
                    if var stopHooks = hooks["Stop"] as? [[String: Any]] {
                        stopHooks = stopHooks.filter { hook in
                            if let hooksList = hook["hooks"] as? [[String: Any]] {
                                return !hooksList.contains { h in
                                    if let command = h["command"] as? String {
                                        return command.contains("goal-stop.sh")
                                    }
                                    return false
                                }
                            }
                            return true
                        }

                        if stopHooks.isEmpty {
                            hooks.removeValue(forKey: "Stop")
                        } else {
                            hooks["Stop"] = stopHooks
                        }
                    }

                    if hooks.isEmpty {
                        json.removeValue(forKey: "hooks")
                    } else {
                        json["hooks"] = hooks
                    }

                    let newData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
                    try newData.write(to: claudeSettingsPath)
                }
            }

            // Step 3: Optionally remove the cloned repo (keep it for now, user can delete manually)
            // try FileManager.default.removeItem(at: goalModeDir)

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Uninstall failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
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
                        domain: "GoalModeManager",
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

// MARK: - Bronco Browser Row

private struct BroncoBrowserRow: View {
    @ObservedObject var manager: BroncoBrowserManager
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Bronco Browser")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        BroncoStatusBadge(status: manager.status)

                        Button(action: { showingInfo.toggle() }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                            BroncoBrowserInfoPopover()
                        }
                    }

                    Text("Browser automation with your real Chrome session")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                BroncoActionButton(manager: manager)
            }

            if manager.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(manager.progressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = manager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if manager.status == .installed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("MCP server configured - restart Claude Code to activate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("You'll also need the Chrome extension - see info for details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Bronco Status Badge

private struct BroncoStatusBadge: View {
    let status: BroncoBrowserManager.InstallStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Bronco Action Button

private struct BroncoActionButton: View {
    @ObservedObject var manager: BroncoBrowserManager

    var body: some View {
        Button(action: {
            Task {
                switch manager.status {
                case .notInstalled:
                    await manager.install()
                case .installed:
                    await manager.uninstall()
                case .checking:
                    break
                }
            }
        }) {
            HStack(spacing: 4) {
                if manager.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: manager.status == .installed ? "trash" : "arrow.down.circle")
                        .font(.system(size: 11))
                }
                Text(manager.status == .installed ? "Remove" : "Install")
                    .font(.subheadline)
            }
            .frame(width: 80)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(manager.isProcessing || manager.status == .checking)
    }
}

// MARK: - Bronco Browser Info Popover

private struct BroncoBrowserInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Bronco Browser")
                    .font(.headline)
            }

            // What it does
            VStack(alignment: .leading, spacing: 6) {
                Text("What it does")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Lets Claude Code control your real Chrome browser - with all your cookies, logins, and sessions intact. Unlike Playwright which uses an isolated browser, Bronco uses your actual browser.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Two parts required
            VStack(alignment: .leading, spacing: 6) {
                Text("Two parts required")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "1.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MCP Server (this install)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Adds bronco-browser to Claude Code's MCP config")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "2.circle.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chrome Extension (separate)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Download from GitHub releases and load unpacked")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            // How to use
            VStack(alignment: .leading, spacing: 6) {
                Text("How to use")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Install MCP server here, then restart Claude Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Install Chrome extension from GitHub")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Click Bronco icon on tabs you want to automate")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("4.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Ask Claude to interact with your browser")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Parallel testing
            VStack(alignment: .leading, spacing: 6) {
                Text("Parallel Testing")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Run npx bronco-browser init in any project to set up parallel browser tests. Then use /bronco-run-tests to run all tests simultaneously.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Link
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundColor(.blue)
                Link("github.com/joshua-mullet-town/bronco-browser",
                     destination: URL(string: "https://github.com/joshua-mullet-town/bronco-browser")!)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Bronco Browser Manager

@MainActor
class BroncoBrowserManager: ObservableObject {
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

        var color: Color {
            switch self {
            case .checking: return .gray
            case .installed: return .green
            case .notInstalled: return .orange
            }
        }
    }

    @Published var status: InstallStatus = .checking
    @Published var isProcessing = false
    @Published var progressMessage = ""
    @Published var errorMessage: String?

    private var claudeJsonPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
    }

    init() {
        // Sync check - isMcpServerInstalled reads a small JSON file, fast enough
        let mcpInstalled = isMcpServerInstalled()
        status = mcpInstalled ? .installed : .notInstalled
    }

    func checkInstallStatus() async {
        let mcpInstalled = isMcpServerInstalled()
        status = mcpInstalled ? .installed : .notInstalled
    }

    private func isMcpServerInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: claudeJsonPath.path) else {
            return false
        }

        do {
            let data = try Data(contentsOf: claudeJsonPath)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let mcpServers = json["mcpServers"] as? [String: Any] {
                return mcpServers["bronco-browser"] != nil
            }
        } catch {
            print("Error reading Claude config: \(error)")
        }
        return false
    }

    func install() async {
        isProcessing = true
        errorMessage = nil
        progressMessage = "Configuring MCP server..."

        do {
            // Read or create ~/.claude.json
            var config: [String: Any] = [:]

            if FileManager.default.fileExists(atPath: claudeJsonPath.path) {
                let data = try Data(contentsOf: claudeJsonPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    config = json
                }
            }

            // Ensure mcpServers exists
            var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]

            // Add bronco-browser
            mcpServers["bronco-browser"] = [
                "command": "npx",
                "args": ["-y", "bronco-browser", "serve"]
            ]

            config["mcpServers"] = mcpServers

            // Write back
            let newData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: claudeJsonPath)

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }

    func uninstall() async {
        isProcessing = true
        errorMessage = nil
        progressMessage = "Removing MCP server..."

        do {
            guard FileManager.default.fileExists(atPath: claudeJsonPath.path) else {
                await checkInstallStatus()
                isProcessing = false
                return
            }

            let data = try Data(contentsOf: claudeJsonPath)
            guard var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                await checkInstallStatus()
                isProcessing = false
                return
            }

            // Remove bronco-browser from mcpServers
            if var mcpServers = config["mcpServers"] as? [String: Any] {
                mcpServers.removeValue(forKey: "bronco-browser")

                if mcpServers.isEmpty {
                    config.removeValue(forKey: "mcpServers")
                } else {
                    config["mcpServers"] = mcpServers
                }
            }

            // Write back
            let newData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try newData.write(to: claudeJsonPath)

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Uninstall failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }
}

// MARK: - Worktree Command Row

private struct WorktreeCommandRow: View {
    @ObservedObject var manager: WorktreeCommandManager
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Worktree Command")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        WorktreeStatusBadge(status: manager.status)

                        Button(action: { showingInfo.toggle() }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                            WorktreeInfoPopover()
                        }
                    }

                    Text("Create git worktrees with /worktree in Claude Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                WorktreeCommandButton(manager: manager)
            }

            if manager.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(manager.progressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = manager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if manager.status == .installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Type /worktree branch-name in Claude Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Worktree Status Badge

private struct WorktreeStatusBadge: View {
    let status: WorktreeCommandManager.InstallStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Worktree Command Button

private struct WorktreeCommandButton: View {
    @ObservedObject var manager: WorktreeCommandManager

    var body: some View {
        Button(action: {
            Task {
                switch manager.status {
                case .notInstalled:
                    await manager.install()
                case .installed:
                    await manager.uninstall()
                case .checking:
                    break
                }
            }
        }) {
            HStack(spacing: 4) {
                if manager.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: manager.status == .installed ? "trash" : "arrow.down.circle")
                        .font(.system(size: 11))
                }
                Text(manager.status == .installed ? "Remove" : "Install")
                    .font(.subheadline)
            }
            .frame(width: 80)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(manager.isProcessing || manager.status == .checking)
    }
}

// MARK: - Worktree Info Popover

private struct WorktreeInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Worktree Command")
                    .font(.headline)
            }

            // What it does
            VStack(alignment: .leading, spacing: 6) {
                Text("What it does")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Adds a /worktree slash command to Claude Code that creates git worktrees for parallel development. Work on multiple branches simultaneously without context switching.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // How to use
            VStack(alignment: .leading, spacing: 6) {
                Text("How to use")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("In Claude Code, type /worktree feature-name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Claude creates a worktree at ~/.worktrees/")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Copy the cd command and start a new terminal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Example
            VStack(alignment: .leading, spacing: 6) {
                Text("Example")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("/worktree feature/user-auth")
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Creates ~/.worktrees/myproject/feature-user-auth/ with .env files copied")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            // Manage worktrees
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Manage worktrees from the Whisper Village menu bar - copy paths, open in Finder, or delete.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Worktree Command Manager

@MainActor
class WorktreeCommandManager: ObservableObject {
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

        var color: Color {
            switch self {
            case .checking: return .gray
            case .installed: return .green
            case .notInstalled: return .orange
            }
        }
    }

    @Published var status: InstallStatus = .checking
    @Published var isProcessing = false
    @Published var progressMessage = ""
    @Published var errorMessage: String?

    private var claudeCommandsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("commands")
    }

    private var commandPath: URL {
        claudeCommandsDir.appendingPathComponent("worktree.md")
    }

    init() {
        // Sync check - just file existence, very fast
        status = FileManager.default.fileExists(atPath: commandPath.path) ? .installed : .notInstalled
    }

    func checkInstallStatus() async {
        status = FileManager.default.fileExists(atPath: commandPath.path) ? .installed : .notInstalled
    }

    func install() async {
        isProcessing = true
        errorMessage = nil
        progressMessage = "Installing slash command..."

        do {
            // Create commands directory if needed
            if !FileManager.default.fileExists(atPath: claudeCommandsDir.path) {
                try FileManager.default.createDirectory(at: claudeCommandsDir, withIntermediateDirectories: true)
            }

            // Write the slash command file
            try worktreeCommandContent.write(to: commandPath, atomically: true, encoding: .utf8)

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Install failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }

    func uninstall() async {
        isProcessing = true
        errorMessage = nil
        progressMessage = "Removing slash command..."

        do {
            if FileManager.default.fileExists(atPath: commandPath.path) {
                try FileManager.default.removeItem(at: commandPath)
            }

            progressMessage = "Done!"
            await checkInstallStatus()

        } catch {
            errorMessage = "Uninstall failed: \(error.localizedDescription)"
        }

        isProcessing = false
        progressMessage = ""
    }

    // The slash command content embedded in the app
    private let worktreeCommandContent = """
# Worktree - Create a Git Worktree

You are creating a new git worktree for parallel development. The user has provided a branch name as an argument: `$ARGUMENTS`

## Your Task

Create a worktree in `~/.worktrees/<project-name>/<branch-name>/` and set it up for development.

## Steps

### 1. Validate Environment

First, confirm you're in a git repository:
```bash
git rev-parse --show-toplevel
```

If not in a git repo, stop and tell the user.

### 2. Extract Info

- **Project name**: The basename of the git root (e.g., `/Users/josh/code/mullet-town` → `mullet-town`)
- **Branch name**: Use `$ARGUMENTS` - sanitize it (replace spaces with hyphens, remove invalid chars)
- **Base branch**: Detect the default branch (main, master, etc.)

### 3. Create the Worktree

```bash
# Create directory structure
mkdir -p ~/.worktrees/<project-name>

# Create the worktree with a new branch
git worktree add ~/.worktrees/<project-name>/<branch-name> -b <branch-name>
```

If the branch already exists, use:
```bash
git worktree add ~/.worktrees/<project-name>/<branch-name> <branch-name>
```

### 4. Copy Environment Files

Find and copy all `.env*` files from the main repo to the worktree:
```bash
find . -maxdepth 2 -name ".env*" -type f
```

Copy each one to the same relative path in the worktree.

### 5. Create Metadata File

Create `~/.worktrees/<project-name>/<branch-name>/.worktree-meta.json`:
```json
{
  "project": "<project-name>",
  "branch": "<branch-name>",
  "baseBranch": "<base-branch>",
  "mainRepoPath": "<full-path-to-main-repo>",
  "created": "<ISO-8601-timestamp>"
}
```

### 6. Output the Command

After everything is set up, output a clear message:

```
✅ Worktree created!

📁 Location: ~/.worktrees/<project-name>/<branch-name>
🌿 Branch: <branch-name> (from <base-branch>)

To start working:
cd ~/.worktrees/<project-name>/<branch-name>
```

## Important Notes

- Do NOT copy `node_modules` - it's too slow and the user can run `npm install` if needed
- DO copy `.env` files - these are small and essential
- The worktree location is `~/.worktrees/` (global, outside the repo) to avoid gitignore issues
- If the branch name has slashes (like `feature/auth`), convert them to hyphens for the directory name (like `feature-auth`)

## Error Handling

- If worktree already exists at that path, tell the user and show the `cd` command
- If branch already exists but isn't checked out anywhere, offer to use it
- If git worktree command fails, show the error and suggest fixes

## Example

User runs: `/worktree feature/user-auth`

You:
1. Detect project is `mullet-town`
2. Sanitize branch to directory name: `feature-user-auth`
3. Create worktree at `~/.worktrees/mullet-town/feature-user-auth/`
4. Create branch `feature/user-auth` from `main`
5. Copy `.env` files
6. Create metadata
7. Output the `cd` command
"""
}

// MARK: - Summary Hook Row

private struct SummaryHookRow: View {
    @ObservedObject var manager: SummaryHookManager
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Session Summaries")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        StatusBadge(status: manager.isInstalled ? .installed : .notInstalled)

                        Button(action: { showingInfo.toggle() }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                            SummaryHookInfoPopover()
                        }
                    }

                    Text("Auto-generates 2-line summaries of Claude Code sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                SummaryHookActionButton(manager: manager)
            }

            if manager.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(manager.progressMessage.isEmpty ? "Working..." : manager.progressMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if manager.isInstalled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("Ready! Summaries will appear in .claude/SUMMARY.txt after Claude Code sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Run 'claude-summary' in any project for live streaming summaries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Session dots toggle
                SessionDotsToggle()
            }

            // Show latest summary if available
            if let summary = manager.latestSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Summary:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(summary)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                        .lineLimit(4)
                }
            }
        }
    }
}

// MARK: - Summary Hook Action Button

private struct SummaryHookActionButton: View {
    @ObservedObject var manager: SummaryHookManager

    var body: some View {
        Button(action: {
            Task {
                if manager.isInstalled {
                    try? await manager.uninstallHooks()
                } else {
                    try? await manager.installHooks()
                }
            }
        }) {
            HStack(spacing: 4) {
                if manager.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: manager.isInstalled ? "trash" : "arrow.down.circle")
                        .font(.system(size: 11))
                }
                Text(manager.isInstalled ? "Remove" : "Install")
                    .font(.subheadline)
            }
            .frame(width: 80)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(manager.isProcessing)
    }
}

// MARK: - Summary Hook Info Popover

private struct SummaryHookInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Session Summaries")
                    .font(.headline)
            }

            // What it does
            VStack(alignment: .leading, spacing: 6) {
                Text("What it does")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Automatically generates 2-line summaries of your Claude Code sessions using Claude Haiku. Helps you track what you accomplished across coding sessions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // How it works
            VStack(alignment: .leading, spacing: 6) {
                Text("How it works")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Captures your prompts and Claude's responses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Reads project context (CLAUDE.md, PLAN.md)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Uses Claude Haiku to generate summary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("4.")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Saves to .claude/SUMMARY.txt in your project")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Example output
            VStack(alignment: .leading, spacing: 6) {
                Text("Example Output")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("USER asked: Help implement user authentication with JWT tokens")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)

                    Text("AGENT: Created JWT auth system with login/signup routes and token validation")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }

            Divider()

            // Usage
            VStack(alignment: .leading, spacing: 6) {
                Text("Viewing Summaries")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Summaries appear in Whisper Village settings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Run 'claude-summary' for live streaming view")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                        Text("Files saved to .claude/SUMMARY.txt in each project")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Session Dots Toggle

private struct SessionDotsToggle: View {
    @StateObject private var sessionManager = ClaudeSessionManager.shared

    var body: some View {
        Divider()
            .padding(.vertical, 4)

        Toggle(isOn: $sessionManager.isEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("Session Status Dots")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text("Show iTerm tab status dots below the notch")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)

        if sessionManager.isEnabled && !sessionManager.iTermTabs.isEmpty {
            HStack(spacing: 6) {
                Text("Active tabs:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(sessionManager.iTermTabs) { tab in
                    HStack(spacing: 2) {
                        Circle()
                            .fill(colorForStatus(sessionManager.statusForTab(tab.index)))
                            .frame(width: 6, height: 6)
                        Text(tab.projectName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        // Summary Panel Toggle
        Divider()
            .padding(.vertical, 4)

        Toggle(isOn: $sessionManager.isSummaryPanelEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "tv")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("Summary Panel")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                Text("Show session summary mini-TV below status dots")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func colorForStatus(_ status: ClaudeSessionStatus) -> Color {
        switch status {
        case .working: return .yellow
        case .waiting: return .green
        case .idle: return .gray.opacity(0.5)
        }
    }
}
