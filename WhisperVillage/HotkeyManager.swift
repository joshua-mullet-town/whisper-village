import Foundation
import KeyboardShortcuts
import Carbon
import AppKit

extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let toggleMiniRecorder2 = Self("toggleMiniRecorder2")
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let retryLastTranscription = Self("retryLastTranscription")
    static let formatWithLLM = Self("formatWithLLM")
    static let commandMode = Self("commandMode")
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

    // Double-tap detection (simplified)
    // Track when recording was stopped - if stopped again within threshold, it's a double-tap
    private static var lastRecordingStopTime: Date? = nil
    private static var lastEventTimestamp: TimeInterval = 0  // Dedupe events
    private let doubleTapThreshold: TimeInterval = 0.8  // 800ms window for double-tap

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

        /// Short symbol for display in compact UI (like notch)
        var symbol: String {
            switch self {
            case .none: return ""
            case .rightOption, .leftOption: return "⌥"
            case .leftControl, .rightControl: return "⌃"
            case .fn: return "fn"
            case .rightCommand: return "⌘"
            case .rightShift: return "⇧"
            case .custom: return "⌨"
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

        // Format with LLM hotkey - triggers two-stage formatting mode
        // User must be actively recording - this captures content and starts Stage 2
        KeyboardShortcuts.onKeyUp(for: .formatWithLLM) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                await self.whisperState.triggerLLMFormatting()
            }
        }

        // Command Mode hotkey - converts current recording to a command
        // User must be actively recording - this marks the transcription as a command
        // When recording stops, it interprets and executes instead of pasting
        KeyboardShortcuts.onKeyUp(for: .commandMode) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                await self.whisperState.triggerCommandMode()
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
        // Deduplicate events using timestamp (like Magnet does)
        let timestamp = event.timestamp
        guard Self.lastEventTimestamp != timestamp else {
            StreamingLogger.shared.log("🔑 DEDUPE: ignoring duplicate event")
            return
        }
        Self.lastEventTimestamp = timestamp

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

        StreamingLogger.shared.log("🔑 MODIFIER EVENT: key=\(hotkey), pressed=\(isKeyPressed)")
        processKeyPress(isKeyPressed: isKeyPressed)
    }
    
    // MARK: - Clean Hotkey Logic
    //
    // KEY DOWN while idle: Start recording
    // KEY DOWN while recording: Stop recording (check for double-tap)
    // KEY UP after starting: If brief press → hands-free mode, else stop recording
    //
    // Double-tap detection:
    //   - When stopping recording, check if we stopped another recording recently
    //   - If stopped within 400ms of previous stop → double-tap → paste + enter

    private var startedRecordingThisPress = false

    private func processKeyPress(isKeyPressed: Bool) {
        guard isKeyPressed != currentKeyState else { return }
        currentKeyState = isKeyPressed

        if isKeyPressed {
            // KEY DOWN
            keyPressStartTime = Date()
            startedRecordingThisPress = false

            let state = whisperState.recordingState
            StreamingLogger.shared.log("🔑 KEY DOWN: state=\(state)")

            switch state {
            case .transcribing, .enhancing, .busy:
                // BUSY states - but still check for double-tap!
                // User might double-tap so fast that we're already transcribing
                let isDoubleTap = isWithinDoubleTapWindow()
                if isDoubleTap {
                    whisperState.doubleTapSendPending = true
                    StreamingLogger.shared.log("🔑 DOUBLE-TAP detected during \(state) → send mode")
                }
                return

            case .error:
                // In error state - dismiss error
                Task { @MainActor in
                    whisperState.dismissError()
                }
                return

            case .recording:
                // STOP recording - check for double-tap
                isHandsFreeMode = false

                // Double-tap detection: did we stop recording recently?
                let isDoubleTap = isWithinDoubleTapWindow()
                if isDoubleTap {
                    whisperState.doubleTapSendPending = true
                    StreamingLogger.shared.log("🔑 DOUBLE-TAP detected → send mode")
                }
                Self.lastRecordingStopTime = Date()

                Task { @MainActor in
                    guard canProcessHotkeyAction else { return }
                    await whisperState.handleToggleMiniRecorder()
                }

            case .idle:
                // Start new recording
                startedRecordingThisPress = true
                Task { @MainActor in
                    guard canProcessHotkeyAction else { return }
                    await whisperState.handleToggleMiniRecorder()
                }
            }
        } else {
            // KEY UP
            defer { keyPressStartTime = nil }

            StreamingLogger.shared.log("🔑 KEY UP: startedThisPress=\(startedRecordingThisPress)")

            // Normal release handling - only matters if we started recording this press
            if startedRecordingThisPress, let startTime = keyPressStartTime {
                let pressDuration = Date().timeIntervalSince(startTime)

                if pressDuration < briefPressThreshold {
                    // Brief press → hands-free mode (keep recording)
                    isHandsFreeMode = true
                    StreamingLogger.shared.log("🔑 Brief press (\(String(format: "%.2f", pressDuration))s) → hands-free mode")
                } else {
                    // Long press released → stop recording (push-to-talk)
                    isHandsFreeMode = false
                    Self.lastRecordingStopTime = Date()
                    StreamingLogger.shared.log("🔑 Long press released → stopping")
                    Task { @MainActor in
                        guard canProcessHotkeyAction else { return }
                        await whisperState.handleToggleMiniRecorder()
                    }
                }
            }
        }
    }

    private func isWithinDoubleTapWindow() -> Bool {
        guard let lastStop = Self.lastRecordingStopTime else { return false }
        return Date().timeIntervalSince(lastStop) <= doubleTapThreshold
    }
    
    // Custom shortcut state tracking
    private var shortcutStartedRecordingThisPress = false

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

        let state = whisperState.recordingState
        StreamingLogger.shared.log("🔑 SHORTCUT KEY DOWN: state=\(state)")

        switch state {
        case .transcribing, .enhancing, .busy:
            // BUSY states - but still check for double-tap!
            // User might double-tap so fast that we're already transcribing
            let isDoubleTap = isWithinDoubleTapWindow()
            if isDoubleTap {
                whisperState.doubleTapSendPending = true
                StreamingLogger.shared.log("🔑 SHORTCUT DOUBLE-TAP detected during \(state) → send mode")
            }
            return

        case .error:
            // In error state - dismiss error
            whisperState.dismissError()
            return

        case .recording:
            // STOP recording - check for double-tap
            isShortcutHandsFreeMode = false

            let isDoubleTap = isWithinDoubleTapWindow()
            if isDoubleTap {
                whisperState.doubleTapSendPending = true
                StreamingLogger.shared.log("🔑 SHORTCUT DOUBLE-TAP detected → send mode")
            }
            Self.lastRecordingStopTime = Date()

            guard canProcessHotkeyAction else { return }
            await whisperState.handleToggleMiniRecorder()

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

        StreamingLogger.shared.log("🔑 SHORTCUT KEY UP: startedThisPress=\(shortcutStartedRecordingThisPress)")

        // Normal release handling - only matters if we started recording this press
        if shortcutStartedRecordingThisPress, let startTime = shortcutKeyPressStartTime {
            let pressDuration = Date().timeIntervalSince(startTime)

            if pressDuration < briefPressThreshold {
                // Brief press → hands-free mode (keep recording)
                isShortcutHandsFreeMode = true
                StreamingLogger.shared.log("🔑 SHORTCUT Brief press → hands-free mode")
            } else {
                // Long press released → stop recording (push-to-talk)
                isShortcutHandsFreeMode = false
                Self.lastRecordingStopTime = Date()
                StreamingLogger.shared.log("🔑 SHORTCUT Long press released → stopping")
                guard canProcessHotkeyAction else { return }
                await whisperState.handleToggleMiniRecorder()
            }
        }
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


