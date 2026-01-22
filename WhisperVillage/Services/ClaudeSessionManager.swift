import Foundation
import AppKit

/// Represents the status of a Claude Code session
enum ClaudeSessionStatus: String, Codable {
    case working    // Session active, agent is processing
    case waiting    // Stop hook fired, agent done, waiting for user
    case idle       // No active session
}

/// Information about a Claude Code session
struct ClaudeSession: Identifiable, Codable {
    let sessionId: String
    let cwd: String
    var status: ClaudeSessionStatus
    var summary: String?  // Raw summary (legacy format)
    var userSummary: String?  // Structured: what the user asked
    var agentSummary: String?  // Structured: what the agent did
    var updatedAt: String  // ISO-8601 string from Python hooks

    var id: String { sessionId }

    /// Project name (last component of cwd)
    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Returns true if we have structured summary data
    var hasStructuredSummary: Bool {
        userSummary != nil || agentSummary != nil
    }
}

/// Information about an iTerm tab
struct ITermTab: Identifiable {
    let index: Int
    let tty: String
    let name: String
    let cwd: String

    var id: Int { index }

    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// Manages Claude Code session state and iTerm tab mapping
/// Watches ~/.claude/sessions/ for session files and polls iTerm for tab info
@MainActor
class ClaudeSessionManager: ObservableObject {
    static let shared: ClaudeSessionManager = {
        let line = "[STATIC INIT] ClaudeSessionManager.shared being created\n"
        if let data = line.data(using: .utf8) {
            FileManager.default.createFile(atPath: "/tmp/claude-session-manager-debug.log", contents: data)
        }
        return ClaudeSessionManager()
    }()

    /// All known sessions, keyed by cwd
    @Published var sessions: [String: ClaudeSession] = [:]

    /// Current iTerm tabs with their working directories
    @Published var iTermTabs: [ITermTab] = []

    /// The currently selected/active iTerm tab index (1-based), or nil if unknown
    @Published var activeTabIndex: Int? = nil

