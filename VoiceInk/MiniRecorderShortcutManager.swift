import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let escapeRecorder = Self("escapeRecorder")
    static let cancelRecorder = Self("cancelRecorder")
    static let toggleEnhancement = Self("toggleEnhancement")
    // Recording action shortcuts
    static let sendRecorder = Self("sendRecorder")       // Stop + Paste + Enter
    static let peekTranscription = Self("peekTranscription") // Show preview without stopping
    // AI Prompt selection shortcuts
    static let selectPrompt1 = Self("selectPrompt1")
    static let selectPrompt2 = Self("selectPrompt2")
    static let selectPrompt3 = Self("selectPrompt3")
    static let selectPrompt4 = Self("selectPrompt4")
    static let selectPrompt5 = Self("selectPrompt5")
    static let selectPrompt6 = Self("selectPrompt6")
    static let selectPrompt7 = Self("selectPrompt7")
    static let selectPrompt8 = Self("selectPrompt8")
    static let selectPrompt9 = Self("selectPrompt9")
    static let selectPrompt10 = Self("selectPrompt10")
    // Power Mode selection shortcuts
    static let selectPowerMode1 = Self("selectPowerMode1")
    static let selectPowerMode2 = Self("selectPowerMode2")
    static let selectPowerMode3 = Self("selectPowerMode3")
    static let selectPowerMode4 = Self("selectPowerMode4")
    static let selectPowerMode5 = Self("selectPowerMode5")
    static let selectPowerMode6 = Self("selectPowerMode6")
    static let selectPowerMode7 = Self("selectPowerMode7")
    static let selectPowerMode8 = Self("selectPowerMode8")
    static let selectPowerMode9 = Self("selectPowerMode9")
    static let selectPowerMode10 = Self("selectPowerMode10")
}

@MainActor
class MiniRecorderShortcutManager: ObservableObject {
    private var whisperState: WhisperState
    private var visibilityTask: Task<Void, Never>?
    
    private var isCancelHandlerSetup = false
    private var isSendHandlerSetup = false
    private var isPeekHandlerSetup = false

    // Double-tap Escape handling
    private var escFirstPressTime: Date? = nil
    private let escSecondPressThreshold: TimeInterval = 1.5
    private var isEscapeHandlerSetup = false
    private var escapeTimeoutTask: Task<Void, Never>?
    
    init(whisperState: WhisperState) {
        self.whisperState = whisperState
        setupVisibilityObserver()
        setupEnhancementShortcut()
        setupEscapeHandlerOnce()
        setupCancelHandlerOnce()
        setupSendHandlerOnce()
        setupPeekHandlerOnce()
    }
    
    private func setupVisibilityObserver() {
        visibilityTask = Task { @MainActor in
            for await isVisible in whisperState.$isMiniRecorderVisible.values {
                if isVisible {
                    activateEscapeShortcut()
                    activateCancelShortcut()
                    KeyboardShortcuts.setShortcut(.init(.e, modifiers: .command), for: .toggleEnhancement)
                    setupPromptShortcuts()
                    setupPowerModeShortcuts()
                } else {
                    deactivateEscapeShortcut()
                    deactivateCancelShortcut()
                    removeEnhancementShortcut()
                    removePromptShortcuts()
                    removePowerModeShortcuts()
                }
            }
        }
    }
    
    // Local escape monitor (doesn't block other apps)
    private var escapeLocalMonitor: Any?
    private var escapeGlobalMonitor: Any?

    // Setup escape handler using local event monitoring (not global hotkey capture)
    private func setupEscapeHandlerOnce() {
        guard !isEscapeHandlerSetup else { return }
        isEscapeHandlerSetup = true
        // Handler setup is done in activateEscapeShortcut using local monitors
    }

    private func activateEscapeShortcut() {
        // Don't activate if custom shortcut is configured
        guard KeyboardShortcuts.getShortcut(for: .cancelRecorder) == nil else { return }

        // Use local event monitoring instead of global hotkey capture
        // This allows escape to pass through to other apps while still working for our app
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Escape key

            Task { @MainActor in
                await self?.handleEscapePress()
            }
            return nil // Consume the event locally
        }

        // Also monitor global events but DON'T consume them - just listen
        escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // 53 = Escape key

