import Foundation
import AppKit

/// Lightweight Homestead manager - just status checking and terminal launching
/// All the heavy lifting (git, npm, server management) is done by the CLI script
class HomesteadManager: ObservableObject {
    static let shared = HomesteadManager()

    @Published var isServerRunning = false

    private var statusTimer: Timer?

    /// Port to check (reads from UserDefaults) - uses different key to not conflict with old settings
    var port: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: "homesteadManagedPort")
        return stored > 0 ? UInt16(stored) : 3007
    }

    private init() {
        // Set default port if not set (3007 to avoid conflict with dev instances)
        if UserDefaults.standard.integer(forKey: "homesteadManagedPort") == 0 {
            UserDefaults.standard.set(3007, forKey: "homesteadManagedPort")
        }

        // Clear old keys if they exist
        UserDefaults.standard.removeObject(forKey: "homesteadPort")

        // Check status async
        checkStatusAsync()

        // Poll every 5 seconds (lightweight TCP check)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkStatusAsync()
        }
    }

    // MARK: - Public Methods

    /// Launch the Homestead CLI in Terminal
    func launchTerminal() {
        let scriptPath = Bundle.main.resourcePath?
            .replacingOccurrences(of: "/Contents/Resources", with: "")
            .replacingOccurrences(of: "/Whisper Village Dev.app", with: "")
            .replacingOccurrences(of: "/Whisper Village.app", with: "")
            .appending("/scripts/homestead") ?? ""

        // Try to find the script in various locations
        let possiblePaths = [
            scriptPath,
            FileManager.default.homeDirectoryForCurrentUser.path + "/code/whisper-village/scripts/homestead",
            "/usr/local/bin/homestead"
        ]

        var finalPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                finalPath = path
                break
            }
        }

        guard let path = finalPath else {
            // Script not found - show error
            let alert = NSAlert()
            alert.messageText = "Homestead CLI Not Found"
            alert.informativeText = "The homestead script could not be found. Please ensure it's installed at ~/code/whisper-village/scripts/homestead"
            alert.runModal()
            return
        }

        // Launch Terminal with the script
        let script = """
        tell application "Terminal"
            activate
            do script "HOMESTEAD_PORT=\(port) '\(path)'"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
    }

    /// Open Homestead in browser
    func openInBrowser() {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Copy URL to clipboard
    func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port)", forType: .string)
    }

    /// Force a status refresh
    func refreshStatus() {
        checkStatusAsync()
    }

    // MARK: - Private Methods

    private func checkStatusAsync() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let running = self.isPortOpen(self.port)
            DispatchQueue.main.async {
                self.isServerRunning = running
            }
        }
    }

    /// Simple TCP port check - no process spawning
    private func isPortOpen(_ port: UInt16) -> Bool {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = port.bigEndian
        sin.sin_addr.s_addr = inet_addr("127.0.0.1")

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Set non-blocking
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let result = withUnsafePointer(to: &sin) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 {
            return true
        } else if errno == EINPROGRESS {
            var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
            let pollResult = poll(&pollFd, 1, 100) // 100ms timeout
            return pollResult > 0 && (pollFd.revents & Int16(POLLOUT)) != 0
        }

        return false
    }
}