    /// Whether the session dots feature is enabled
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "ClaudeSessionDotsEnabled")
            if isEnabled || isSummaryPanelEnabled {
                startWatching()
            } else {
                stopWatching()
            }
        }
    }

    /// Whether the summary panel (mini TV) is enabled
    @Published var isSummaryPanelEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isSummaryPanelEnabled, forKey: "ClaudeSummaryPanelEnabled")
            if isEnabled || isSummaryPanelEnabled {
                startWatching()
            } else {
                stopWatching()
            }
        }
    }

    private var sessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var spaceChangeObserver: NSObjectProtocol?

    /// Lock to serialize AppleScript execution - NSAppleScript is NOT thread-safe
    /// and will crash with EXC_BAD_ACCESS if called from multiple threads simultaneously
    private static let appleScriptLock = NSLock()

    /// Debug logging - set to true to enable verbose logging to /tmp/claude-session-manager-debug.log
    private let debugEnabled = false
    private let debugLogPath = "/tmp/claude-session-manager-debug.log"

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogPath) {
                if let handle = FileHandle(forWritingAtPath: debugLogPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: debugLogPath, contents: data)
            }
        }
    }

    private init() {
        // Clear old log
        try? FileManager.default.removeItem(atPath: debugLogPath)

        debugLog("INIT STARTED")
        isEnabled = UserDefaults.standard.bool(forKey: "ClaudeSessionDotsEnabled")
        isSummaryPanelEnabled = UserDefaults.standard.bool(forKey: "ClaudeSummaryPanelEnabled")
        debugLog("isEnabled = \(isEnabled), isSummaryPanelEnabled = \(isSummaryPanelEnabled)")

        // Create sessions directory if needed
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        debugLog("sessionsDir = \(sessionsDir.path)")

        if isEnabled || isSummaryPanelEnabled {
            debugLog("Starting watcher...")
            startWatching()
        } else {
            debugLog("Disabled, not starting watcher")
        }
        debugLog("INIT COMPLETE")
    }

    // MARK: - Public Interface

    /// Get the session status for a given tab index
    func statusForTab(_ tabIndex: Int) -> ClaudeSessionStatus {
        guard tabIndex > 0, tabIndex <= iTermTabs.count else {
            debugLog("statusForTab(\(tabIndex)) - invalid index, returning idle")
            return .idle
        }
        let tab = iTermTabs[tabIndex - 1]

        if let session = sessionForTab(tab) {
            debugLog("statusForTab(\(tabIndex)) - cwd: \(tab.cwd), status: \(session.status.rawValue)")
            return session.status
        }

        debugLog("statusForTab(\(tabIndex)) - no match for cwd: \(tab.cwd), returning idle")
        return .idle
    }

    /// Get the summary for a given tab index
    func summaryForTab(_ tabIndex: Int) -> String? {
        guard tabIndex > 0, tabIndex <= iTermTabs.count else { return nil }
        let tab = iTermTabs[tabIndex - 1]
        return sessionForTab(tab)?.summary
    }

    /// Get the full session for a given tab index (for structured summary access)
    func sessionForTabIndex(_ tabIndex: Int) -> ClaudeSession? {
        guard tabIndex > 0, tabIndex <= iTermTabs.count else { return nil }
        let tab = iTermTabs[tabIndex - 1]
        return sessionForTab(tab)
    }

    /// Get the updatedAt timestamp for a given tab index
    func updatedAtForTab(_ tabIndex: Int) -> Date? {
        guard tabIndex > 0, tabIndex <= iTermTabs.count else { return nil }
        let tab = iTermTabs[tabIndex - 1]
        guard let session = sessionForTab(tab) else { return nil }

        return parseISO8601Date(session.updatedAt)
    }

    /// Parse ISO-8601 date string, handling both milliseconds and microseconds
    /// Python outputs local time without timezone, so we parse as local
    private func parseISO8601Date(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current  // Python outputs local time

        // Try microseconds first (6 decimal places) - Python's default
        // Format: 2026-01-20T08:57:24.234764
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }

        // Try milliseconds (3 decimal places)
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }

        // Try without fractional seconds
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = dateFormatter.date(from: dateString) {
            return date
        }

        // Fallback to ISO8601DateFormatter
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            return date
        }

        // Try with milliseconds (3 decimal places)
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return dateFormatter.date(from: dateString)
    }

    /// Find the session for a tab (exact match or subdirectory match)
    /// When multiple sessions match (e.g., GiveGrove and GiveGrove/functions),
    /// prefer the most recently updated one
    private func sessionForTab(_ tab: ITermTab) -> ClaudeSession? {
        // Exact match first
        if let session = sessions[tab.cwd] {
            return session
        }

        // Subdirectory match - collect all matches
        var matches: [ClaudeSession] = []
        for (sessionCwd, session) in sessions {
            if tab.cwd.hasPrefix(sessionCwd + "/") || sessionCwd.hasPrefix(tab.cwd + "/") {
                matches.append(session)
            }
        }

        // If multiple matches, return the most recently updated one
        if matches.count > 1 {
            return matches.max { a, b in
                let dateA = parseISO8601Date(a.updatedAt) ?? .distantPast
                let dateB = parseISO8601Date(b.updatedAt) ?? .distantPast
                return dateA < dateB
            }
        }

        return matches.first
    }

    /// Force refresh of all data
    func refresh() {
        Task {
            await loadSessions()
            await refreshITermTabs()
        }
    }

    // MARK: - File Watching

    private func startWatching() {
        // Initial load
        refresh()

        // Watch sessions directory for changes
        setupFileWatcher()

        // Poll iTerm tabs and session files periodically (every 2 seconds)
        // Note: DispatchSource file watching on directories doesn't trigger when file contents change,
        // only when files are created/deleted. So we poll instead.
        // Run heavy I/O off main thread to avoid blocking UI/audio
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { [weak self] in
                await self?.pollInBackground()
            }
        }

        // Listen for Space changes - when user switches Spaces, check which iTerm tab is active
        setupSpaceChangeListener()
    }

    private func stopWatching() {
        fileWatcher?.cancel()
        fileWatcher = nil
        pollTimer?.invalidate()
        pollTimer = nil
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
    }

    private func setupSpaceChangeListener() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debugLog("Space changed - checking active iTerm tab")
            Task { @MainActor [weak self] in
                await self?.refreshActiveTab()
            }
        }
    }

    /// Refresh which iTerm tab is currently selected
    private func refreshActiveTab() async {
        let activeIndex = await getActiveTabIndexOffMain()
        activeTabIndex = activeIndex
        debugLog("Active tab index: \(activeIndex ?? -1)")
    }

    /// Get the currently selected iTerm tab index (off main thread)
    private nonisolated func getActiveTabIndexOffMain() async -> Int? {
        // Check if iTerm is running
        let isITermRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }
        guard isITermRunning else { return nil }

        // Query iTerm for the selected tab index
        let script = """
        tell application "iTerm2"
            if (count of windows) = 0 then
                return "NO_WINDOWS"
            end if
            tell first window
                set tabList to tabs
                repeat with i from 1 to count of tabList
                    if item i of tabList = current tab then
                        return i
                    end if
                end repeat
                return -1
            end tell
        end tell
        """

        guard let result = runAppleScriptSync(script),
              result != "NO_WINDOWS",
              let index = Int(result),
              index > 0 else {
            return nil
        }

        return index
    }

    private func setupFileWatcher() {
        let fd = open(sessionsDir.path, O_EVTONLY)
        guard fd >= 0 else {
            StreamingLogger.shared.log("ClaudeSessionManager: Could not open sessions dir for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                await self?.loadSessions()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileWatcher = source
    }

    // MARK: - Background Polling

    /// Performs all I/O off the main thread, then updates published properties on main
    private func pollInBackground() async {
        // Do file I/O off main thread
        let loadedSessions = await loadSessionsOffMain()
        let loadedTabs = await refreshITermTabsOffMain()
        let activeIndex = await getActiveTabIndexOffMain()

        // Update published properties on main thread (quick, no I/O)
        await MainActor.run {
            self.sessions = loadedSessions
            self.iTermTabs = loadedTabs
            self.activeTabIndex = activeIndex
        }
    }

    // MARK: - Session Loading

    private func loadSessions() async {
        let loaded = await loadSessionsOffMain()
        sessions = loaded
    }

    /// Load sessions off the main thread - returns the loaded sessions dictionary
    private nonisolated func loadSessionsOffMain() async -> [String: ClaudeSession] {
        var loadedSessions: [String: ClaudeSession] = [:]
        let sessionsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath.path) else {
            return loadedSessions
        }

        for file in files where file.hasSuffix(".json") {
            let filePath = sessionsPath.appendingPathComponent(file)
            do {
                let data = try Data(contentsOf: filePath)
                let session = try JSONDecoder().decode(ClaudeSession.self, from: data)
                loadedSessions[session.cwd] = session
            } catch {
                // Skip invalid files
            }
        }

        return loadedSessions
    }

    // MARK: - iTerm Tab Enumeration

    private func refreshITermTabs() async {
        let tabs = await refreshITermTabsOffMain()
        iTermTabs = tabs
    }

    /// Refresh iTerm tabs off the main thread - returns the loaded tabs array
    private nonisolated func refreshITermTabsOffMain() async -> [ITermTab] {
        // Check if iTerm is running (this is quick, fine to do here)
        let isITermRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }
        guard isITermRunning else { return [] }

        // Get tab info via AppleScript
        let script = """
        tell application "iTerm2"
            if (count of windows) = 0 then
                return "NO_WINDOWS"
            end if
            tell first window
                set tabList to tabs
                set output to ""
                repeat with i from 1 to count of tabList
                    set t to item i of tabList
                    set s to current session of t
                    set sessTTY to tty of s
                    set sessName to name of s
                    if i > 1 then
                        set output to output & "|"
                    end if
                    set output to output & i & "," & sessTTY & "," & sessName
                end repeat
                return output
            end tell
        end tell
        """

        guard let result = runAppleScriptSync(script), result != "NO_WINDOWS" else {
            return []
        }

        // Parse the result and get cwds
        var tabs: [ITermTab] = []
        let entries = result.split(separator: "|")

        for entry in entries {
            let parts = entry.split(separator: ",", maxSplits: 2)
            guard parts.count >= 2,
                  let index = Int(parts[0]) else { continue }

            let tty = String(parts[1])
            let name = parts.count > 2 ? String(parts[2]) : "Tab \(index)"

            // Get working directory for this TTY
            let cwd = getCwdForTTYSync(tty)

            tabs.append(ITermTab(index: index, tty: tty, name: name, cwd: cwd))
        }

        return tabs
    }

    private func getCwdForTTY(_ tty: String) -> String {
        getCwdForTTYSync(tty)
    }

    /// Sync version that can be called from nonisolated context
    private nonisolated func getCwdForTTYSync(_ tty: String) -> String {
        let ttyName = URL(fileURLWithPath: tty).lastPathComponent

        // Find the foreground process on this TTY
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-t", ttyName, "-o", "pid=,stat="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Find foreground process (stat contains '+')
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2 else { continue }
                let stat = String(parts[1])
                if stat.contains("+") {
                    let pid = String(parts[0])
                    return getCwdForPidSync(pid)
                }
            }
        } catch {
            // Silently ignore errors in background polling
        }

        return ""
    }

    private func getCwdForPid(_ pid: String) -> String {
        getCwdForPidSync(pid)
    }

    /// Sync version that can be called from nonisolated context
    private nonisolated func getCwdForPidSync(_ pid: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-p", pid, "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            for line in output.split(separator: "\n") {
                if line.hasPrefix("n") {
                    return String(line.dropFirst())
                }
            }
        } catch {
            // Silently ignore errors in background polling
        }

        return ""
    }

    private func runAppleScript(_ source: String) -> String? {
        runAppleScriptSync(source)
    }

    /// Sync version that can be called from nonisolated context
    /// Uses a lock to serialize AppleScript calls - NSAppleScript is NOT thread-safe
    private nonisolated func runAppleScriptSync(_ source: String) -> String? {
        // Serialize all AppleScript calls to prevent crashes
        ClaudeSessionManager.appleScriptLock.lock()
        defer { ClaudeSessionManager.appleScriptLock.unlock() }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)

        if error != nil {
            // Silently ignore AppleScript errors in background polling
            return nil
        }

        return result.stringValue
    }

    deinit {
        pollTimer?.invalidate()
        fileWatcher?.cancel()
    }
}
