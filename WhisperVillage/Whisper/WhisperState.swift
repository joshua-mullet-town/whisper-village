import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import KeyboardShortcuts
import os

// MARK: - Recording State Machine
enum RecordingState: Equatable {
    case idle
    case recording
    case paused      // Audio stopped, previous segments transcribed and stored
    case transcribing
    case enhancing
    case busy
    case error(message: String)
}

// MARK: - Debug Log Entry
/// Represents an event in the streaming debug log
/// All text is shown as unified bubbles with state indicators (icons/colors)
enum DebugLogEntry: Identifiable {
    /// Pending transcription - text in buffer that will be sent (gray waveform)
    case transcription(id: UUID = UUID(), text: String)
    /// Sent transcription - text that was already sent (checkmark icon, lighter)
    case sentTranscription(id: UUID = UUID(), text: String)
    /// Command/action indicator - shows what action was taken (yellow pill)
    case commandDetected(id: UUID = UUID(), raw: String, parsed: String)
    /// Listening indicator - shows system is ready to transcribe (green pill)
    case listening(id: UUID = UUID())

    var id: UUID {
        switch self {
        case .transcription(let id, _): return id
        case .sentTranscription(let id, _): return id
        case .commandDetected(let id, _, _): return id
        case .listening(let id): return id
        }
    }
}

@MainActor
class WhisperState: NSObject, ObservableObject {
    @Published var recordingState: RecordingState = .idle {
        didSet {
            // Dismiss live preview box when recording stops (but not when paused)
            if recordingState != .recording && recordingState != .paused {
                NotificationManager.shared.dismissLiveBox()
            }
        }
    }
    @Published var isModelLoaded = false
    @Published var loadedLocalModel: WhisperModel?
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var shouldCancelRecording = false

    // MARK: - Pause/Resume
    /// Accumulated transcribed text segments from pause operations
    @Published var pausedSegments: [String] = []

    /// When true, the next paste operation should also press Enter (for double-tap send)
    var doubleTapSendPending = false {
        didSet {
            StreamingLogger.shared.log("🚩 doubleTapSendPending changed: \(oldValue) → \(doubleTapSendPending)")
        }
    }

    let recorderType: String = "notch"

    @Published var isMiniRecorderVisible = false {
        didSet {
            if isMiniRecorderVisible {
                showRecorderPanel()
            } else {
                hideRecorderPanel()
            }
        }
    }

    var whisperContext: WhisperContext?
    let recorder = Recorder()
    let streamingRecorder = StreamingRecorder()
    var recordedFile: URL? = nil
    let whisperPrompt = WhisperPrompt()

