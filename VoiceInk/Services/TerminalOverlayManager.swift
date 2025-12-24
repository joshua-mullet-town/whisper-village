import Foundation
import AppKit
import SwiftUI

/// Manages the floating terminal overlay that mirrors iTerm2 Claude Code sessions
@MainActor
class TerminalOverlayManager: ObservableObject {
    static let shared = TerminalOverlayManager()

    // MARK: - Published State
    @Published var isVisible = false
    @Published var sessions: [TerminalSession] = []
    @Published var selectedSession: TerminalSession?
    @Published var terminalContent: [String] = []
    @Published var opacity: Double = 0.85

    // MARK: - Private State
    private var overlayPanel: NSPanel?
    private var daemonProcess: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var pollingTimer: Timer?

    // Path to daemon
    private let daemonPath: String = {
        if let resourcePath = Bundle.main.resourcePath {
            return resourcePath + "/iterm2-bridge/daemon.py"
        }
        // Fallback for development
        return "/Users/joshuamullet/code/whisper-village/scripts/iterm2-bridge/daemon.py"
    }()

    private let pythonPath: String = {
        if let resourcePath = Bundle.main.resourcePath {
            return resourcePath + "/iterm2-bridge/venv/bin/python"
        }
        // Fallback for development
        return "/Users/joshuamullet/code/whisper-village/scripts/iterm2-bridge/venv/bin/python"
    }()

    private init() {}

    // MARK: - Public API

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else { return }

        startDaemon()
        createOverlayPanel()
        isVisible = true

        // Refresh sessions
        refreshSessions()
    }

    func hide() {
        guard isVisible else { return }

        stopPolling()
        overlayPanel?.orderOut(nil)
        overlayPanel = nil
        isVisible = false
    }

    func selectSession(_ session: TerminalSession) {
        selectedSession = session
        sendCommand(["cmd": "select_session", "session_id": session.id])
        startPolling()
    }

    func sendInput(_ text: String) {
        guard selectedSession != nil else { return }
        sendCommand(["cmd": "send_input", "text": text + "\n"])
    }

    func refreshSessions() {
        sendCommand(["cmd": "list_sessions"])
    }

    func refreshContent() {
        guard selectedSession != nil else { return }
        sendCommand(["cmd": "get_content"])
    }

    // MARK: - Daemon Management

    private func startDaemon() {
        guard daemonProcess == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [daemonPath]
        process.currentDirectoryURL = URL(fileURLWithPath: daemonPath).deletingLastPathComponent()

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        stdinPipe = stdin
        stdoutPipe = stdout

        // Handle stdout data
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                DispatchQueue.main.async {
                    self?.handleDaemonResponse(line)
                }
            }
        }

        do {
            try process.run()
            daemonProcess = process
            print("[TerminalOverlay] Daemon started")
        } catch {
            print("[TerminalOverlay] Failed to start daemon: \(error)")
        }
    }

    private func stopDaemon() {
        sendCommand(["cmd": "quit"])
        daemonProcess?.terminate()
        daemonProcess = nil
        stdinPipe = nil
        stdoutPipe = nil
    }

    private func sendCommand(_ command: [String: Any]) {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: command),
              var jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        jsonString += "\n"
        pipe.fileHandleForWriting.write(jsonString.data(using: .utf8)!)
    }

    private func handleDaemonResponse(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Handle sessions list
        if let sessionsData = response["sessions"] as? [[String: Any]] {
            sessions = sessionsData.compactMap { dict -> TerminalSession? in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String else { return nil }
                return TerminalSession(
                    id: id,
                    name: name,
                    path: dict["path"] as? String ?? "",
                    job: dict["job"] as? String ?? ""
                )
            }

            // Auto-select first session if none selected
            if selectedSession == nil, let first = sessions.first {
                selectSession(first)
            }
        }

        // Handle content
        if let lines = response["lines"] as? [String] {
            terminalContent = lines
        }

        // Handle errors
        if let error = response["error"] as? String {
            print("[TerminalOverlay] Error: \(error)")
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshContent()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - UI

    private func createOverlayPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = "Terminal Overlay"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(opacity)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden

        let contentView = NSHostingView(rootView: TerminalOverlayView(manager: self))
        panel.contentView = contentView

        panel.center()
        panel.orderFront(nil)

        overlayPanel = panel
    }
}

// MARK: - Models

struct TerminalSession: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let job: String

    var projectName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - SwiftUI View

struct TerminalOverlayView: View {
    @ObservedObject var manager: TerminalOverlayManager
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Session tabs
            if manager.sessions.count > 1 {
                sessionTabs
            }

            // Terminal content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(manager.terminalContent.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black.opacity(0.9))
                .onChange(of: manager.terminalContent.count) { _, _ in
                    // Auto-scroll to bottom
                    if let last = manager.terminalContent.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            // Input field
            HStack {
                Text(">")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)

                TextField("Enter command...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.green)
                    .onSubmit {
                        if !inputText.isEmpty {
                            manager.sendInput(inputText)
                            inputText = ""
                        }
                    }
            }
            .padding(8)
            .background(Color.black)
        }
        .background(Color.black)
    }

    private var sessionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(manager.sessions) { session in
                    Button(action: { manager.selectSession(session) }) {
                        Text(session.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                manager.selectedSession?.id == session.id
                                    ? Color.green.opacity(0.3)
                                    : Color.gray.opacity(0.2)
                            )
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                }
            }
            .padding(8)
        }
        .background(Color.black.opacity(0.95))
    }
}
