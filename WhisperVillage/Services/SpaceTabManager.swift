import Foundation
import AppKit

// MARK: - Private API Bridge for macOS Spaces

/// Get the default Core Graphics connection
@_silgen_name("_CGSDefaultConnection")
func CGSDefaultConnection() -> Int32

/// Get the active space ID for a connection
@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ connection: Int32) -> Int

// MARK: - Space Tab Binding Model

/// Represents a binding between a macOS Space and an iTerm2 tab
struct SpaceTabBinding: Codable, Identifiable {
    let spaceID: Int
    let tabIndex: Int
    let tabName: String
    let createdAt: Date

    var id: Int { spaceID }
}

// MARK: - Space Tab Manager

/// Manages bindings between macOS Spaces and iTerm2 tabs
/// When user swipes to a Space, automatically switches to the linked iTerm2 tab
class SpaceTabManager: ObservableObject {
    static let shared = SpaceTabManager()

    /// All current space-to-tab bindings
    @Published var bindings: [Int: SpaceTabBinding] = [:]

    /// Whether the feature is enabled
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "SpaceTabBindingEnabled")
            if isEnabled {
                startListening()
            } else {
                stopListening()
            }
        }
    }

    /// Current space ID (for display)
    @Published var currentSpaceID: Int = 0

    private var spaceChangeObserver: Any?
    private let bindingsKey = "SpaceTabBindings"

    private init() {
        loadBindings()
        isEnabled = UserDefaults.standard.bool(forKey: "SpaceTabBindingEnabled")
        currentSpaceID = getCurrentSpaceID()

        if isEnabled {
            startListening()
        }
    }

    // MARK: - Space Detection (Private API)

    /// Get the current macOS Space ID using private API
    func getCurrentSpaceID() -> Int {
        let connection = CGSDefaultConnection()
        let spaceID = CGSGetActiveSpace(connection)
        return spaceID
    }

    // MARK: - iTerm2 AppleScript Helpers

    /// Get current iTerm2 tab info (index and name)
    func getCurrentiTermTab() -> (index: Int, name: String)? {
        // Note: iTerm2's "index of current tab" doesn't work directly,
        // so we iterate through tabs to find the current one's position
        let script = """
        tell application "iTerm2"
            if (count of windows) = 0 then
                return "NO_WINDOW"
            end if
            tell current window
                set tabList to tabs
                set currentT to current tab
                set tabIdx to 0
                repeat with i from 1 to count of tabList
                    if item i of tabList is currentT then
                        set tabIdx to i
                        exit repeat
                    end if
                end repeat
                set sessionName to name of current session of currentT
                return (tabIdx as string) & "|" & sessionName
            end tell
        end tell
        """

        guard let result = runAppleScript(script) else {
            StreamingLogger.shared.log("SpaceTabManager: Failed to get iTerm2 tab info")
            return nil
        }

        if result == "NO_WINDOW" {
            StreamingLogger.shared.log("SpaceTabManager: No iTerm2 window open")
            return nil
        }

        let parts = result.split(separator: "|", maxSplits: 1)
        guard parts.count >= 1, let index = Int(parts[0]) else {
            StreamingLogger.shared.log("SpaceTabManager: Failed to parse iTerm2 response: \(result)")
            return nil
        }

        let name = parts.count > 1 ? String(parts[1]) : "Tab \(index)"
        return (index, name)
    }

    /// Switch iTerm2 to a specific tab by index
    func switchToiTermTab(index: Int) -> Bool {
        let script = """
        tell application "iTerm2"
            if (count of windows) = 0 then
                return "NO_WINDOW"
            end if
            tell current window
                if \(index) > (count of tabs) then
                    return "TAB_NOT_FOUND"
                end if
                select tab \(index)
            end tell
            return "OK"
        end tell
        """

        guard let result = runAppleScript(script) else {
            StreamingLogger.shared.log("SpaceTabManager: Failed to switch iTerm2 tab")
            return false
        }

        if result == "NO_WINDOW" {
            StreamingLogger.shared.log("SpaceTabManager: No iTerm2 window to switch tabs")
            return false
        }

        if result == "TAB_NOT_FOUND" {
            StreamingLogger.shared.log("SpaceTabManager: Tab \(index) not found in iTerm2")
            return false
        }

        StreamingLogger.shared.log("SpaceTabManager: Switched to iTerm2 tab \(index)")
        return true
    }

    /// Check if iTerm2 is running
    func isiTermRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.googlecode.iterm2" }
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)

        if let error = error {
            StreamingLogger.shared.log("SpaceTabManager: AppleScript error: \(error)")
            return nil
        }

        return result.stringValue
    }

    // MARK: - Binding Management

    /// Link the current Space to the current iTerm2 tab
    func linkCurrentSpaceAndTab() -> Bool {
        guard isiTermRunning() else {
            StreamingLogger.shared.log("SpaceTabManager: iTerm2 not running")
            return false
        }

        guard let tabInfo = getCurrentiTermTab() else {
            return false
        }

        let spaceID = getCurrentSpaceID()

        let binding = SpaceTabBinding(
            spaceID: spaceID,
            tabIndex: tabInfo.index,
            tabName: tabInfo.name,
            createdAt: Date()
        )

        bindings[spaceID] = binding
        saveBindings()

        StreamingLogger.shared.log("SpaceTabManager: Linked Space \(spaceID) to Tab '\(tabInfo.name)' (index \(tabInfo.index))")
        return true
    }

    /// Remove a specific binding
    func removeBinding(spaceID: Int) {
        bindings.removeValue(forKey: spaceID)
        saveBindings()
        StreamingLogger.shared.log("SpaceTabManager: Removed binding for Space \(spaceID)")
    }

    /// Clear all bindings
    func resetAllBindings() {
        bindings.removeAll()
        saveBindings()
        StreamingLogger.shared.log("SpaceTabManager: Reset all bindings")
    }

    /// Check if current space has a binding
    var hasBindingForCurrentSpace: Bool {
        bindings[currentSpaceID] != nil
    }

    // MARK: - Space Change Listener

    private func startListening() {
        guard spaceChangeObserver == nil else { return }

        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        }

        StreamingLogger.shared.log("SpaceTabManager: Started listening for space changes")
    }

    private func stopListening() {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
            StreamingLogger.shared.log("SpaceTabManager: Stopped listening for space changes")
        }
    }

    private func handleSpaceChange() {
        let newSpaceID = getCurrentSpaceID()
        currentSpaceID = newSpaceID

        StreamingLogger.shared.log("SpaceTabManager: Space changed to \(newSpaceID)")

        // Check if we have a binding for this space
        guard let binding = bindings[newSpaceID] else {
            StreamingLogger.shared.log("SpaceTabManager: No binding for Space \(newSpaceID)")
            return
        }

        // Switch to the linked iTerm2 tab
        StreamingLogger.shared.log("SpaceTabManager: Switching to Tab '\(binding.tabName)' (index \(binding.tabIndex))")
        _ = switchToiTermTab(index: binding.tabIndex)
    }

    // MARK: - Persistence

    private func saveBindings() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Array(bindings.values)) {
            UserDefaults.standard.set(data, forKey: bindingsKey)
        }
    }

    private func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: bindingsKey) else { return }
        let decoder = JSONDecoder()
        if let savedBindings = try? decoder.decode([SpaceTabBinding].self, from: data) {
            bindings = Dictionary(uniqueKeysWithValues: savedBindings.map { ($0.spaceID, $0) })
            StreamingLogger.shared.log("SpaceTabManager: Loaded \(bindings.count) bindings")
        }
    }

    deinit {
        stopListening()
    }
}