    /// Whether streaming mode is enabled (captures samples in real-time)
    var isStreamingModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "StreamingModeEnabled")
    }

    /// Whether live preview is enabled (continuous transcription while recording)
    /// When OFF: Simple Mode - just record, transcribe only on stop/peek/send
    var isLivePreviewEnabled: Bool {
        UserDefaults.standard.bool(forKey: "LivePreviewEnabled")
    }

    /// Live preview style: "ticker" (horizontal scrolling) or "box" (draggable floating box)
    var livePreviewStyle: String {
        UserDefaults.standard.string(forKey: "LivePreviewStyle") ?? "box"
    }

    /// Whether live preview is in box mode (floating draggable box)
    var isLivePreviewBoxMode: Bool {
        isLivePreviewEnabled && livePreviewStyle == "box"
    }

    // MARK: - Streaming Transcription (Simplified - Full Buffer)
    /// Task for the streaming transcription loop
    private var streamingTranscriptionTask: Task<Void, Never>?
    private var isStreamingTranscriptionInProgress = false
    /// Flag to request graceful stop (allows current transcription to complete + one final pass)
    private var shouldStopStreamingGracefully = false

    /// Current live preview - shows the FULL transcription (preview = final)
    @Published var interimTranscription: String = ""

    /// Debug log entries for the current recording session (never cleared until new recording starts)
    @Published var debugLog: [DebugLogEntry] = []

    /// Final transcribed text chunks - ONLY populated on user pause boundaries
    /// This is the ACTUAL output (not the live preview). Chunks are created when:
    /// - User pauses → transcribe full audio, save text, clear audio buffer
    /// - User sends or hits Option+Space → transcribe, append to this, concatenate for output
    private var finalTranscribedChunks: [String] = []

    // Transcription Services
    private var localTranscriptionService: LocalTranscriptionService!
    // Cloud transcription removed — local only
    private lazy var parakeetTranscriptionService = ParakeetTranscriptionService(customModelsDirectory: parakeetModelsDirectory)

    private var modelUrl: URL? {
        let possibleURLs = [
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "Models"),
            Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin"),
            Bundle.main.bundleURL.appendingPathComponent("Models/ggml-base.en.bin")
        ]

        for url in possibleURLs {
            if let url = url, FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private enum LoadError: Error {
        case couldNotLocateModel
    }

    let modelsDirectory: URL
    let recordingsDirectory: URL
    let parakeetModelsDirectory: URL
    let modelContext: ModelContext
    let logger = Logger(subsystem: "town.mullet.WhisperVillage", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?

    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloadingParakeet = false

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("town.mullet.WhisperVillage")

        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        self.parakeetModelsDirectory = appSupportDirectory

        super.init()

        // Set the whisperState reference after super.init()
        self.localTranscriptionService = LocalTranscriptionService(modelsDirectory: self.modelsDirectory, whisperState: self)

        setupNotifications()
        createModelsDirectoryIfNeeded()
        createRecordingsDirectoryIfNeeded()
        loadAvailableModels()
        loadCurrentTranscriptionModel()
        refreshAllAvailableModels()

        // Log startup state for debugging recorder selection bug
        StreamingLogger.shared.log("=== APP LAUNCH - USER DEFAULTS STATE ===")
        StreamingLogger.shared.log("  RecorderType: '\(UserDefaults.standard.string(forKey: "RecorderType") ?? "nil")'")
        StreamingLogger.shared.log("  StreamingModeEnabled: \(UserDefaults.standard.bool(forKey: "StreamingModeEnabled"))")
        StreamingLogger.shared.log("  LivePreviewEnabled: \(UserDefaults.standard.bool(forKey: "LivePreviewEnabled"))")
        StreamingLogger.shared.log("  NotchAlwaysVisible: \(UserDefaults.standard.bool(forKey: "NotchAlwaysVisible"))")
        StreamingLogger.shared.log("  Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
    }

    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }

    func toggleRecord() async {
        StreamingLogger.shared.log("🎯 toggleRecord() called, current state: \(recordingState)")

        // Handle hotkey pressed while paused: finalize with all stored segments
        if recordingState == .paused {
            StreamingLogger.shared.log("🎯 Was paused, finalizing with \(pausedSegments.count) stored segments...")

            await MainActor.run {
                recordingState = .transcribing
            }

            // Concatenate all stored segments with newlines
            let finalText: String
            if pausedSegments.isEmpty {
                // Nothing was transcribed during any pause
                await MainActor.run {
                    recordingState = .idle
                    pausedSegments = []
                }
                await cleanupModelResources()
                await dismissMiniRecorder()
                return
            } else {
                finalText = pausedSegments.joined(separator: "\n")
            }

            // Clear segments for next session
            await MainActor.run {
                pausedSegments = []
                recordingState = .idle
            }

            var processedText = finalText

            let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
            if shouldAddSpace {
                processedText += " "
            }

            // Save to history
            saveStreamingTranscriptionToHistory(processedText)

            let shouldSend = self.doubleTapSendPending
            self.doubleTapSendPending = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                if shouldSend {
                    StreamingLogger.shared.log("📋 DOUBLE-TAP (from paused): Pasting + Enter")
                    CursorPaster.pasteAtCursor(processedText)
                    SoundManager.shared.playSendSound()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        CursorPaster.pressEnter()
                    }
                } else {
                    StreamingLogger.shared.log("📋 -> Normal paste from paused segments")
                    CursorPaster.pasteAtCursor(processedText)
                }
            }

            hideRecorderPanel()
            await MainActor.run {
                isMiniRecorderVisible = false
            }
            await cleanupModelResources()
            return
        }

        if recordingState == .recording {
            StreamingLogger.shared.log("🎯 Was recording, now stopping...")
            // FIRST: Stop audio engines to release audio resources
            // This allows sounds to play without being blocked by AVAudioEngine
            // Samples are already buffered in memory so transcription will still work
            await stopStreamingTranscription()
            let capturedSamples = await streamingRecorder.stopRecording()
            await recorder.stopRecording()

            // NOW play stop sound - audio resources are released
            SoundManager.shared.playStopSound()

            // Show transcribing/processing state immediately (for always-visible notch)
            StreamingLogger.shared.log("🔵 ABOUT TO SET recordingState = .transcribing")
            await MainActor.run {
                recordingState = .transcribing
                StreamingLogger.shared.log("🔵 DONE SET recordingState = .transcribing, now: \(recordingState)")
            }

            // Streaming mode path
            if isStreamingModeEnabled {
                StreamingLogger.shared.log("=== TOGGLE RECORD STOP (Streaming Mode) ===")
                StreamingLogger.shared.log("Using \(capturedSamples.count) pre-captured samples")

                // OPTIMIZATION: Hide UI immediately - user stopped recording, they're done
                hideRecorderPanel()
                await MainActor.run {
                    isMiniRecorderVisible = false
                }
                StreamingLogger.shared.log("UI hidden immediately for responsiveness")

                // Inline placeholder - shows loading indicator in target text field
                let placeholderText = "⏳ Transcribing..."
                let showPlaceholder = UserDefaults.standard.bool(forKey: "InlinePlaceholderEnabled")
                var placeholderLength = 0

                if showPlaceholder {
                    placeholderLength = placeholderText.count
                    DispatchQueue.main.async {
                        CursorPaster.pasteAtCursor(placeholderText)
                    }
                    StreamingLogger.shared.log("Pasted inline placeholder (\(placeholderLength) chars)")
                    // Small delay to ensure paste completes
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }

                var textToPaste = ""

                if isLivePreviewEnabled {
                    // Live Preview ON: Use the last interim transcription (already computed)
                    // Since engine is stopped, we can't do graceful stop - use what we have
                    StreamingLogger.shared.log("Live Preview Mode - using last interim transcription")
                    textToPaste = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

                    // If interim is empty but we have samples, transcribe them
                    if textToPaste.isEmpty && capturedSamples.count > 16000 {
                        StreamingLogger.shared.log("Interim empty, transcribing captured samples...")
                        if let transcribedText = await transcribeCapturedSamples(capturedSamples) {
                            textToPaste = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    StreamingLogger.shared.log("Live preview final: \"\(textToPaste)\"")
                } else {
                    // Live Preview OFF: Simple Mode - transcribe captured samples
                    StreamingLogger.shared.log("Simple Mode - transcribing captured samples")

                    // Transcribe the captured audio samples (engine already stopped)
                    if let transcribedText = await transcribeCapturedSamples(capturedSamples) {
                        textToPaste = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    StreamingLogger.shared.log("Simple mode final: \"\(textToPaste)\"")
                }

                // Prepend any paused segments from earlier in this session
                if !pausedSegments.isEmpty {
                    var allSegments = pausedSegments
                    if !textToPaste.isEmpty {
                        allSegments.append(textToPaste)
                    }
                    textToPaste = allSegments.joined(separator: "\n")
                    pausedSegments = []
                    StreamingLogger.shared.log("📝 Prepended \(allSegments.count - 1) paused segments to final text")
                }

                if shouldCancelRecording || textToPaste.isEmpty {
                    // Delete placeholder if we pasted one (cancelled or empty result)
                    if placeholderLength > 0 {
                        DispatchQueue.main.async {
                            CursorPaster.deleteCharacters(count: placeholderLength)
                        }
                        StreamingLogger.shared.log("Deleted placeholder (cancelled/empty)")
                    }
                    pausedSegments = []  // Clear on cancel too
                    await MainActor.run {
                        recordingState = .idle
                    }
                    await cleanupModelResources()
                    await cleanupAfterSend()
                } else {
                    saveStreamingTranscriptionToHistory(textToPaste)

                    await MainActor.run {
                        recordingState = .idle
                    }

                    var finalText = textToPaste

                    let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
                    if shouldAddSpace {
                        finalText += " "
                    }

                    // Delete placeholder if we pasted one, then paste real text
                    let shouldSend = self.doubleTapSendPending
                    self.doubleTapSendPending = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        // Always delete placeholder first if present
                        if placeholderLength > 0 {
                            CursorPaster.deleteCharacters(count: placeholderLength)
                        }

                        if shouldSend {
                            // Double-tap: paste + Enter
                            // 1200ms delay to allow slower apps (like Claude Code terminals) to finish processing paste
                            StreamingLogger.shared.log("📋 DOUBLE-TAP (Streaming): Pasting + Enter")
                            CursorPaster.pasteAtCursor(finalText)
                            SoundManager.shared.playSendSound()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                CursorPaster.pressEnter()
                            }
                        } else {
                            // Normal paste at cursor (single tap stop)
                            StreamingLogger.shared.log("📋 -> Normal paste at cursor")
                            CursorPaster.pasteAtCursor(finalText)
                        }
                    }

                    await cleanupAfterSend()
                }
                return
            }

            // Traditional (non-streaming) mode
            await recorder.stopRecording()

            if let recordedFile {
                if !shouldCancelRecording {
                    await transcribeAudio(recordedFile)
                } else {
                    await MainActor.run {
                        recordingState = .idle
                    }
                    await cleanupModelResources()
                }
            } else {
                logger.error("❌ No recorded file found after stopping recording")
                await MainActor.run {
                    recordingState = .idle
                }
            }
        } else {
            guard currentTranscriptionModel != nil else {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "No AI Model Selected",
                        type: .error
                    )
                }
                return
            }
            shouldCancelRecording = false
            requestRecordPermission { [self] granted in
                if granted {
                    Task {
                        do {
                            // --- Prepare permanent file URL ---
                            let fileName = "\(UUID().uuidString).wav"
                            let permanentURL = self.recordingsDirectory.appendingPathComponent(fileName)
                            self.recordedFile = permanentURL

                            try await self.recorder.startRecording(toOutputFile: permanentURL)

                            // Also start streaming recorder if enabled
                            if self.isStreamingModeEnabled {
                                StreamingLogger.shared.log("Streaming mode enabled, starting StreamingRecorder...")
                                do {
                                    try await self.streamingRecorder.startRecording()
                                    StreamingLogger.shared.log("StreamingRecorder started successfully")
                                } catch {
                                    StreamingLogger.shared.log("ERROR: StreamingRecorder failed to start: \(error)")
                                }
                            }

                            await MainActor.run {
                                StreamingLogger.shared.log("=== RECORDING START - CLEARING STATE ===")
                                StreamingLogger.shared.log("  debugLog.count BEFORE: \(self.debugLog.count)")

                                // Clear streaming preview and debug log from last session
                                self.interimTranscription = ""
                                self.debugLog = []  // Fresh debug log for new recording
                                self.recordingState = .recording

                                // Clear final transcribed chunks from previous session
                                self.finalTranscribedChunks = []

                                StreamingLogger.shared.log("  debugLog.count AFTER clear: \(self.debugLog.count)")
                                StreamingLogger.shared.log("=== RECORDING START COMPLETE ===")

                                // Show live preview box if in box mode
                                StreamingLogger.shared.log("📦 Live Preview Check:")
                                StreamingLogger.shared.log("  isLivePreviewEnabled: \(self.isLivePreviewEnabled)")
                                StreamingLogger.shared.log("  livePreviewStyle: \(self.livePreviewStyle)")
                                StreamingLogger.shared.log("  isLivePreviewBoxMode: \(self.isLivePreviewBoxMode)")
                                if self.isLivePreviewBoxMode {
                                    StreamingLogger.shared.log("📦 Showing live box...")
                                    NotificationManager.shared.showLiveBox()
                                    StreamingLogger.shared.log("📦 showLiveBox() called")
                                } else {
                                    StreamingLogger.shared.log("📦 NOT showing live box (mode is ticker or preview disabled)")
                                }
                            }

                            // Only load model if it's a local model and not already loaded
                            if let model = self.currentTranscriptionModel, model.provider == .local {
                                if let localWhisperModel = self.availableModels.first(where: { $0.name == model.name }),
                                   self.whisperContext == nil {
                                    do {
                                        try await self.loadModel(localWhisperModel)
                                    } catch {
                                        self.logger.error("❌ Model loading failed: \(error.localizedDescription)")
                                    }
                                }
                                    } else if let model = self.currentTranscriptionModel, model.provider == .parakeet {
            try? await parakeetTranscriptionService.loadModel()
                            }

                            // Start streaming transcription if enabled and using local or parakeet model
                            // Only start live preview loop if LivePreviewEnabled is true
                            if self.isStreamingModeEnabled && self.isLivePreviewEnabled {
                                if let model = self.currentTranscriptionModel,
                                   (model.provider == .local || model.provider == .parakeet) {
                                    self.startStreamingTranscription()
                                } else {
                                    StreamingLogger.shared.log("Streaming transcription only works with local/parakeet models (current: \(self.currentTranscriptionModel?.provider.rawValue ?? "none"))")
                                }
                            } else if self.isStreamingModeEnabled && !self.isLivePreviewEnabled {
                                StreamingLogger.shared.log("Simple Mode: Recording audio only, no live transcription")
                            }

                        } catch {
                            self.logger.error("❌ Failed to start recording: \(error.localizedDescription)")
                            await NotificationManager.shared.showNotification(title: "Recording failed to start", type: .error)
                            await self.dismissMiniRecorder()
                            // Do not remove the file on a failed start, to preserve all recordings.
                            self.recordedFile = nil
                        }
                    }
                } else {
                    logger.error("❌ Recording permission denied.")
                }
            }
        }
    }

    // MARK: - Pause/Resume Recording

    /// Pauses recording: immediately transcribes current buffer, stores the text segment,
    /// and stops audio capture. Resume will start fresh recording.
    func pauseRecording() async {
        guard recordingState == .recording else { return }
        StreamingLogger.shared.log("⏸️ PAUSE: Stopping audio and transcribing current segment...")

        // 1. Stop streaming transcription loop
        await stopStreamingTranscription()

        // 2. Get current audio samples before stopping
        let capturedSamples = await streamingRecorder.stopRecording()
        await recorder.stopRecording()

        // 3. Set state to paused immediately (shows paused UI)
        await MainActor.run {
            recordingState = .paused
        }

        // 4. Transcribe the captured audio segment
        var segmentText = ""

        if isStreamingModeEnabled && isLivePreviewEnabled {
            // Use interim transcription if available (fast path)
            let interimText = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            if !interimText.isEmpty {
                segmentText = interimText
                StreamingLogger.shared.log("⏸️ PAUSE: Using interim transcription: \"\(segmentText.prefix(80))...\"")
            } else if capturedSamples.count > 16000 {
                // Fallback: transcribe captured samples
                if let transcribed = await transcribeCapturedSamples(capturedSamples) {
                    segmentText = transcribed.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                StreamingLogger.shared.log("⏸️ PAUSE: Transcribed samples: \"\(segmentText.prefix(80))...\"")
            }
        } else if isStreamingModeEnabled {
            // Simple streaming mode (no live preview) - must transcribe
            if capturedSamples.count > 16000 {
                if let transcribed = await transcribeCapturedSamples(capturedSamples) {
                    segmentText = transcribed.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // 5. Store non-empty segment
        if !segmentText.isEmpty {
            await MainActor.run {
                pausedSegments.append(segmentText)
                StreamingLogger.shared.log("⏸️ PAUSE: Stored segment #\(pausedSegments.count): \"\(segmentText.prefix(50))...\"")
            }
        } else {
            StreamingLogger.shared.log("⏸️ PAUSE: No audio to transcribe (empty segment)")
        }

        // 6. Clear interim for next segment
        await MainActor.run {
            interimTranscription = ""
            finalTranscribedChunks = []
        }
    }

    /// Resumes recording after pause: starts fresh audio capture.
    /// Previous segments are preserved in pausedSegments.
    func resumeRecording() async {
        guard recordingState == .paused else { return }
        StreamingLogger.shared.log("▶️ RESUME: Starting fresh audio capture...")

        do {
            // 1. Create new recording file for standard recorder
            let fileName = "\(UUID().uuidString).wav"
            let permanentURL = recordingsDirectory.appendingPathComponent(fileName)
            recordedFile = permanentURL

            // 2. Start standard recorder
            try await recorder.startRecording(toOutputFile: permanentURL)

            // 3. Start streaming recorder (fresh buffer)
            if isStreamingModeEnabled {
                try await streamingRecorder.startRecording()
                StreamingLogger.shared.log("▶️ RESUME: StreamingRecorder started")
            }

            // 4. Set state back to recording
            await MainActor.run {
                recordingState = .recording
                interimTranscription = ""
            }

            // 5. Restart streaming transcription if live preview is enabled
            if isStreamingModeEnabled && isLivePreviewEnabled {
                if let model = currentTranscriptionModel,
                   (model.provider == .local || model.provider == .parakeet) {
                    startStreamingTranscription()
                }
            }

            StreamingLogger.shared.log("▶️ RESUME: Recording resumed successfully")
        } catch {
            logger.error("❌ Failed to resume recording: \(error.localizedDescription)")
            await MainActor.run {
                recordingState = .error(message: "Failed to resume: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Stop Recording and Send (Paste + Enter)

    /// Stops recording, transcribes, pastes, and presses Enter to send
    /// This is similar to toggleRecord() stop path but also presses Enter after paste
    /// OPTIMIZED: Hides UI immediately for perceived responsiveness
    func stopRecordingAndSend() async {
        guard recordingState == .recording || recordingState == .paused else { return }

        // For streaming mode
        if isStreamingModeEnabled {
            StreamingLogger.shared.log("=== STOP RECORDING AND SEND ===")

            // FIRST: Stop audio engines to release audio resources
            // This allows the send sound to play without being blocked by AVAudioEngine
            await stopStreamingTranscription()
            let capturedSamples = await streamingRecorder.stopRecording()
            await recorder.stopRecording()

            // NOW play send sound - audio resources are released
            SoundManager.shared.playSendSound()

            // Show transcribing/processing state immediately (for always-visible notch)
            StreamingLogger.shared.log("🔵 stopRecordingAndSend: ABOUT TO SET .transcribing")
            await MainActor.run {
                recordingState = .transcribing
                StreamingLogger.shared.log("🔵 stopRecordingAndSend: DONE SET .transcribing, now: \(recordingState)")
            }

            // Hide UI (if not in always-visible mode, this hides the window)
            hideRecorderPanel()
            await MainActor.run {
                isMiniRecorderVisible = false
            }
            StreamingLogger.shared.log("UI hidden, using \(capturedSamples.count) captured samples")

            var textToPaste = ""

            if isLivePreviewEnabled {
                // Live Preview ON: Use the last interim transcription
                StreamingLogger.shared.log("Send mode - using last interim transcription")
                textToPaste = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

                // If interim is empty but we have samples, transcribe them
                if textToPaste.isEmpty && capturedSamples.count > 16000 {
                    StreamingLogger.shared.log("Interim empty, transcribing captured samples...")
                    if let transcribedText = await transcribeCapturedSamples(capturedSamples) {
                        textToPaste = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                StreamingLogger.shared.log("Send final (live preview): \"\(textToPaste)\"")
            } else {
                // Simple Mode: Transcribe captured samples
                StreamingLogger.shared.log("Send mode - transcribing captured samples")
                await MainActor.run {
                    recordingState = .transcribing
                }
                if let transcribedText = await transcribeCapturedSamples(capturedSamples) {
                    textToPaste = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                StreamingLogger.shared.log("Send final (simple mode): \"\(textToPaste)\"")
            }

            // Recorders already stopped above

            if shouldCancelRecording || textToPaste.isEmpty {
                await MainActor.run {
                    recordingState = .idle
                }
                await cleanupModelResources()
                // Cleanup remaining state
                await cleanupAfterSend()
            } else {
                // Save to history (fast SwiftData insert, non-blocking)
                saveStreamingTranscriptionToHistory(textToPaste)

                await MainActor.run {
                    recordingState = .idle
                }

                let finalText = textToPaste

                // OPTIMIZATION 2 & 3: Reduced delays (50ms→20ms paste, 100ms→50ms enter)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    CursorPaster.pasteAtCursor(finalText)
                    // Press Enter after paste
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        CursorPaster.pressEnter()
                    }
                }

                // Cleanup remaining state (UI already hidden)
                await cleanupAfterSend()
            }
            return
        }

        // For non-streaming mode, just call toggleRecord and then press Enter
        await toggleRecord()
    }

    /// Cleanup state after send - called when UI is already hidden
    private func cleanupAfterSend() async {
        StreamingLogger.shared.log("=== CLEANUP AFTER SEND ===")
        await stopStreamingTranscription()
        await streamingRecorder.clearBuffer()
        await cleanupModelResources()
        await MainActor.run {
            debugLog = []
            interimTranscription = ""
        }
        StreamingLogger.shared.log("=== CLEANUP COMPLETE ===")
    }

    // MARK: - Peek Transcription (Show preview without stopping)

    /// Triggers a transcription of current audio and shows the result
    /// Recording continues after showing the preview
    func peekTranscription() async {
        guard recordingState == .recording || recordingState == .paused else { return }

        guard isStreamingModeEnabled else {
            NotificationManager.shared.showNotification(
                title: "Peek requires streaming mode",
                type: .info,
                duration: 2.0
            )
            return
        }

        StreamingLogger.shared.log("=== PEEK TRANSCRIPTION ===")

        var currentSegmentText = ""

        if recordingState == .paused {
            // While paused: no active audio to transcribe, current segment is empty
            StreamingLogger.shared.log("Peek (paused): showing stored segments only")
        } else if isLivePreviewEnabled {
            // Live Preview ON: Use the already-computed interim transcription
            currentSegmentText = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            StreamingLogger.shared.log("Peek (live preview): \"\(currentSegmentText)\"")
        } else {
            // Simple Mode: Do an on-demand transcription of current audio buffer
            // Note: This transcribes but doesn't stop recording
            StreamingLogger.shared.log("Peek (simple mode): Transcribing current audio...")
            if let transcribedText = await transcribeFullAudioBuffer(clearBufferAfter: false) {
                currentSegmentText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            StreamingLogger.shared.log("Peek (simple mode) result: \"\(currentSegmentText)\"")
        }

        // Combine paused segments + current segment for full peek view
        var allSegments = pausedSegments
        if !currentSegmentText.isEmpty {
            allSegments.append(currentSegmentText)
        }
        let fullText = allSegments.joined(separator: "\n")

        if fullText.isEmpty {
            NotificationManager.shared.showNotification(
                title: "No transcription yet",
                type: .info,
                duration: 2.0
            )
        } else {
            // Show the full transcription in the peek toast
            // - Full text (scrollable if long)
            // - Hover to pause auto-dismiss
            // - 8 second default duration
            NotificationManager.shared.showPeekToast(
                text: fullText,
                duration: 8.0
            )
        }
    }

    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
        response(true)
    }

    private func transcribeAudio(_ url: URL) async {
        if shouldCancelRecording {
            await MainActor.run {
                recordingState = .idle
            }
            await cleanupModelResources()
            return
        }

        await MainActor.run {
            recordingState = .transcribing
        }

        defer {
            if shouldCancelRecording {
                Task {
                    await cleanupModelResources()
                }
            }
        }

        logger.notice("🔄 Starting transcription...")

        do {
            guard let model = currentTranscriptionModel else {
                throw WhisperStateError.transcriptionFailed
            }

            let transcriptionService: TranscriptionService
            switch model.provider {
            case .local:
                transcriptionService = localTranscriptionService
                    case .parakeet:
            transcriptionService = parakeetTranscriptionService
            default:
                // Unsupported provider — fall back to local
                transcriptionService = localTranscriptionService
            }

            let transcriptionStart = Date()
            var text = try await transcriptionService.transcribe(audioURL: url, model: model)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)

            if await checkCancellationAndCleanup() { return }

            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Store last transcription + save to history
            LastTranscriptionService.shared.store(text)
            let audioAsset = AVURLAsset(url: url)
            let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0
            let newTranscription = Transcription(
                text: text,
                duration: actualDuration,
                transcriptionModelName: model.displayName
            )
            modelContext.insert(newTranscription)
            try? modelContext.save()

            let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
            if shouldAddSpace {
                text += " "
            }

            if await checkCancellationAndCleanup() { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                CursorPaster.pasteAtCursor(text)
            }

            await self.dismissMiniRecorder()

        } catch {
            logger.error("❌ Transcription failed: \(error.localizedDescription)")

            // Show error in recorder UI instead of dismissing
            await MainActor.run {
                recordingState = .error(message: "Transcription failed")
                miniRecorderError = "Transcription failed"
            }
        }
    }

    private func checkCancellationAndCleanup() async -> Bool {
        if shouldCancelRecording {
            await dismissMiniRecorder()
            return true
        }
        return false
    }

    private func cleanupAndDismiss() async {
        await dismissMiniRecorder()
    }

    // MARK: - Streaming Transcription Methods

    /// Start the streaming transcription loop (Task-based, not timer)
    func startStreamingTranscription() {
        guard isStreamingModeEnabled else { return }

        // Check we have a valid model for streaming (local whisper or parakeet)
        guard let model = currentTranscriptionModel else {
            StreamingLogger.shared.log("Cannot start streaming transcription: no model selected")
            return
        }

        if model.provider == .local && whisperContext == nil {
            StreamingLogger.shared.log("Cannot start streaming transcription: no whisper context loaded")
            return
        }

        StreamingLogger.shared.log("Starting streaming transcription loop (full buffer mode) [provider: \(model.provider.rawValue)]")

        // Reset state
        interimTranscription = ""
        shouldStopStreamingGracefully = false

        // Start the transcription loop as a Task
        streamingTranscriptionTask = Task { @MainActor [weak self] in
            while let self = self,
                  self.recordingState == .recording,
                  self.isStreamingModeEnabled,
                  !self.shouldStopStreamingGracefully,
                  !Task.isCancelled {
                await self.performInterimTranscription()
                // Yield to let RunLoop process timer events (fixes frozen timer)
                await Task.yield()
            }

            // Graceful stop: do one final transcription to catch any trailing audio
            if let self = self, self.shouldStopStreamingGracefully {
                StreamingLogger.shared.log("Graceful stop: performing final transcription...")
                await self.performInterimTranscription()
                StreamingLogger.shared.log("Graceful stop: final transcription complete")
            }

            StreamingLogger.shared.log("Streaming transcription loop ended")
        }
    }

    /// Stop the streaming transcription loop and wait for any in-flight transcription to complete
    /// This prevents race conditions when starting final transcription immediately after
    func stopStreamingTranscription() async {
        StreamingLogger.shared.log("Stopping streaming transcription loop")
        streamingTranscriptionTask?.cancel()
        // CRITICAL: Wait for the task to actually finish to prevent race conditions
        // The task might be mid-CoreML-inference, which can't be interrupted
        if let task = streamingTranscriptionTask {
            StreamingLogger.shared.log("Waiting for in-flight transcription to complete...")
            _ = await task.value
            StreamingLogger.shared.log("In-flight transcription completed")
        }
        streamingTranscriptionTask = nil
        isStreamingTranscriptionInProgress = false
        // Note: We don't clear interimTranscription here - it contains the full transcription
    }

    /// Stop the streaming transcription loop gracefully
    /// Waits for current transcription to complete, then does one final pass
    /// Returns the final transcription result (from interimTranscription)
    func stopStreamingTranscriptionGracefully() async -> String {
        StreamingLogger.shared.log("Gracefully stopping streaming transcription loop...")

        // Signal the loop to stop after its current iteration
        shouldStopStreamingGracefully = true

        // Wait for the task to complete (which will do one final transcription)
        if let task = streamingTranscriptionTask {
            await task.value
        }

        // Clean up
        streamingTranscriptionTask = nil
        isStreamingTranscriptionInProgress = false

        let result = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        StreamingLogger.shared.log("Graceful stop complete. Result: \"\(result.prefix(100))...\"")
        return result
    }

    /// Clear all streaming UI state
    func clearStreamingPreview() {
        interimTranscription = ""
    }

    /// Perform one interim transcription of the FULL audio buffer
    /// This is the simplified architecture: preview = final
    /// NOTE: Heavy transcription work runs on background thread to avoid UI freezing
    private func performInterimTranscription() async {
        // Skip if already transcribing (serialization actor handles this, but good to skip early)
        guard !isStreamingTranscriptionInProgress else {
            StreamingLogger.shared.log("Skipping interim transcription - previous still in progress")
            return
        }

        // Get current model
        guard let model = currentTranscriptionModel else {
            StreamingLogger.shared.log("Skipping interim transcription - no model selected")
            return
        }

        // Get ALL samples from the buffer (not chunks - full buffer mode)
        let getSamplesStart = Date()
        let rawSamples = await streamingRecorder.getCurrentSamples()
        let getSamplesElapsed = Date().timeIntervalSince(getSamplesStart)
        if getSamplesElapsed > 0.05 {
            StreamingLogger.shared.log("⚠️ MAIN THREAD: getCurrentSamples took \(String(format: "%.3f", getSamplesElapsed))s")
        }

        guard rawSamples.count >= 16000 else {  // Need at least 1 second
            // Don't log this - it's normal at the start of recording
            return
        }

        isStreamingTranscriptionInProgress = true
        let startTime = Date()
        StreamingLogger.shared.log("🚀 Starting background task...")

        // Capture references needed for background work
        let parakeetService = parakeetTranscriptionService
        let context = whisperContext
        let provider = model.provider
        let audioPreprocessor = AudioPreprocessor.shared

        // Run ALL CPU-intensive work on background thread to avoid UI freezing
        // This includes VAD preprocessing AND transcription
        let transcriptionResult: String = await Task.detached(priority: .userInitiated) {
            // Apply VAD preprocessing to extract speech and remove silence (CPU-intensive)
            let samples = audioPreprocessor.extractSpeech(from: rawSamples)

            guard samples.count >= 8000 else {  // Need at least 0.5s of speech
                StreamingLogger.shared.log("Skipping transcription - not enough speech detected")
                return ""
            }

            let sampleDuration = Double(samples.count) / 16000.0
            let rawDuration = Double(rawSamples.count) / 16000.0
            StreamingLogger.shared.log("Transcribing: \(samples.count) samples (\(String(format: "%.2f", sampleDuration))s speech from \(String(format: "%.2f", rawDuration))s) [provider: \(provider.rawValue)]")

            var trimmedText = ""

            if provider == .parakeet {
                // Use Parakeet
                do {
                    let text = try await parakeetService.transcribeSamples(samples)
                    trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    let elapsed = Date().timeIntervalSince(startTime)
                    StreamingLogger.shared.log("Full buffer result (\(String(format: "%.2f", elapsed))s): \"\(trimmedText.prefix(100))...\"")
                } catch {
                    let elapsed = Date().timeIntervalSince(startTime)
                    StreamingLogger.shared.log("Transcription failed after \(String(format: "%.2f", elapsed))s: \(error)")
                }
            } else if provider == .local, let context = context {
                // Use Whisper
                let success = await context.fullTranscribe(samples: samples)
                let elapsed = Date().timeIntervalSince(startTime)

                if success {
                    let text = await context.getTranscription()
                    trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    StreamingLogger.shared.log("Full buffer result (\(String(format: "%.2f", elapsed))s): \"\(trimmedText.prefix(100))...\"")
                } else {
                    StreamingLogger.shared.log("Transcription failed after \(String(format: "%.2f", elapsed))s")
                }
            }

            return trimmedText
        }.value

        let totalElapsed = Date().timeIntervalSince(startTime)
        StreamingLogger.shared.log("✅ Background task complete after \(String(format: "%.2f", totalElapsed))s")

        // Back on MainActor - update UI state
        if !transcriptionResult.isEmpty {
            interimTranscription = transcriptionResult

            // Update live preview box if in box mode
            if isLivePreviewBoxMode {
                NotificationManager.shared.updateLiveBox(text: transcriptionResult)
            }
        }

        isStreamingTranscriptionInProgress = false
    }

    // MARK: - Streaming History Saving

    /// Save a streaming transcription to history
    private func saveStreamingTranscriptionToHistory(_ text: String) {
        guard !text.isEmpty else { return }
        LastTranscriptionService.shared.store(text)
        let newTranscription = Transcription(
            text: text,
            duration: 0,
            transcriptionModelName: currentTranscriptionModel?.displayName ?? "Streaming"
        )
        modelContext.insert(newTranscription)
        try? modelContext.save()
        StreamingLogger.shared.log("History: Saved transcription (\(text.prefix(30))...)")
    }

    // MARK: - Final Audio Transcription

    /// Transcribe the FULL audio buffer (not just a chunk) - used for actual output
    /// This is called on user pause/send boundaries to get the real transcription
    /// Returns the transcribed text, or nil if transcription failed
    /// Transcribe pre-captured audio samples (used when recorder was stopped before sound playback)
    func transcribeCapturedSamples(_ rawSamples: [Float]) async -> String? {
        guard let model = currentTranscriptionModel else {
            StreamingLogger.shared.log("Final transcription: No model selected")
            return nil
        }

        guard rawSamples.count > 0 else {
            StreamingLogger.shared.log("Final transcription: No samples provided")
            return nil
        }

        // Apply VAD preprocessing to extract speech and remove silence
        let samples = AudioPreprocessor.shared.extractSpeech(from: rawSamples)

        guard samples.count >= 8000 else {  // Need at least 0.5s of speech
            StreamingLogger.shared.log("Final transcription: Not enough speech detected after VAD")
            return nil
        }

        let sampleDuration = Double(samples.count) / 16000.0
        let rawDuration = Double(rawSamples.count) / 16000.0
        StreamingLogger.shared.log("Final transcription (captured): Transcribing \(samples.count) samples (\(String(format: "%.2f", sampleDuration))s speech from \(String(format: "%.2f", rawDuration))s)")
        StreamingLogger.shared.log("Final transcription (captured): Using model '\(model.name)' provider=\(model.provider.rawValue)")

        let startTime = Date()
        var transcribedText = ""

        // Run transcription based on provider
        if model.provider == .parakeet {
            StreamingLogger.shared.log("Final transcription (captured): Starting Parakeet transcription...")
            do {
                let text = try await parakeetTranscriptionService.transcribeSamples(samples)
                transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                StreamingLogger.shared.log("Final transcription: Parakeet failed - \(error)")
                return nil
            }
        } else if model.provider == .local, let context = whisperContext {
            let success = await context.fullTranscribe(samples: samples)
            if success {
                let text = await context.getTranscription()
                transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                StreamingLogger.shared.log("Final transcription: Whisper failed")
                return nil
            }
        } else {
            StreamingLogger.shared.log("Final transcription: Unsupported model provider")
            return nil
        }

        let elapsed = Date().timeIntervalSince(startTime)
        StreamingLogger.shared.log("Final transcription (captured): Got \"\(transcribedText)\" in \(String(format: "%.2f", elapsed))s")

        return transcribedText
    }

    private func transcribeFullAudioBuffer(clearBufferAfter: Bool = false) async -> String? {
        guard let model = currentTranscriptionModel else {
            StreamingLogger.shared.log("Final transcription: No model selected")
            return nil
        }

        // Get ALL samples from the streaming recorder
        let rawSamples = await streamingRecorder.getCurrentSamples()

        guard rawSamples.count > 0 else {
            StreamingLogger.shared.log("Final transcription: No samples in buffer")
            return nil
        }

        // Apply VAD preprocessing to extract speech and remove silence
        let samples = AudioPreprocessor.shared.extractSpeech(from: rawSamples)

        guard samples.count >= 8000 else {  // Need at least 0.5s of speech
            StreamingLogger.shared.log("Final transcription: Not enough speech detected after VAD")
            return nil
        }

        let sampleDuration = Double(samples.count) / 16000.0
        let rawDuration = Double(rawSamples.count) / 16000.0
        StreamingLogger.shared.log("Final transcription: Transcribing \(samples.count) samples (\(String(format: "%.2f", sampleDuration))s speech from \(String(format: "%.2f", rawDuration))s)")

        let startTime = Date()
        var transcribedText = ""

        // Run transcription based on provider
        if model.provider == .parakeet {
            do {
                let text = try await parakeetTranscriptionService.transcribeSamples(samples)
                transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                StreamingLogger.shared.log("Final transcription: Parakeet failed - \(error)")
                return nil
            }
        } else if model.provider == .local, let context = whisperContext {
            let success = await context.fullTranscribe(samples: samples)
            if success {
                let text = await context.getTranscription()
                transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                StreamingLogger.shared.log("Final transcription: Whisper failed")
                return nil
            }
        } else {
            StreamingLogger.shared.log("Final transcription: Unsupported model provider")
            return nil
        }

        let elapsed = Date().timeIntervalSince(startTime)
        StreamingLogger.shared.log("Final transcription: Got \"\(transcribedText)\" in \(String(format: "%.2f", elapsed))s")

        // Clear buffer if requested (used after pause to start fresh)
        if clearBufferAfter {
            await streamingRecorder.clearBuffer()
            StreamingLogger.shared.log("Final transcription: Buffer cleared")
        }

        return transcribedText
    }
}
