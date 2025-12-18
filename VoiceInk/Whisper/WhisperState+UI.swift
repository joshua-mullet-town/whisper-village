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
    
    private func updateContextPrompt() async {
        // Always reload the prompt from UserDefaults to ensure we have the latest
        let currentPrompt = UserDefaults.standard.string(forKey: "TranscriptionPrompt") ?? whisperPrompt.transcriptionPrompt
        
        if let context = whisperContext {
            await context.setPrompt(currentPrompt)
        }
    }
} 