            // Only handle if our app is not the active app (background monitoring)
            // This way escape still works when recording but another app is focused
            Task { @MainActor in
                await self?.handleEscapePress()
            }
        }
    }

    private func handleEscapePress() async {
        guard whisperState.isMiniRecorderVisible else { return }
        guard KeyboardShortcuts.getShortcut(for: .cancelRecorder) == nil else { return }

        let now = Date()
        if let firstTime = escFirstPressTime,
           now.timeIntervalSince(firstTime) <= escSecondPressThreshold {
            // Second press - actually cancel
            escFirstPressTime = nil
            // Stop engines FIRST so sound can play (AVAudioEngine blocks NSSound)
            whisperState.stopStreamingTranscription()
            _ = await whisperState.streamingRecorder.stopRecording()
            await whisperState.recorder.stopRecording()
            // NOW play sound
            SoundManager.shared.playEscSound()
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms for sound
            await whisperState.dismissMiniRecorder()
        } else {
            // First press - just show warning (sound may not play due to engine, but notification will show)
            escFirstPressTime = now
            SoundManager.shared.playEscSound()
            NotificationManager.shared.showNotification(
                title: "Press ESC again to cancel recording",
                type: .info,
                duration: escSecondPressThreshold
            )
            escapeTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.escSecondPressThreshold ?? 1.5) * 1_000_000_000))
                await MainActor.run {
                    self?.escFirstPressTime = nil
                }
            }
        }
    }
    
    // Setup cancel handler once
    private func setupCancelHandlerOnce() {
        guard !isCancelHandlerSetup else { return }
        isCancelHandlerSetup = true

        KeyboardShortcuts.onKeyDown(for: .cancelRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      KeyboardShortcuts.getShortcut(for: .cancelRecorder) != nil else { return }

                // Stop engines FIRST so sound can play (AVAudioEngine blocks NSSound)
                self.whisperState.stopStreamingTranscription()
                _ = await self.whisperState.streamingRecorder.stopRecording()
                await self.whisperState.recorder.stopRecording()
                // NOW play sound
                SoundManager.shared.playEscSound()
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms for sound
                await self.whisperState.dismissMiniRecorder()
            }
        }
    }
    
    private func activateCancelShortcut() {
        // Handler checks if shortcut exists
    }
    
    private func deactivateEscapeShortcut() {
        // Remove local and global monitors
        if let monitor = escapeLocalMonitor {
            NSEvent.removeMonitor(monitor)
            escapeLocalMonitor = nil
        }
        if let monitor = escapeGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            escapeGlobalMonitor = nil
        }
        escFirstPressTime = nil
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
    }
    
    private func deactivateCancelShortcut() {
        // Shortcut managed by user settings
    }

    // MARK: - Send Shortcut (Stop + Paste + Enter)

    private func setupSendHandlerOnce() {
        guard !isSendHandlerSetup else { return }
        isSendHandlerSetup = true

        KeyboardShortcuts.onKeyDown(for: .sendRecorder) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      await self.whisperState.recordingState == .recording,
                      KeyboardShortcuts.getShortcut(for: .sendRecorder) != nil else { return }

                await self.whisperState.stopRecordingAndSend()
            }
        }
    }

    // MARK: - Peek Shortcut (Show transcription without stopping)

    private func setupPeekHandlerOnce() {
        guard !isPeekHandlerSetup else { return }
        isPeekHandlerSetup = true

        KeyboardShortcuts.onKeyDown(for: .peekTranscription) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      await self.whisperState.recordingState == .recording,
                      KeyboardShortcuts.getShortcut(for: .peekTranscription) != nil else { return }

                await self.whisperState.peekTranscription()
            }
        }
    }

    private func setupEnhancementShortcut() {
        KeyboardShortcuts.onKeyDown(for: .toggleEnhancement) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible,
                      let enhancementService = await self.whisperState.getEnhancementService() else { return }
                enhancementService.isEnhancementEnabled.toggle()
            }
        }
    }
    
    private func setupPowerModeShortcuts() {
        KeyboardShortcuts.setShortcut(.init(.one, modifiers: .option), for: .selectPowerMode1)
        KeyboardShortcuts.setShortcut(.init(.two, modifiers: .option), for: .selectPowerMode2)
        KeyboardShortcuts.setShortcut(.init(.three, modifiers: .option), for: .selectPowerMode3)
        KeyboardShortcuts.setShortcut(.init(.four, modifiers: .option), for: .selectPowerMode4)
        KeyboardShortcuts.setShortcut(.init(.five, modifiers: .option), for: .selectPowerMode5)
        KeyboardShortcuts.setShortcut(.init(.six, modifiers: .option), for: .selectPowerMode6)
        KeyboardShortcuts.setShortcut(.init(.seven, modifiers: .option), for: .selectPowerMode7)
        KeyboardShortcuts.setShortcut(.init(.eight, modifiers: .option), for: .selectPowerMode8)
        KeyboardShortcuts.setShortcut(.init(.nine, modifiers: .option), for: .selectPowerMode9)
        KeyboardShortcuts.setShortcut(.init(.zero, modifiers: .option), for: .selectPowerMode10)
        
        // Setup handlers
        setupPowerModeHandler(for: .selectPowerMode1, index: 0)
        setupPowerModeHandler(for: .selectPowerMode2, index: 1)
        setupPowerModeHandler(for: .selectPowerMode3, index: 2)
        setupPowerModeHandler(for: .selectPowerMode4, index: 3)
        setupPowerModeHandler(for: .selectPowerMode5, index: 4)
        setupPowerModeHandler(for: .selectPowerMode6, index: 5)
        setupPowerModeHandler(for: .selectPowerMode7, index: 6)
        setupPowerModeHandler(for: .selectPowerMode8, index: 7)
        setupPowerModeHandler(for: .selectPowerMode9, index: 8)
        setupPowerModeHandler(for: .selectPowerMode10, index: 9)
    }
    
    private func setupPowerModeHandler(for shortcutName: KeyboardShortcuts.Name, index: Int) {
        KeyboardShortcuts.onKeyDown(for: shortcutName) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible else { return }
                
                let powerModeManager = PowerModeManager.shared
                
                if !powerModeManager.enabledConfigurations.isEmpty {
                    let availableConfigurations = powerModeManager.enabledConfigurations
                    if index < availableConfigurations.count {
                        let selectedConfig = availableConfigurations[index]
                        powerModeManager.setActiveConfiguration(selectedConfig)
                        await PowerModeSessionManager.shared.beginSession(with: selectedConfig)
                    }
                }
            }
        }
    }
    
    private func removePowerModeShortcuts() {
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode1)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode2)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode3)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode4)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode5)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode6)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode7)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode8)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode9)
        KeyboardShortcuts.setShortcut(nil, for: .selectPowerMode10)
    }
    
    private func setupPromptShortcuts() {
        // Use Ctrl+Cmd+1-9 to avoid conflicts with browser/terminal tab switching (Cmd+1-9)
        KeyboardShortcuts.setShortcut(.init(.one, modifiers: [.control, .command]), for: .selectPrompt1)
        KeyboardShortcuts.setShortcut(.init(.two, modifiers: [.control, .command]), for: .selectPrompt2)
        KeyboardShortcuts.setShortcut(.init(.three, modifiers: [.control, .command]), for: .selectPrompt3)
        KeyboardShortcuts.setShortcut(.init(.four, modifiers: [.control, .command]), for: .selectPrompt4)
        KeyboardShortcuts.setShortcut(.init(.five, modifiers: [.control, .command]), for: .selectPrompt5)
        KeyboardShortcuts.setShortcut(.init(.six, modifiers: [.control, .command]), for: .selectPrompt6)
        KeyboardShortcuts.setShortcut(.init(.seven, modifiers: [.control, .command]), for: .selectPrompt7)
        KeyboardShortcuts.setShortcut(.init(.eight, modifiers: [.control, .command]), for: .selectPrompt8)
        KeyboardShortcuts.setShortcut(.init(.nine, modifiers: [.control, .command]), for: .selectPrompt9)
        KeyboardShortcuts.setShortcut(.init(.zero, modifiers: [.control, .command]), for: .selectPrompt10)
        
        // Setup handlers
        setupPromptHandler(for: .selectPrompt1, index: 0)
        setupPromptHandler(for: .selectPrompt2, index: 1)
        setupPromptHandler(for: .selectPrompt3, index: 2)
        setupPromptHandler(for: .selectPrompt4, index: 3)
        setupPromptHandler(for: .selectPrompt5, index: 4)
        setupPromptHandler(for: .selectPrompt6, index: 5)
        setupPromptHandler(for: .selectPrompt7, index: 6)
        setupPromptHandler(for: .selectPrompt8, index: 7)
        setupPromptHandler(for: .selectPrompt9, index: 8)
        setupPromptHandler(for: .selectPrompt10, index: 9)
    }
    
    private func setupPromptHandler(for shortcutName: KeyboardShortcuts.Name, index: Int) {
        KeyboardShortcuts.onKeyDown(for: shortcutName) { [weak self] in
            Task { @MainActor in
                guard let self = self,
                      await self.whisperState.isMiniRecorderVisible else { return }
                
                guard let enhancementService = await self.whisperState.getEnhancementService() else { return }
                
                let availablePrompts = enhancementService.allPrompts
                if index < availablePrompts.count {
                    if !enhancementService.isEnhancementEnabled {
                        enhancementService.isEnhancementEnabled = true
                    }
                    
                    enhancementService.setActivePrompt(availablePrompts[index])
                }
            }
        }
    }
    
    private func removePromptShortcuts() {
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt1)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt2)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt3)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt4)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt5)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt6)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt7)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt8)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt9)
        KeyboardShortcuts.setShortcut(nil, for: .selectPrompt10)
    }
    
    private func removeEnhancementShortcut() {
        KeyboardShortcuts.setShortcut(nil, for: .toggleEnhancement)
    }
    
    deinit {
        visibilityTask?.cancel()
        Task { @MainActor in
            deactivateEscapeShortcut()
            deactivateCancelShortcut()
            removeEnhancementShortcut()
            removePowerModeShortcuts()
        }
    }
} 