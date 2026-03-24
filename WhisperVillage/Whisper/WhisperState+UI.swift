import Foundation
import SwiftUI
import os

// MARK: - UI Management Extension
extension WhisperState {

    // MARK: - Recorder Panel Management

    func showRecorderPanel() {
        if notchWindowManager == nil {
            notchWindowManager = NotchWindowManager(whisperState: self, recorder: recorder)
        }
        notchWindowManager?.show()
    }

    func hideRecorderPanel() {
        notchWindowManager?.hide()
    }

    // MARK: - Mini Recorder Management

    func toggleMiniRecorder() async {
        if isMiniRecorderVisible {
            if recordingState == .recording || recordingState == .paused {
                await toggleRecord()
            } else {
                await cancelRecording()
            }
        } else {
            SoundManager.shared.playStartSound()

            await toggleRecord()

            await MainActor.run {
                isMiniRecorderVisible = true
            }
        }
    }

    func dismissMiniRecorder() async {
        if recordingState == .busy {
            return
        }

        let wasRecording = recordingState == .recording
        let wasPaused = recordingState == .paused

        if wasPaused || wasRecording {
            pausedSegments = []
        }

        await stopStreamingTranscription()
        await streamingRecorder.clearBuffer()

        await MainActor.run {
            self.recordingState = .busy
        }

        if wasRecording {
            await recorder.stopRecording()
        }

        _ = await streamingRecorder.stopRecording()

        hideRecorderPanel()

        await MainActor.run {
            isMiniRecorderVisible = false
        }

        await cleanupModelResources()

        await MainActor.run {
            recordingState = .idle
            debugLog = []
            interimTranscription = ""
        }
    }

    func resetOnLaunch() async {
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
        let wasPaused = recordingState == .paused

        if !wasPaused {
            await stopStreamingTranscription()
            _ = await streamingRecorder.stopRecording()
            await recorder.stopRecording()
        }

        pausedSegments = []

        SoundManager.shared.playEscSound()
        try? await Task.sleep(nanoseconds: 150_000_000)

        shouldCancelRecording = true
        await dismissMiniRecorder()
    }

    // MARK: - Notification Handling

    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleMiniRecorder), name: .toggleMiniRecorder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissMiniRecorder), name: .dismissMiniRecorder, object: nil)
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

    @objc func handlePromptChange() {
        Task {
            await updateContextPrompt()
        }
    }

    @objc func handleTranscriptionError(_ notification: Notification) {
        let errorMessage = notification.userInfo?["error"] as? String ?? "An error occurred during transcription"

        Task { @MainActor in
            await stopStreamingTranscription()
            await streamingRecorder.stopRecording()
            await recorder.stopRecording()

            recordingState = .error(message: errorMessage)
            miniRecorderError = errorMessage
        }
    }

    func dismissError() {
        recordingState = .idle
        miniRecorderError = nil
    }

    func retryAfterError() async {
        dismissError()
        await handleToggleMiniRecorder()
    }

    private func updateContextPrompt() async {
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt

        if let context = whisperContext {
            await context.setPrompt(currentPrompt)
        }
    }
}
