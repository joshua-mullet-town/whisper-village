import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {
    
    // MARK: - Recorder Panel Management
    
    func showRecorderPanel() {
        StreamingLogger.shared.log("=== SHOW RECORDER PANEL ===")
        StreamingLogger.shared.log("  recorderType property: '\(recorderType)'")
        StreamingLogger.shared.log("  recorderType from UserDefaults: '\(UserDefaults.standard.string(forKey: "RecorderType") ?? "nil")'")
        StreamingLogger.shared.log("  notchWindowManager exists BEFORE: \(notchWindowManager != nil)")
        StreamingLogger.shared.log("  miniWindowManager exists BEFORE: \(miniWindowManager != nil)")
        StreamingLogger.shared.log("  notchWindowManager.isVisible BEFORE: \(notchWindowManager?.isVisible ?? false)")
        StreamingLogger.shared.log("  miniWindowManager.isVisible BEFORE: \(miniWindowManager?.isVisible ?? false)")

        logger.notice("📱 Showing \(self.recorderType) recorder")
        if recorderType == "notch" {
            if notchWindowManager == nil {
                notchWindowManager = NotchWindowManager(whisperState: self, recorder: recorder)
                logger.info("Created new notch window manager")
                StreamingLogger.shared.log("  CREATED new NotchWindowManager")
            }
            notchWindowManager?.show()
        } else {
            if miniWindowManager == nil {
                miniWindowManager = MiniWindowManager(whisperState: self, recorder: recorder)
                logger.info("Created new mini window manager")
                StreamingLogger.shared.log("  CREATED new MiniWindowManager")
            }
            miniWindowManager?.show()
        }

        StreamingLogger.shared.log("  notchWindowManager.isVisible AFTER: \(notchWindowManager?.isVisible ?? false)")
        StreamingLogger.shared.log("  miniWindowManager.isVisible AFTER: \(miniWindowManager?.isVisible ?? false)")
    }
    
    func hideRecorderPanel() {
        StreamingLogger.shared.log("=== HIDE RECORDER PANEL ===")
        StreamingLogger.shared.log("  recorderType: '\(recorderType)'")
        StreamingLogger.shared.log("  notchWindowManager.isVisible BEFORE: \(notchWindowManager?.isVisible ?? false)")
        StreamingLogger.shared.log("  miniWindowManager.isVisible BEFORE: \(miniWindowManager?.isVisible ?? false)")

        if recorderType == "notch" {
            notchWindowManager?.hide()
            StreamingLogger.shared.log("  Called notchWindowManager?.hide()")
        } else {
            miniWindowManager?.hide()
            StreamingLogger.shared.log("  Called miniWindowManager?.hide()")
        }

        StreamingLogger.shared.log("  notchWindowManager.isVisible AFTER: \(notchWindowManager?.isVisible ?? false)")
        StreamingLogger.shared.log("  miniWindowManager.isVisible AFTER: \(miniWindowManager?.isVisible ?? false)")
    }
    
    // MARK: - Mini Recorder Management
    
    func toggleMiniRecorder() async {
        // Check if we're in LLM formatting mode - handle differently
        if await handleLLMFormattingToggle() {
            return
        }

        if isMiniRecorderVisible {
            if recordingState == .recording {
                await toggleRecord()
            } else {
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            await toggleRecord()

            await MainActor.run {
                isMiniRecorderVisible = true // This will call showRecorderPanel() via didSet
            }
        }
    }
    
    func dismissMiniRecorder() async {
        StreamingLogger.shared.log("=== DISMISS MINI RECORDER CALLED ===")
        StreamingLogger.shared.log("  recordingState: \(recordingState)")
        StreamingLogger.shared.log("  debugLog.count BEFORE: \(debugLog.count)")

        if recordingState == .busy {
            StreamingLogger.shared.log("  EARLY RETURN: recordingState is .busy")
            return
        }

        let wasRecording = recordingState == .recording

        logger.notice("📱 Dismissing \(self.recorderType) recorder")

        // CRITICAL: Stop streaming transcription timer FIRST to prevent race conditions
        StreamingLogger.shared.log("  Stopping streaming transcription timer...")
        await stopStreamingTranscription()

        // Clear the streaming recorder buffer to prevent old audio from being transcribed
        StreamingLogger.shared.log("  Clearing streaming recorder buffer...")
        await streamingRecorder.clearBuffer()

        await MainActor.run {
            self.recordingState = .busy
        }

        if wasRecording {
            await recorder.stopRecording()
        }

        // Stop streaming recorder
        _ = await streamingRecorder.stopRecording()

        hideRecorderPanel()

        await MainActor.run {
            isMiniRecorderVisible = false
        }

        await cleanupModelResources()

        await MainActor.run {
            StreamingLogger.shared.log("  CLEARING STATE in MainActor.run")
            StreamingLogger.shared.log("  debugLog.count BEFORE clear: \(debugLog.count)")
            recordingState = .idle
            // Clear debug log and streaming state on dismiss
            debugLog = []
            interimTranscription = ""
            isInJarvisCommandMode = false
            StreamingLogger.shared.log("  debugLog.count AFTER clear: \(debugLog.count)")
            StreamingLogger.shared.log("=== DISMISS COMPLETE ===")
        }
    }
    
    func resetOnLaunch() async {
        logger.notice("🔄 Resetting recording state on launch")
        await recorder.stopRecording()
        hideRecorderPanel()
        await MainActor.run {
            isMiniRecorderVisible = false
            shouldCancelRecording = false
            miniRecorderError = nil
            recordingState = .idle
        }
        await cleanupModelResources()
    }
    
    func cancelRecording() async {
        // FIRST: Stop audio engines to release audio resources
        // This allows the cancel sound to play without being blocked by AVAudioEngine
        await stopStreamingTranscription()
        _ = await streamingRecorder.stopRecording()
        await recorder.stopRecording()

        // NOW play cancel sound - audio resources are released
        SoundManager.shared.playEscSound()
        // Give the sound time to play
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        shouldCancelRecording = true
        await dismissMiniRecorder()
    }
    
    // MARK: - Notification Handling
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleMiniRecorder), name: .toggleMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissMiniRecorder), name: .dismissMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLicenseStatusChanged), name: .licenseStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePromptChange), name: .promptDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleTranscriptionError), name: NSNotification.Name("SimulateTranscriptionError"), object: nil)
    }
    
    @objc public func handleToggleMiniRecorder() {
        Task {
            await toggleMiniRecorder()
        }
    }
    
    @objc public func handleDismissMiniRecorder() {
        Task {
            await dismissMiniRecorder()
        }
    }
    
    @objc func handleLicenseStatusChanged() {
        self.licenseViewModel = LicenseViewModel()
    }
    
    @objc func handlePromptChange() {
        // Update the whisper context with the new prompt
        Task {
            await updateContextPrompt()
        }
    }

    @objc func handleTranscriptionError(_ notification: Notification) {
        let errorMessage = notification.userInfo?["error"] as? String ?? "An error occurred during transcription"
        StreamingLogger.shared.log("❌ TRANSCRIPTION ERROR: \(errorMessage)")

        Task { @MainActor in
            // Stop any ongoing recording/transcription
            await stopStreamingTranscription()
            await streamingRecorder.stopRecording()
            await recorder.stopRecording()

            // Set error state
            recordingState = .error(message: errorMessage)
            miniRecorderError = errorMessage
        }
    }

    /// Dismiss error and return to idle state
    func dismissError() {
        recordingState = .idle
        miniRecorderError = nil
    }

    /// Retry recording after an error
    func retryAfterError() async {
        dismissError()
        await handleToggleMiniRecorder()
    }
    
    private func updateContextPrompt() async {
        // Always reload the prompt from UserDefaults to ensure we have the latest
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt

        if let context = whisperContext {
            await context.setPrompt(currentPrompt)
        }
    }

    // MARK: - Two-Stage LLM Formatting
    //
    // Flow: User is recording normally → hits "Format with AI" →
    //       captures content, shows in Live Box → Stage 2 starts →
    //       user records instructions → stops → sends to LLM → pastes result

    /// Trigger LLM formatting mode from current recording
    /// Called when user hits "Format with AI" shortcut while recording
    func triggerLLMFormatting() async {
        StreamingLogger.shared.log("🎨 triggerLLMFormatting() called")
        StreamingLogger.shared.log("🎨   recordingState: \(recordingState)")
        StreamingLogger.shared.log("🎨   isLLMFormattingMode: \(isLLMFormattingMode)")
        StreamingLogger.shared.log("🎨   isWaitingForFormattingInstruction: \(isWaitingForFormattingInstruction)")

        // Must be actively recording to use this
        guard recordingState == .recording else {
            StreamingLogger.shared.log("🎨 Format with AI: Not recording, ignoring")
            return
        }

        // If already in Stage 2, complete it
        if isLLMFormattingMode && isWaitingForFormattingInstruction {
            StreamingLogger.shared.log("🎨 Already in Stage 2, completing...")
            await completeLLMFormattingStage2()
            return
        }

        StreamingLogger.shared.log("🎨 Format with AI: Capturing content and starting Stage 2")

        // Capture current transcription as Stage 1 content
        var stage1Text = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        StreamingLogger.shared.log("🎨   stage1Text from interim: \(stage1Text.count) chars")

        // If interim is empty (Simple Mode / Live Preview OFF), transcribe the audio buffer now
        if stage1Text.isEmpty {
            StreamingLogger.shared.log("🎨 Interim empty - transcribing audio buffer on-demand...")
            let samples = await streamingRecorder.getCurrentSamples()
            if samples.count > 16000 { // At least 1 second of audio
                if let transcribedText = await transcribeCapturedSamples(samples) {
                    stage1Text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    StreamingLogger.shared.log("🎨   On-demand transcription: \(stage1Text.count) chars")
                }
            }
        }

        guard !stage1Text.isEmpty else {
            StreamingLogger.shared.log("🎨 Format with AI: No content to format (speak first!)")
            return
        }

        // CRITICAL: Clear the audio buffer FIRST so the streaming transcription loop
        // doesn't immediately refill the live preview with Stage 1 content
        await streamingRecorder.clearBuffer()
        StreamingLogger.shared.log("🎨 Cleared audio buffer for format mode - Stage 2 starts fresh")

        // Enter LLM formatting mode and clear live preview for Stage 2
        await MainActor.run {
            isLLMFormattingMode = true
            llmFormattingContent = stage1Text
            isWaitingForFormattingInstruction = true
            isLLMProcessing = false

            // Clear the live preview (ticker or box) - Stage 2 content will show here
            interimTranscription = ""

            // CRITICAL: Clear the underlying chunks buffer so live preview truly empties
            clearFinalTranscribedChunksForFormatMode()

            // If using live box mode, clear it so formatting instructions show fresh
            if isLivePreviewBoxMode {
                NotificationManager.shared.updateLiveBox(text: "")
            }
        }

        // Show Stage 1 content in the Format Content Box (separate from live preview)
        NotificationManager.shared.showFormatContentBox(content: stage1Text)

        // Play a sound to indicate stage transition
        SoundManager.shared.playStopSound()

        logger.notice("🎨 Format with AI: Stage 1 captured (\(stage1Text.count) chars), now recording instructions")
        // Recording continues - user now speaks their formatting instructions
    }

    /// Complete Stage 2 (instruction recording) and send to LLM
    func completeLLMFormattingStage2() async {
        StreamingLogger.shared.log("🎨 completeLLMFormattingStage2() called")
        StreamingLogger.shared.log("🎨   isLLMFormattingMode: \(isLLMFormattingMode)")
        StreamingLogger.shared.log("🎨   isWaitingForFormattingInstruction: \(isWaitingForFormattingInstruction)")

        guard isLLMFormattingMode && isWaitingForFormattingInstruction else {
            StreamingLogger.shared.log("🎨   Guard failed, returning")
            return
        }

        StreamingLogger.shared.log("🎨 LLM Formatting - Completing Stage 2, sending to LLM")

        // Get the Stage 2 transcription (instructions) - use current interim
        var stage2Text = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        StreamingLogger.shared.log("🎨   stage2Text from interim: \(stage2Text.count) chars")
        StreamingLogger.shared.log("🎨   llmFormattingContent length: \(llmFormattingContent.count)")

        // If interim is empty (Simple Mode / Live Preview OFF), transcribe the audio buffer now
        // Must do this BEFORE stopping recorders
        if stage2Text.isEmpty {
            let samples = await streamingRecorder.getCurrentSamples()
            StreamingLogger.shared.log("🎨 Stage 2 interim empty - checking audio buffer: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)")
            if samples.count > 16000 { // At least 1 second of audio
                if let transcribedText = await transcribeCapturedSamples(samples) {
                    stage2Text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    StreamingLogger.shared.log("🎨   Stage 2 on-demand transcription: \(stage2Text.count) chars")
                }
            } else {
                StreamingLogger.shared.log("🎨   Not enough audio for Stage 2 instructions (< 1 second)")
            }
        }

        // Stop recording
        await stopStreamingTranscription()
        _ = await streamingRecorder.stopRecording()
        await recorder.stopRecording()

        SoundManager.shared.playStopSound()

        // If Stage 2 is empty, proceed with baseline cleanup only (no additional instructions)
        // The new system prompt handles empty instructions properly
        if stage2Text.isEmpty {
            StreamingLogger.shared.log("🎨 LLM Formatting - No instructions, using baseline cleanup only")
        }

        StreamingLogger.shared.log("🎨 LLM Formatting - Stage 2 complete, calling LLM API...")

        // Update UI to show processing state
        await MainActor.run {
            isWaitingForFormattingInstruction = false
            isLLMProcessing = true
            recordingState = .transcribing // Use transcribing state for visual feedback
        }

        // Dismiss the Format Content Box - we're done with Stage 1 reference
        NotificationManager.shared.dismissFormatContentBox()

        // Send to LLM
        do {
            let formattedResult = try await LLMFormattingService.shared.format(
                content: llmFormattingContent,
                instructions: stage2Text
            )

            StreamingLogger.shared.log("🎨 LLM Formatting - Result: \"\(formattedResult.prefix(100))...\"")

            // Hide UI
            hideRecorderPanel()
            await MainActor.run {
                isMiniRecorderVisible = false
                recordingState = .idle
            }

            // Paste the formatted result
            await pasteText(formattedResult)

            // Reset formatting state
            resetLLMFormattingState()

        } catch {
            StreamingLogger.shared.log("🎨 LLM Formatting - ERROR: \(error.localizedDescription)")
            StreamingLogger.shared.log("🎨   Full error: \(error)")

            await MainActor.run {
                recordingState = .error(message: error.localizedDescription)
                miniRecorderError = error.localizedDescription
                isLLMProcessing = false
            }
        }
    }

    /// Cancel the LLM formatting flow
    func cancelLLMFormattingMode() async {
        logger.notice("🎨 LLM Formatting - Cancelled")

        if recordingState == .recording {
            await stopStreamingTranscription()
            _ = await streamingRecorder.stopRecording()
            await recorder.stopRecording()
        }

        SoundManager.shared.playEscSound()

        NotificationManager.shared.dismissFormatContentBox()
        await dismissMiniRecorder()
        resetLLMFormattingState()
    }

    /// Reset all LLM formatting state
    private func resetLLMFormattingState() {
        isLLMFormattingMode = false
        llmFormattingContent = ""
        isWaitingForFormattingInstruction = false
        isLLMProcessing = false
        LLMFormattingService.shared.reset()
    }

    /// Handle toggle action during LLM formatting mode (called from toggleMiniRecorder)
    /// Returns true if the action was handled by LLM formatting flow
    func handleLLMFormattingToggle() async -> Bool {
        guard isLLMFormattingMode else { return false }

        if isWaitingForFormattingInstruction && recordingState == .recording {
            // In Stage 2, user stopped - complete it
            await completeLLMFormattingStage2()
            return true
        }

        return false
    }

    /// Helper to paste text and optionally send with Enter
    private func pasteText(_ text: String) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay before paste
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Paste using Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Command Mode (Voice Navigation)
    //
    // Flow: User starts normal recording → says command → hits Command Mode shortcut →
    //       background changes to orange → user stops recording → executes command
    //
    // Similar to AI Polish - you decide mid-recording that this should be a command.

    /// Trigger Command Mode - immediately stops recording and executes as command
    /// Called when user hits Command Mode shortcut while recording
    func triggerCommandMode() async {
        StreamingLogger.shared.log("⌘ triggerCommandMode() called")
        StreamingLogger.shared.log("⌘   recordingState: \(recordingState)")

        // Check if Command Mode is enabled
        guard isCommandModeEnabled else {
            StreamingLogger.shared.log("⌘ Command Mode is disabled in settings")
            return
        }

        // Must be actively recording
        guard recordingState == .recording else {
            StreamingLogger.shared.log("⌘ Not recording, ignoring")
            return
        }

        // Check dependencies first - give helpful guidance if something's missing
        let deps = await OllamaClient.shared.checkDependencies()
        if !deps.isReady {
            StreamingLogger.shared.log("⌘ Dependencies not ready: \(deps.userMessage ?? "unknown")")
            SoundManager.shared.playEscSound()

            // Show helpful notification with action button when possible
            await MainActor.run {
                let message = deps.userMessage ?? "Command Mode is not ready"

                // Determine if we can offer a one-click fix
                if deps.ollamaInstalled && !deps.ollamaRunning {
                    // Ollama installed but not running - offer to start it
                    NotificationManager.shared.showNotification(
                        title: message,
                        type: .warning,
                        duration: 8.0,
                        actionButton: (title: "Start Ollama", action: {
                            OllamaClient.shared.startOllama()
                        })
                    )
                } else if deps.ollamaRunning && !deps.modelAvailable {
                    // Ollama running but model missing - offer to download it
                    NotificationManager.shared.showNotification(
                        title: message,
                        type: .warning,
                        duration: 8.0,
                        actionButton: (title: "Download Model", action: {
                            OllamaClient.shared.pullModel(deps.modelName)
                        })
                    )
                } else {
                    // Ollama not installed - they need to install it manually
                    let command = deps.terminalCommand ?? ""
                    if !command.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                    }
                    NotificationManager.shared.showNotification(
                        title: "\(message). Paste '\(command)' in Terminal.",
                        type: .warning
                    )
                }
            }
            return
        }

        // Dependencies OK - now check if Ollama is actually healthy (catches GPU errors)
        let healthResult = await OllamaClient.shared.ensureHealthy()
        switch healthResult {
        case .success:
            break // Continue with command execution
        case .failure(let error):
            StreamingLogger.shared.log("⌘ Ollama health check failed: \(error.localizedDescription)")
            SoundManager.shared.playEscSound()

            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: error.localizedDescription,
                    type: .error
                )
            }
            return
        }

        StreamingLogger.shared.log("⌘ Command Mode triggered - stopping recording and executing")

        // Mark as command mode for visual feedback
        await MainActor.run {
            isInCommandMode = true
        }

        // Capture the current transcription as the command
        var command = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        StreamingLogger.shared.log("⌘ Command from interim: \(command.count) chars")

        // If interim is empty (Simple Mode / Live Preview OFF), transcribe the audio buffer now
        // Must do this BEFORE stopping recorders
        if command.isEmpty {
            let samples = await streamingRecorder.getCurrentSamples()
            StreamingLogger.shared.log("⌘ Interim empty - checking audio buffer: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)")
            if samples.count > 16000 { // At least 1 second of audio
                if let transcribedText = await transcribeCapturedSamples(samples) {
                    command = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    StreamingLogger.shared.log("⌘ On-demand transcription: \"\(command)\"")
                }
            } else {
                StreamingLogger.shared.log("⌘ Not enough audio (< 1 second)")
            }
        }

        // Stop recording immediately
        await stopStreamingTranscription()
        _ = await streamingRecorder.stopRecording()
        await recorder.stopRecording()

        // Play stop sound
        SoundManager.shared.playStopSound()

        // Hide the recorder panel
        hideRecorderPanel()
        await MainActor.run {
            isMiniRecorderVisible = false
        }

        // Execute the command
        await executeCommandModeTranscription(command)

        // Cleanup
        await cleanupModelResources()
        await MainActor.run {
            interimTranscription = ""
            debugLog = []
        }
    }

    /// Execute the command when recording stops in Command Mode
    /// Called from toggleRecord when isInCommandMode is true
    func executeCommandModeTranscription(_ command: String) async {
        StreamingLogger.shared.log("⌘ executeCommandModeTranscription: \"\(command)\"")

        guard !command.isEmpty else {
            StreamingLogger.shared.log("⌘ Empty command, nothing to execute")
            await MainActor.run {
                isInCommandMode = false
            }
            return
        }

        // Show processing state briefly
        await MainActor.run {
            recordingState = .transcribing
        }

        // Send to Ollama for interpretation
        do {
            let context = await gatherCommandContext()
            let action = try await OllamaClient.shared.interpret(command: command, context: context)

            StreamingLogger.shared.log("⌘ Ollama interpreted: \(action)")

            // Execute the action
            let success = await executeCommandAction(action)

            if success {
                // Play success sound
                SoundManager.shared.playStartSound()
                StreamingLogger.shared.log("⌘ Command executed successfully")
            } else {
                StreamingLogger.shared.log("⌘ Command execution failed or unknown command")
                SoundManager.shared.playEscSound()
            }

        } catch {
            StreamingLogger.shared.log("⌘ Ollama error: \(error)")
            SoundManager.shared.playEscSound()
        }

        // Clean up
        await MainActor.run {
            isInCommandMode = false
            recordingState = .idle
        }
    }

    /// Gather context about open apps for command interpretation
    private func gatherCommandContext() async -> OllamaClient.AppContext {
        let jarvisService = JarvisCommandService.shared
        // Use reflection or direct access to get the context gathering methods
        // For now, create basic context

        let openApps = getOpenApps()
        let itermTabs = getItermTabs()
        let chromeTabs = getChromeTabs()

        return OllamaClient.AppContext(
            openApps: openApps,
            itermTabs: itermTabs,
            chromeTabs: chromeTabs
        )
    }

    /// Execute the interpreted command action
    private func executeCommandAction(_ action: OllamaClient.JarvisAction) async -> Bool {
        switch action {
        case .focusApp(let name):
            return await focusApp(name)

        case .focusTab(let app, let window, let tab):
            await focusTab(app: app, window: window, tab: tab)
            return true

        case .unknown:
            StreamingLogger.shared.log("⌘ Unknown command - no action taken")
            return false

        default:
            // Other actions (send, stop, cancel, listen) not applicable in Command Mode
            return false
        }
    }

    // MARK: - AppleScript Helpers for Command Mode

    private func getOpenApps() -> [String] {
        let script = """
        tell application "System Events" to get name of every process whose background only is false
        """
        return runAppleScript(script)?.components(separatedBy: ", ") ?? []
    }

    private func getItermTabs() -> [(window: Int, tab: Int, name: String)] {
        let script = """
        tell application "iTerm2"
            set output to ""
            set winNum to 1
            repeat with w in windows
                set tabNum to 1
                repeat with t in tabs of w
                    set output to output & winNum & "," & tabNum & "," & (name of current session of t) & linefeed
                    set tabNum to tabNum + 1
                end repeat
                set winNum to winNum + 1
            end repeat
            return output
        end tell
        """

        guard let output = runAppleScript(script) else { return [] }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3,
                  let window = Int(parts[0]),
                  let tab = Int(parts[1]) else { return nil }
            let name = parts.dropFirst(2).joined(separator: ",")
            return (window, tab, name)
        }
    }

    private func getChromeTabs() -> [(window: Int, tab: Int, title: String)] {
        let script = """
        tell application "Google Chrome"
            set output to ""
            set winNum to 1
            repeat with w in windows
                set tabNum to 1
                repeat with t in tabs of w
                    set output to output & winNum & "," & tabNum & "," & (title of t) & linefeed
                    set tabNum to tabNum + 1
                end repeat
                set winNum to winNum + 1
            end repeat
            return output
        end tell
        """

        guard let output = runAppleScript(script) else { return [] }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3,
                  let window = Int(parts[0]),
                  let tab = Int(parts[1]) else { return nil }
            let title = parts.dropFirst(2).joined(separator: ",")
            return (window, tab, title)
        }
    }

    @MainActor
    private func focusApp(_ name: String) -> Bool {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedName.isEmpty || cleanedName.count < 2 {
            StreamingLogger.shared.log("⌘ Rejecting invalid app name: \"\(name)\"")
            return false
        }

        let openApps = getOpenApps()
        let matchingApp = openApps.first { app in
            app.lowercased().contains(cleanedName.lowercased()) ||
            cleanedName.lowercased().contains(app.lowercased())
        }

        guard let appToFocus = matchingApp else {
            StreamingLogger.shared.log("⌘ No open app matches \"\(cleanedName)\". Open apps: \(openApps)")
            return false
        }

        let script = "tell application \"\(appToFocus)\" to activate"
        _ = runAppleScript(script)
        StreamingLogger.shared.log("⌘ Focused app: \(appToFocus)")
        return true
    }

    @MainActor
    private func focusTab(app: String, window: Int, tab: Int) {
        let script: String

        if app == "iTerm2" || app.lowercased().contains("iterm") {
            script = """
            tell application "iTerm2"
                activate
                tell window \(window)
                    select tab \(tab)
                end tell
            end tell
            """
        } else if app == "Google Chrome" || app.lowercased().contains("chrome") {
            script = """
            tell application "Google Chrome"
                activate
                set active tab index of window \(window) to \(tab)
            end tell
            """
        } else {
            script = "tell application \"\(app)\" to activate"
        }

        _ = runAppleScript(script)
        StreamingLogger.shared.log("⌘ Focused \(app) window \(window) tab \(tab)")
    }

    private func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
} 