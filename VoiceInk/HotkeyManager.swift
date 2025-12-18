import Foundation
import KeyboardShortcuts
import Carbon
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let toggleMiniRecorder2 = Self("toggleMiniRecorder2")
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let retryLastTranscription = Self("retryLastTranscription")
}

@MainActor
class HotkeyManager: ObservableObject {
    @Published var selectedHotkey1: HotkeyOption {
        didSet {
            UserDefaults.standard.set(selectedHotkey1.rawValue, forKey: "selectedHotkey1")
            setupHotkeyMonitoring()
        }
    }
    @Published var selectedHotkey2: HotkeyOption {
        didSet {
            if selectedHotkey2 == .none {
                KeyboardShortcuts.setShortcut(nil, for: .toggleMiniRecorder2)
            }
            UserDefaults.standard.set(selectedHotkey2.rawValue, forKey: "selectedHotkey2")
            setupHotkeyMonitoring()
        }
    }
    @Published var isMiddleClickToggleEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMiddleClickToggleEnabled, forKey: "isMiddleClickToggleEnabled")
            setupHotkeyMonitoring()
        }
    }
    @Published var middleClickActivationDelay: Int {
        didSet {
            UserDefaults.standard.set(middleClickActivationDelay, forKey: "middleClickActivationDelay")
        }
    }
    
    private var whisperState: WhisperState
    private var miniRecorderShortcutManager: MiniRecorderShortcutManager
    
    // MARK: - Helper Properties
    private var canProcessHotkeyAction: Bool {
        whisperState.recordingState != .transcribing && whisperState.recordingState != .enhancing && whisperState.recordingState != .busy
    }
    
    // NSEvent monitoring for modifier keys
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    // Middle-click event monitoring
    private var middleClickMonitors: [Any?] = []
    private var middleClickTask: Task<Void, Never>?
    
    // Key state tracking
    private var currentKeyState = false
    private var keyPressStartTime: Date?
    private let briefPressThreshold = 1.7
    private var isHandsFreeMode = false
    
    // Debounce for Fn key
    private var fnDebounceTask: Task<Void, Never>?
    private var pendingFnKeyState: Bool? = nil
    
    // Keyboard shortcut state tracking
    private var shortcutKeyPressStartTime: Date?
    private var isShortcutHandsFreeMode = false
    private var shortcutCurrentKeyState = false
    private var lastShortcutTriggerTime: Date?
    private let shortcutCooldownInterval: TimeInterval = 0.5

    // Double-tap to send detection
    private var lastStopTime: Date? = nil
    private let doubleTapSendThreshold: TimeInterval = 1.0 // 1000ms window for double-tap
    
    enum HotkeyOption: String, CaseIterable {
        case none = "none"
        case rightOption = "rightOption"
        case leftOption = "leftOption"
        case leftControl = "leftControl" 
        case rightControl = "rightControl"
        case fn = "fn"
        case rightCommand = "rightCommand"
        case rightShift = "rightShift"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .rightOption: return "Right Option (⌥)"
            case .leftOption: return "Left Option (⌥)"
            case .leftControl: return "Left Control (⌃)"
            case .rightControl: return "Right Control (⌃)"
            case .fn: return "Fn"
            case .rightCommand: return "Right Command (⌘)"
            case .rightShift: return "Right Shift (⇧)"
            case .custom: return "Custom"
            }
        }
        
        var keyCode: CGKeyCode? {
            switch self {
            case .rightOption: return 0x3D
            case .leftOption: return 0x3A
            case .leftControl: return 0x3B
            case .rightControl: return 0x3E
            case .fn: return 0x3F
            case .rightCommand: return 0x36
            case .rightShift: return 0x3C
            case .custom, .none: return nil
            }
        }
        
        var isModifierKey: Bool {
            return self != .custom && self != .none
        }
    }
    
    init(whisperState: WhisperState) {
        // One-time migration from legacy single-hotkey settings
        if UserDefaults.standard.object(forKey: "didMigrateHotkeys_v2") == nil {
            // If legacy push-to-talk modifier key was enabled, carry it over
            if UserDefaults.standard.bool(forKey: "isPushToTalkEnabled"),
               let legacyRaw = UserDefaults.standard.string(forKey: "pushToTalkKey"),
               let legacyKey = HotkeyOption(rawValue: legacyRaw) {
                UserDefaults.standard.set(legacyKey.rawValue, forKey: "selectedHotkey1")
            }
            // If a custom shortcut existed, mark hotkey-1 as custom (shortcut itself already persisted)
            if KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil {
                UserDefaults.standard.set(HotkeyOption.custom.rawValue, forKey: "selectedHotkey1")
            }
            // Leave second hotkey as .none
            UserDefaults.standard.set(true, forKey: "didMigrateHotkeys_v2")
        }
        // ---- normal initialisation ----
        self.selectedHotkey1 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "") ?? .rightCommand
        self.selectedHotkey2 = HotkeyOption(rawValue: UserDefaults.standard.string(forKey: "selectedHotkey2") ?? "") ?? .none
        
        self.isMiddleClickToggleEnabled = UserDefaults.standard.bool(forKey: "isMiddleClickToggleEnabled")
        let storedDelay = UserDefaults.standard.integer(forKey: "middleClickActivationDelay")
        self.middleClickActivationDelay = storedDelay > 0 ? storedDelay : 200
        
        self.whisperState = whisperState
        self.miniRecorderShortcutManager = MiniRecorderShortcutManager(whisperState: whisperState)
        if KeyboardShortcuts.getShortcut(for: .pasteLastTranscription) == nil {
            let defaultPasteShortcut = KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .option])
            KeyboardShortcuts.setShortcut(defaultPasteShortcut, for: .pasteLastTranscription)
        }

        KeyboardShortcuts.onKeyUp(for: .pasteLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.pasteLastTranscription(from: self.whisperState.modelContext)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .retryLastTranscription) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                LastTranscriptionService.retryLastTranscription(from: self.whisperState.modelContext, whisperState: self.whisperState)
            }
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.setupHotkeyMonitoring()
        }
    }
    
    private func setupHotkeyMonitoring() {
        removeAllMonitoring()
        
        setupModifierKeyMonitoring()
        setupCustomShortcutMonitoring()
        setupMiddleClickMonitoring()
    }
    
    private func setupModifierKeyMonitoring() {
        // Only set up if at least one hotkey is a modifier key
        guard (selectedHotkey1.isModifierKey && selectedHotkey1 != .none) || (selectedHotkey2.isModifierKey && selectedHotkey2 != .none) else { return }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            Task { @MainActor in
                await self.handleModifierKeyEvent(event)
            }
            return event
        }
    }
    
    private func setupMiddleClickMonitoring() {
        guard isMiddleClickToggleEnabled else { return }

        // Mouse Down
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }

            self.middleClickTask?.cancel()
            self.middleClickTask = Task {
                do {
                    let delay = UInt64(self.middleClickActivationDelay) * 1_000_000 // ms to ns
                    try await Task.sleep(nanoseconds: delay)
                    
                    guard self.isMiddleClickToggleEnabled, !Task.isCancelled else { return }
                    
                    Task { @MainActor in
                        guard self.canProcessHotkeyAction else { return }
                        await self.whisperState.handleToggleMiniRecorder()
                    }
                } catch {
                    // Cancelled
                }
            }
        }

        // Mouse Up
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self = self, event.buttonNumber == 2 else { return }
            self.middleClickTask?.cancel()
        }

        middleClickMonitors = [downMonitor, upMonitor]
    }
    
    private func setupCustomShortcutMonitoring() {
        // Hotkey 1
        if selectedHotkey1 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyUp() }
            }
        }
        // Hotkey 2
        if selectedHotkey2 == .custom {
            KeyboardShortcuts.onKeyDown(for: .toggleMiniRecorder2) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyDown() }
            }
            KeyboardShortcuts.onKeyUp(for: .toggleMiniRecorder2) { [weak self] in
                Task { @MainActor in await self?.handleCustomShortcutKeyUp() }
            }
        }
    }
    
    private func removeAllMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        
        for monitor in middleClickMonitors {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        middleClickMonitors = []
        middleClickTask?.cancel()
        
        resetKeyStates()
    }
    
    private func resetKeyStates() {
        currentKeyState = false
        keyPressStartTime = nil
        isHandsFreeMode = false
        shortcutCurrentKeyState = false
        shortcutKeyPressStartTime = nil
        isShortcutHandsFreeMode = false
    }
    
    private func handleModifierKeyEvent(_ event: NSEvent) async {
        let keycode = event.keyCode
        let flags = event.modifierFlags
        
        // Determine which hotkey (if any) is being triggered
        let activeHotkey: HotkeyOption?
        if selectedHotkey1.isModifierKey && selectedHotkey1.keyCode == keycode {
            activeHotkey = selectedHotkey1
        } else if selectedHotkey2.isModifierKey && selectedHotkey2.keyCode == keycode {
            activeHotkey = selectedHotkey2
        } else {
            activeHotkey = nil
        }
        
        guard let hotkey = activeHotkey else { return }
        
        var isKeyPressed = false
        
        switch hotkey {
        case .rightOption, .leftOption:
            isKeyPressed = flags.contains(.option)
        case .leftControl, .rightControl:
            isKeyPressed = flags.contains(.control)
        case .fn:
            isKeyPressed = flags.contains(.function)
            // Debounce Fn key
            pendingFnKeyState = isKeyPressed
            fnDebounceTask?.cancel()
            fnDebounceTask = Task { [pendingState = isKeyPressed] in
                try? await Task.sleep(nanoseconds: 75_000_000) // 75ms
                if pendingFnKeyState == pendingState {
                    await MainActor.run {
                        self.processKeyPress(isKeyPressed: pendingState)
                    }
                }
            }
            return
        case .rightCommand:
            isKeyPressed = flags.contains(.command)
        case .rightShift:
            isKeyPressed = flags.contains(.shift)
        case .custom, .none:
            return // Should not reach here
        }
        
        processKeyPress(isKeyPressed: isKeyPressed)
    }
    
    // MARK: - Clean Hotkey Logic (with Debug Logging)
    //
    // States: .idle (can start), .recording (can stop), .transcribing (BUSY - ignore)
    //
    // KEY DOWN:
    //   1. If BUSY (transcribing) → IGNORE
    //   2. If recording → STOP, record stop time
    //   3. If idle:
    //      a. If within 500ms of last stop → DOUBLE-TAP SEND
    //      b. Else → START recording
    //
    // KEY UP:
    //   - If we started recording AND brief press → hands-free
    //   - If we started recording AND long press → stop (push-to-talk)

    private var startedRecordingThisPress = false
    private var doubleTapHandled = false

    private static let logFile = "/tmp/hotkey_debug.log"

    private func logHotkey(_ message: String) {
        let state = whisperState.recordingState
        let timeSinceStop: String
        if let stopTime = lastStopTime {
            timeSinceStop = String(format: "%.0fms", Date().timeIntervalSince(stopTime) * 1000)
        } else {
            timeSinceStop = "never"
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let appName = Bundle.main.bundleIdentifier?.contains("debug") == true ? "DEV" : "PROD"
        let logLine = "[\(timestamp)] [\(appName)] \(message) | state=\(state) | lastStop=\(timeSinceStop) | handsFree=\(isHandsFreeMode)\n"

        // Write to file
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: Self.logFile) {
                if let handle = FileHandle(forWritingAtPath: Self.logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: Self.logFile, contents: data)
            }
        }
    }

    private func processKeyPress(isKeyPressed: Bool) {
        guard isKeyPressed != currentKeyState else { return }
        currentKeyState = isKeyPressed

        if isKeyPressed {
            logHotkey("KEY DOWN")
            keyPressStartTime = Date()
            startedRecordingThisPress = false
            doubleTapHandled = false

            // CHECK DOUBLE-TAP FIRST (before state) - state may lag behind
            if isWithinDoubleTapWindow() {
                logHotkey("→ DOUBLE-TAP SEND!")
                doubleTapHandled = true
                lastStopTime = nil
                // Set flag - WhisperState will press Enter AFTER paste completes
                whisperState.doubleTapSendPending = true
                return
            }

            let state = whisperState.recordingState

            switch state {
            case .transcribing, .enhancing, .busy:
                // BUSY - ignore keypress entirely
                logHotkey("→ IGNORED (busy: \(state))")
                return

            case .recording:
                // STOP recording
                logHotkey("→ STOPPING recording")
                isHandsFreeMode = false
                Task { @MainActor in
                    guard canProcessHotkeyAction else { return }
                    await whisperState.handleToggleMiniRecorder()
                    recordStopTime()
                    logHotkey("→ STOPPED, recorded stop time")
                }

            case .idle:
                // Start new recording
                logHotkey("→ STARTING recording")
                startedRecordingThisPress = true
                Task { @MainActor in
                    guard canProcessHotkeyAction else { return }
                    await whisperState.handleToggleMiniRecorder()
                    logHotkey("→ STARTED")
                }
            }
        } else {
            // KEY UP
            logHotkey("KEY UP")
            defer { keyPressStartTime = nil }

            if doubleTapHandled {
                logHotkey("→ (double-tap handled, ignoring)")
                return
            }

            if startedRecordingThisPress, let startTime = keyPressStartTime {
                let pressDuration = Date().timeIntervalSince(startTime)
                let durationMs = Int(pressDuration * 1000)

                if pressDuration < briefPressThreshold {
                    logHotkey("→ Brief press (\(durationMs)ms) → HANDS-FREE mode")
                    isHandsFreeMode = true
                } else {
                    logHotkey("→ Long press (\(durationMs)ms) → PUSH-TO-TALK stop")
                    isHandsFreeMode = false
                    Task { @MainActor in
                        guard canProcessHotkeyAction else { return }
                        await whisperState.handleToggleMiniRecorder()
                        recordStopTime()
                    }
                }
            } else {
                logHotkey("→ (didn't start recording this press)")
            }
        }
    }

    private func isWithinDoubleTapWindow() -> Bool {
        guard let stopTime = lastStopTime else { return false }
        return Date().timeIntervalSince(stopTime) <= doubleTapSendThreshold
    }
    
    // Custom shortcut state tracking
    private var shortcutStartedRecordingThisPress = false
    private var shortcutDoubleTapHandled = false

    private func handleCustomShortcutKeyDown() async {
        if let lastTrigger = lastShortcutTriggerTime,
           Date().timeIntervalSince(lastTrigger) < shortcutCooldownInterval {
            return
        }

        guard !shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = true
        lastShortcutTriggerTime = Date()
        shortcutKeyPressStartTime = Date()
        shortcutStartedRecordingThisPress = false
        shortcutDoubleTapHandled = false

        // CHECK DOUBLE-TAP FIRST (before state) - state may lag behind
        if isWithinDoubleTapWindow() {
            shortcutDoubleTapHandled = true
            lastStopTime = nil
            // Set flag - WhisperState will press Enter AFTER paste completes
            whisperState.doubleTapSendPending = true
            return
        }

        let state = whisperState.recordingState

        switch state {
        case .transcribing, .enhancing, .busy:
            // BUSY - ignore
            return

        case .recording:
            // STOP recording
            isShortcutHandsFreeMode = false
            guard canProcessHotkeyAction else { return }
            await whisperState.handleToggleMiniRecorder()
            recordStopTime()

        case .idle:
            // Start new recording
            shortcutStartedRecordingThisPress = true
            guard canProcessHotkeyAction else { return }
            await whisperState.handleToggleMiniRecorder()
        }
    }

    private func handleCustomShortcutKeyUp() async {
        guard shortcutCurrentKeyState else { return }
        shortcutCurrentKeyState = false
        defer { shortcutKeyPressStartTime = nil }

        // If double-tap was handled, nothing to do
        if shortcutDoubleTapHandled { return }

        // If we started recording this press, handle push-to-talk
        if shortcutStartedRecordingThisPress, let startTime = shortcutKeyPressStartTime {
            let pressDuration = Date().timeIntervalSince(startTime)

            if pressDuration < briefPressThreshold {
                // Brief press → hands-free mode (keep recording)
                isShortcutHandsFreeMode = true
            } else {
                // Long press released → stop recording (push-to-talk)
                isShortcutHandsFreeMode = false
                guard canProcessHotkeyAction else { return }
                await whisperState.handleToggleMiniRecorder()
                recordStopTime()
            }
        }
    }
    
    /// Record that recording just stopped (for double-tap detection)
    private func recordStopTime() {
        lastStopTime = Date()
    }

    // Computed property for backward compatibility with UI
    var isShortcutConfigured: Bool {
        let isHotkey1Configured = (selectedHotkey1 == .custom) ? (KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) != nil) : true
        let isHotkey2Configured = (selectedHotkey2 == .custom) ? (KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder2) != nil) : true
        return isHotkey1Configured && isHotkey2Configured
    }
    
    func updateShortcutStatus() {
        // Called when a custom shortcut changes
        if selectedHotkey1 == .custom || selectedHotkey2 == .custom {
            setupHotkeyMonitoring()
        }
    }
    
    deinit {
        // Remove monitoring synchronously - these are just removing event monitors
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}


