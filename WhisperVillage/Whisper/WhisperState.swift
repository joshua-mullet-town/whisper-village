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
            // Dismiss live preview box when recording stops
            if recordingState != .recording {
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

    /// When true, the next paste operation should also press Enter (for double-tap send)
    var doubleTapSendPending = false

    /// When true, the next transcription should be sent to terminal instead of pasting (for triple-tap)
    var tripleTapTerminalPending = false

    // MARK: - Two-Stage LLM Formatting
    /// Tracks whether we're in LLM formatting mode (two-stage transcription)
    @Published var isLLMFormattingMode = false
    /// Stage 1 content (the main message)
    @Published var llmFormattingContent = ""
    /// Whether we're waiting for Stage 2 (instruction recording)
    @Published var isWaitingForFormattingInstruction = false
    /// Whether LLM is processing the formatted result
    @Published var isLLMProcessing = false

    /// Clears the final transcribed chunks buffer - used when entering format mode
    /// to ensure the live preview starts fresh for formatting instructions
    func clearFinalTranscribedChunksForFormatMode() {
        finalTranscribedChunks = []
        StreamingLogger.shared.log("🎨 Cleared finalTranscribedChunks for format mode")
    }

    // MARK: - Command Mode (Voice Navigation)
    /// Whether we're in Command Mode (recording a voice command)
    @Published var isInCommandMode = false
    /// Whether Command Mode is enabled in settings
    var isCommandModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "CommandModeEnabled")
    }

    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "notch" {
        didSet {
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
            StreamingLogger.shared.log("🎛️ RECORDER_TYPE CHANGED: '\(oldValue)' → '\(recorderType)'")
            StreamingLogger.shared.log("    notchWindowManager exists: \(notchWindowManager != nil)")
            StreamingLogger.shared.log("    miniWindowManager exists: \(miniWindowManager != nil)")
        }
    }
    
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

    // MARK: - Jarvis Command Mode
    /// Whether we're in command mode (not transcribing, waiting for Jarvis commands)
    @Published var isInJarvisCommandMode = false

    /// Flag to prevent duplicate command execution while one is in progress
    private var isExecutingJarvisCommand = false

    /// Last executed command part (to avoid re-executing similar commands)
    private var lastExecutedJarvisCommandPart: String = ""

    /// Timestamp of last executed command (for debounce)
    private var lastJarvisCommandTime: Date = .distantPast

    /// The transcription buffer - text accumulated since recording start
    /// This is what gets pasted when recording ends
    private var jarvisTranscriptionBuffer: String = ""

    /// Text that was in the buffer before the last "Jarvis listen" command
    /// Used to properly accumulate text across pause/listen cycles
    private var jarvisPreListenBuffer: String = ""

    /// Sample index where current transcription segment started (for audio offset tracking)
    private var jarvisBufferStartSample: Int = 0

    /// Flag indicating a voice command set the final text (vs streaming preview)
    /// When true, toggleRecord should use jarvisTranscriptionBuffer directly
    /// When false, toggleRecord should do a fresh final transcription
    private var voiceCommandSetFinalText: Bool = false

    /// Final transcribed text chunks - ONLY populated on user pause boundaries
    /// This is the ACTUAL output (not the live preview). Chunks are created when:
    /// - User says "Jarvis pause" → transcribe full audio, save text, clear audio buffer
    /// - User says "Jarvis send it" or hits Option+Space → transcribe, append to this, concatenate for output
    private var finalTranscribedChunks: [String] = []

    // Prompt detection service for trigger word handling
    private let promptDetectionService = PromptDetectionService()

    // Jarvis command service for intelligent voice commands
    private let jarvisService = JarvisCommandService.shared
    
    let modelContext: ModelContext
    
    // Transcription Services
    private var localTranscriptionService: LocalTranscriptionService!
    private lazy var cloudTranscriptionService = CloudTranscriptionService()
    private lazy var nativeAppleTranscriptionService = NativeAppleTranscriptionService()
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
    let enhancementService: AIEnhancementService?
    var licenseViewModel: LicenseViewModel
    let logger = Logger(subsystem: "town.mullet.WhisperVillage", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    
    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloadingParakeet = false
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("town.mullet.WhisperVillage")
        
        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        self.parakeetModelsDirectory = appSupportDirectory
        
        self.enhancementService = enhancementService
        self.licenseViewModel = LicenseViewModel()
        
        super.init()
        
        // Configure the session manager
        if let enhancementService = enhancementService {
            PowerModeSessionManager.shared.configure(whisperState: self, enhancementService: enhancementService)
        }
        
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

            // If Jarvis streaming mode - handle transcription with captured samples
            if isStreamingModeEnabled && jarvisService.isEnabled {
                StreamingLogger.shared.log("=== TOGGLE RECORD STOP (Jarvis mode) ===")

                // Check if a voice command already did the final transcription (e.g., "Jarvis stop")
                // NOTE: We check voiceCommandSetFinalText flag, NOT buffer emptiness,
                // because the streaming preview continuously updates jarvisTranscriptionBuffer
                let voiceCommandProvidedText = voiceCommandSetFinalText

                // Reset the flag for next session
                voiceCommandSetFinalText = false

                // NOTE: Linger delay disabled because we stop the engine before playing sound
                // to avoid AVAudioEngine blocking sound playback

                // If no voice command handled it, transcribe the FULL audio now
                var textToPaste = ""
                if voiceCommandProvidedText {
                    // Voice command already transcribed and set jarvisTranscriptionBuffer
                    textToPaste = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    StreamingLogger.shared.log("Using voice command buffer (flag was set): \"\(textToPaste)\"")
                } else {
                    // OPTIMIZATION: Use interim transcription instead of re-transcribing
                    // Streaming already transcribed the full buffer, stored in interimTranscription
                    let interimText = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !interimText.isEmpty {
                        // Use the interim transcription (skip re-transcription - saves 500ms-1s!)
                        var allChunks = finalTranscribedChunks
                        allChunks.append(interimText)
                        textToPaste = allChunks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                        StreamingLogger.shared.log("FAST PATH: Using interim transcription: \"\(textToPaste.prefix(100))...\"")
                    } else {
                        // Fallback: interim was empty, do full transcription
                        StreamingLogger.shared.log("Fallback: Interim empty, transcribing \(capturedSamples.count) samples...")
                        if let transcribedText = await transcribeCapturedSamples(capturedSamples) {
                            let currentChunkText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            var allChunks = finalTranscribedChunks
                            if !currentChunkText.isEmpty {
                                allChunks.append(currentChunkText)
                            }
                            textToPaste = allChunks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                            StreamingLogger.shared.log("Fallback: Final text: \"\(textToPaste)\" (chunks: \(allChunks.count))")
                        }
                    }
                }

                // Recorders already stopped above before playing sound
                StreamingLogger.shared.log("Using \(capturedSamples.count) pre-captured samples")

                // Clear finalTranscribedChunks for next session
                finalTranscribedChunks = []

                if shouldCancelRecording || textToPaste.isEmpty {
                    // Cancelled or nothing to paste
                    await MainActor.run {
                        recordingState = .idle
                    }
                    await cleanupModelResources()
                    await dismissMiniRecorder()
                } else {
                    // Save to history for Option+Cmd+V
                    saveStreamingTranscriptionToHistory(textToPaste)

                    // Paste the final content
                    await MainActor.run {
                        recordingState = .idle
                    }

                    // Apply word replacements if enabled
                    var finalText = textToPaste
                    if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                        finalText = WordReplacementService.shared.applyReplacements(to: finalText)
                    }

                    // ML Cleanup - filler removal (if enabled)
                    if UserDefaults.standard.bool(forKey: "IsMLCleanupEnabled") {
                        // Try CoreML first (native, no Python server needed)
                        if #available(macOS 13.0, *), CoreMLCleanupService.shared.isAvailable {
                            finalText = CoreMLCleanupService.shared.cleanup(text: finalText)
                        } else {
                            // Fall back to HTTP-based cleanup
                            finalText = await MLCleanupService.shared.cleanup(text: finalText)
                        }
                    }

                    let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
                    if shouldAddSpace {
                        finalText += " "
                    }

                    let shouldSend = self.doubleTapSendPending
                    self.doubleTapSendPending = false
                    self.tripleTapTerminalPending = false  // No longer used, but clear it

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if shouldSend {
                            // Double-tap: paste + Enter
                            // 650ms delay to allow slower apps (like Claude Code terminals) to finish processing paste
                            StreamingLogger.shared.log("📋 DOUBLE-TAP: Pasting + Enter")
                            CursorPaster.pasteAtCursor(finalText)
                            SoundManager.shared.playSendSound()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                                CursorPaster.pressEnter()
                            }
                        } else {
                            // Normal paste at cursor (single tap stop)
                            StreamingLogger.shared.log("📋 -> Normal paste at cursor")
                            CursorPaster.pasteAtCursor(finalText)
                        }
                    }

                    await dismissMiniRecorder()
                }
                return
            }

            // ============================================================
            // SIMPLE STREAMING (Jarvis disabled) - Clean, simple path
            // No command detection, no chunks, no voice command flags
            // OPTIMIZED: Hides UI immediately for perceived responsiveness
            // NOTE: Audio engines already stopped above (before sound playback)
            //       We use capturedSamples instead of reading from the buffer
            // ============================================================
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

                // Recorders already stopped above (before sound playback)

                if shouldCancelRecording || textToPaste.isEmpty {
                    // Delete placeholder if we pasted one (cancelled or empty result)
                    if placeholderLength > 0 {
                        DispatchQueue.main.async {
                            CursorPaster.deleteCharacters(count: placeholderLength)
                        }
                        StreamingLogger.shared.log("Deleted placeholder (cancelled/empty)")
                    }
                    await MainActor.run {
                        recordingState = .idle
                        isInCommandMode = false  // Reset command mode on cancel
                    }
                    await cleanupModelResources()
                    await cleanupAfterSend()
                } else {
                    saveStreamingTranscriptionToHistory(textToPaste)

                    await MainActor.run {
                        recordingState = .idle
                    }

                    var finalText = textToPaste

                    // LLM Correction (if enabled) - runs before word replacements
                    finalText = await LLMCorrectionService.shared.correct(finalText)

                    // Word replacements (if enabled)
                    if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                        finalText = WordReplacementService.shared.applyReplacements(to: finalText)
                    }

                    // ML Cleanup - filler removal (if enabled)
                    if UserDefaults.standard.bool(forKey: "IsMLCleanupEnabled") {
                        // Try CoreML first (native, no Python server needed)
                        if #available(macOS 13.0, *), CoreMLCleanupService.shared.isAvailable {
                            finalText = CoreMLCleanupService.shared.cleanup(text: finalText)
                        } else {
                            // Fall back to HTTP-based cleanup
                            finalText = await MLCleanupService.shared.cleanup(text: finalText)
                        }
                    }

                    let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
                    if shouldAddSpace {
                        finalText += " "
                    }

                    // Delete placeholder if we pasted one, then paste real text
                    let shouldSend = self.doubleTapSendPending
                    self.doubleTapSendPending = false // Reset flag
                    self.tripleTapTerminalPending = false // No longer used, but clear it

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                        // Always delete placeholder first if present
                        if placeholderLength > 0 {
                            CursorPaster.deleteCharacters(count: placeholderLength)
                        }

                        if shouldSend {
                            // Double-tap: paste + Enter
                            // 650ms delay to allow slower apps (like Claude Code terminals) to finish processing paste
                            StreamingLogger.shared.log("📋 DOUBLE-TAP (Streaming): Pasting + Enter")
                            CursorPaster.pasteAtCursor(finalText)
                            SoundManager.shared.playSendSound()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
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

                            // Cache text context in background for smart capitalization
                            // Don't block MainActor - just fire and forget
                            Task.detached { @MainActor in
                                TextContextService.shared.cacheCurrentContext()
                            }

                            await MainActor.run {
                                StreamingLogger.shared.log("=== RECORDING START - CLEARING STATE ===")
                                StreamingLogger.shared.log("  debugLog.count BEFORE: \(self.debugLog.count)")

                                // Clear streaming preview and debug log from last session
                                self.interimTranscription = ""
                                self.debugLog = []  // Fresh debug log for new recording
                                self.recordingState = .recording

                                // Reset Jarvis command mode state
                                self.isInJarvisCommandMode = false
                                self.jarvisTranscriptionBuffer = ""
                                self.jarvisPreListenBuffer = ""
                                self.jarvisBufferStartSample = 0
                                self.lastExecutedJarvisCommandPart = ""  // Allow same command in new session
                                self.lastJarvisCommandTime = .distantPast
                                self.voiceCommandSetFinalText = false  // Reset flag for new session

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

                            await ActiveWindowService.shared.applyConfigurationForCurrentApp()
         
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
        
                            if let enhancementService = self.enhancementService,
                               enhancementService.useScreenCaptureContext {
                                await enhancementService.captureScreenContext()
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

    // MARK: - Stop Recording and Send (Paste + Enter)

    /// Stops recording, transcribes, pastes, and presses Enter to send
    /// This is similar to toggleRecord() stop path but also presses Enter after paste
    /// OPTIMIZED: Hides UI immediately for perceived responsiveness
    func stopRecordingAndSend() async {
        guard recordingState == .recording else { return }

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

                var finalText = textToPaste

                // LLM Correction (if enabled) - runs before word replacements
                finalText = await LLMCorrectionService.shared.correct(finalText)

                // Word replacements (if enabled)
                if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                    finalText = WordReplacementService.shared.applyReplacements(to: finalText)
                }

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
            isInJarvisCommandMode = false
        }
        StreamingLogger.shared.log("=== CLEANUP COMPLETE ===")
    }

    // MARK: - Peek Transcription (Show preview without stopping)

    /// Triggers a transcription of current audio and shows the result
    /// Recording continues after showing the preview
    func peekTranscription() async {
        guard recordingState == .recording else { return }

        guard isStreamingModeEnabled else {
            NotificationManager.shared.showNotification(
                title: "Peek requires streaming mode",
                type: .info,
                duration: 2.0
            )
            return
        }

        StreamingLogger.shared.log("=== PEEK TRANSCRIPTION ===")

        var currentText = ""

        if isLivePreviewEnabled {
            // Live Preview ON: Use the already-computed interim transcription
            currentText = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            StreamingLogger.shared.log("Peek (live preview): \"\(currentText)\"")
        } else {
            // Simple Mode: Do an on-demand transcription of current audio buffer
            // Note: This transcribes but doesn't stop recording
            StreamingLogger.shared.log("Peek (simple mode): Transcribing current audio...")
            if let transcribedText = await transcribeFullAudioBuffer(clearBufferAfter: false) {
                currentText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            StreamingLogger.shared.log("Peek (simple mode) result: \"\(currentText)\"")
        }

        if currentText.isEmpty {
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
                text: currentText,
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
            case .nativeApple:
                transcriptionService = nativeAppleTranscriptionService
            default:
                transcriptionService = cloudTranscriptionService
            }

            let transcriptionStart = Date()
            var text = try await transcriptionService.transcribe(audioURL: url, model: model)
            let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
            
            if await checkCancellationAndCleanup() { return }
            
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Always fix common Whisper transcription errors (e.g., I' -> I'm)
            text = WordReplacementService.shared.applyBuiltInFixes(to: text)

            if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                text = WordReplacementService.shared.applyReplacements(to: text)
            }

            let audioAsset = AVURLAsset(url: url)
            let actualDuration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0
            var promptDetectionResult: PromptDetectionService.PromptDetectionResult? = nil
            let originalText = text
            
            if let enhancementService = enhancementService, enhancementService.isConfigured {
                let detectionResult = promptDetectionService.analyzeText(text, with: enhancementService)
                promptDetectionResult = detectionResult
                await promptDetectionService.applyDetectionResult(detectionResult, to: enhancementService)
            }
            
            if let enhancementService = enhancementService,
               enhancementService.isEnhancementEnabled,
               enhancementService.isConfigured {
                do {
                    if await checkCancellationAndCleanup() { return }

                    await MainActor.run { self.recordingState = .enhancing }
                    let textForAI = promptDetectionResult?.processedText ?? text
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    let newTranscription = Transcription(
                        text: originalText,
                        duration: actualDuration,
                        enhancedText: enhancedText,
                        audioFileURL: url.absoluteString,
                        transcriptionModelName: model.displayName,
                        aiEnhancementModelName: enhancementService.getAIService()?.currentModel,
                        promptName: promptName,
                        transcriptionDuration: transcriptionDuration,
                        enhancementDuration: enhancementDuration
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: newTranscription)
                    text = enhancedText
                } catch {
                    let newTranscription = Transcription(
                        text: originalText,
                        duration: actualDuration,
                        enhancedText: "Enhancement failed: \(error)",
                        audioFileURL: url.absoluteString,
                        transcriptionModelName: model.displayName,
                        promptName: nil,
                        transcriptionDuration: transcriptionDuration
                    )
                    modelContext.insert(newTranscription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: newTranscription)
                    
                    await MainActor.run {
                        NotificationManager.shared.showNotification(
                            title: "AI enhancement failed",
                            type: .error
                        )
                    }
                }
            } else {
                let newTranscription = Transcription(
                    text: originalText,
                    duration: actualDuration,
                    audioFileURL: url.absoluteString,
                    transcriptionModelName: model.displayName,
                    promptName: nil,
                    transcriptionDuration: transcriptionDuration
                )
                modelContext.insert(newTranscription)
                try? modelContext.save()
                NotificationCenter.default.post(name: .transcriptionCreated, object: newTranscription)
            }
            

            let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
            if shouldAddSpace {
                text += " "
            }

            if await checkCancellationAndCleanup() { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                CursorPaster.pasteAtCursor(text)

                // Check if we should press Enter (power mode auto-send)
                let powerMode = PowerModeManager.shared
                if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
                    // Slight delay to ensure the paste operation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        CursorPaster.pressEnter()
                    }
                }
            }
            
            if let result = promptDetectionResult,
               let enhancementService = enhancementService,
               result.shouldEnableAI {
                await promptDetectionService.restoreOriginalSettings(result, to: enhancementService)
            }
            
            await self.dismissMiniRecorder()
            
        } catch {
            do {
                let audioAsset = AVURLAsset(url: url)
                let duration = (try? CMTimeGetSeconds(await audioAsset.load(.duration))) ?? 0.0
                
                await MainActor.run {
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let recoverySuggestion = (error as? LocalizedError)?.recoverySuggestion ?? ""
                    let fullErrorText = recoverySuggestion.isEmpty ? errorDescription : "\(errorDescription) \(recoverySuggestion)"
                    
                    let failedTranscription = Transcription(
                        text: "Transcription Failed: \(fullErrorText)",
                        duration: duration,
                        enhancedText: nil,
                        audioFileURL: url.absoluteString,
                        promptName: nil
                    )
                    
                    modelContext.insert(failedTranscription)
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .transcriptionCreated, object: failedTranscription)
                }
            } catch {
                logger.error("❌ Could not create a record for the failed transcription: \(error.localizedDescription)")
            }
            
            // Show error in recorder UI instead of dismissing
            await MainActor.run {
                recordingState = .error(message: "Transcription failed")
                miniRecorderError = "Transcription failed"
            }
        }
    }

    func getEnhancementService() -> AIEnhancementService? {
        return enhancementService
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
        // ============================================================
        // JARVIS BYPASS: When Jarvis is disabled, use simple path
        // No command mode, no command detection, just transcription
        // ============================================================
        let jarvisEnabled = jarvisService.isEnabled

        // Skip if in Jarvis command mode (only possible if Jarvis is enabled)
        if jarvisEnabled && isInJarvisCommandMode {
            // Still check for Jarvis commands even in command mode
            // Add delay to prevent tight loop (the function is sync, returns immediately)
            checkForJarvisCommandInCommandMode()
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms - commands don't need fast polling
            return
        }

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
        // Apply built-in fixes (e.g., I' -> I'm) to preview
        if !transcriptionResult.isEmpty {
            let fixedText = WordReplacementService.shared.applyBuiltInFixes(to: transcriptionResult)
            interimTranscription = fixedText

            // Update live preview box if in box mode
            if isLivePreviewBoxMode {
                NotificationManager.shared.updateLiveBox(text: fixedText)
            }

            // JARVIS: Only update Jarvis buffers and check for commands if enabled
            if jarvisEnabled {
                jarvisTranscriptionBuffer = fixedText
                checkForVoiceCommand(in: fixedText)
            }
        }

        isStreamingTranscriptionInProgress = false
    }

    /// Check for Jarvis commands while in command mode (minimal transcription just for command detection)
    private func checkForJarvisCommandInCommandMode() {
        guard jarvisService.isEnabled else { return }

        // We need to transcribe to detect commands, but we do a quick transcription
        // just to check for "Jarvis listen" or other commands
        Task { @MainActor in
            guard !isStreamingTranscriptionInProgress else { return }
            guard let model = currentTranscriptionModel else { return }

            // Get recent samples (last 3 seconds should be enough for command detection)
            let recentSampleCount = 16000 * 3  // 3 seconds
            let totalSamples = await streamingRecorder.getCurrentSampleCount()
            let startIndex = max(0, totalSamples - recentSampleCount)
            let samples = await streamingRecorder.getSamplesFromIndex(startIndex)

            guard samples.count > 8000 else { return }  // Need at least 0.5s

            isStreamingTranscriptionInProgress = true

            var text = ""
            if model.provider == .parakeet {
                text = (try? await parakeetTranscriptionService.transcribeSamples(samples)) ?? ""
            } else if model.provider == .local, let context = whisperContext {
                if await context.fullTranscribe(samples: samples) {
                    text = await context.getTranscription()
                }
            }

            isStreamingTranscriptionInProgress = false

            // Check for Jarvis command in the transcribed text
            // Guard against duplicate execution (same pattern as checkForVoiceCommand)
            guard !isExecutingJarvisCommand else {
                StreamingLogger.shared.log("checkForJarvisCommandInCommandMode: Skipping - already executing a command")
                return
            }

            if !text.isEmpty, let jarvisCommand = jarvisService.detectCommand(in: text) {
                StreamingLogger.shared.log("Jarvis command detected in command mode: \"\(jarvisCommand.commandPart)\"")
                isExecutingJarvisCommand = true
                defer { isExecutingJarvisCommand = false }
                await executeJarvisCommand(jarvisCommand, fullText: text)
            }
        }
    }

    // MARK: - Jarvis Command Detection

    /// Check if the transcription contains a Jarvis command
    private func checkForVoiceCommand(in text: String) {
        // Don't detect new commands while one is executing (prevents duplicate Task spawning)
        // This guard must be BEFORE spawning any Task - otherwise multiple Tasks race to set the flag
        guard !isExecutingJarvisCommand else {
            StreamingLogger.shared.log("checkForVoiceCommand: Skipping - already executing a command")
            return
        }

        // Check for Jarvis command (if enabled)
        if jarvisService.isEnabled {
            // In full buffer mode, text IS the full transcription
            let fullText = text

            if let jarvisCommand = jarvisService.detectCommand(in: fullText) {
                StreamingLogger.shared.log("Jarvis command detected: \"\(jarvisCommand.commandPart)\"")

                // Set flag BEFORE spawning Task to prevent race condition
                // Multiple transcriptions could detect the same command before any Task starts executing
                isExecutingJarvisCommand = true

                // Execute command - visual feedback is handled in executeJarvisCommand
                Task { @MainActor in
                    defer { self.isExecutingJarvisCommand = false }  // ALWAYS clear, even if guards return early
                    await self.executeJarvisCommand(jarvisCommand, fullText: fullText)
                }
                return
            }
        }
    }

    // MARK: - Streaming History Saving

    /// Save a streaming transcription to history (for Option+Cmd+V paste-last-message)
    private func saveStreamingTranscriptionToHistory(_ text: String) {
        guard !text.isEmpty else { return }

        let newTranscription = Transcription(
            text: text,
            duration: 0,  // No duration info available in streaming mode
            transcriptionModelName: currentTranscriptionModel?.displayName ?? "Streaming"
        )
        modelContext.insert(newTranscription)
        try? modelContext.save()
        NotificationCenter.default.post(name: .transcriptionCreated, object: newTranscription)
        StreamingLogger.shared.log("History: Saved transcription to history (\(text.prefix(30))...)")
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

        // Apply built-in fixes (e.g., I' -> I'm)
        if !transcribedText.isEmpty {
            transcribedText = WordReplacementService.shared.applyBuiltInFixes(to: transcribedText)
        }

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

        // Apply built-in fixes (e.g., I' -> I'm)
        if !transcribedText.isEmpty {
            transcribedText = WordReplacementService.shared.applyBuiltInFixes(to: transcribedText)
        }

        // Clear buffer if requested (used after pause to start fresh)
        if clearBufferAfter {
            await streamingRecorder.clearBuffer()
            StreamingLogger.shared.log("Final transcription: Buffer cleared")
        }

        return transcribedText
    }

    // MARK: - Jarvis Command Execution

    /// Execute a Jarvis command
    @MainActor
    private func executeJarvisCommand(_ command: JarvisCommandService.DetectedCommand, fullText: String) async {
        guard recordingState == .recording else { return }

        // Prevent re-executing similar commands (compare commandPart + time debounce)
        // Note: duplicate execution prevention is now handled in checkForVoiceCommand() via isExecutingJarvisCommand flag
        let timeSinceLastCommand = Date().timeIntervalSince(lastJarvisCommandTime)
        let normalizedCommandPart = command.commandPart.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isSimilarCommand = normalizedCommandPart.hasPrefix(lastExecutedJarvisCommandPart.lowercased()) ||
                               lastExecutedJarvisCommandPart.lowercased().hasPrefix(normalizedCommandPart)

        if isSimilarCommand && timeSinceLastCommand < 3.0 {
            StreamingLogger.shared.log("Jarvis: Skipping - similar command within 3s: \"\(command.commandPart)\" (last: \"\(lastExecutedJarvisCommandPart)\")")
            return
        }

        lastExecutedJarvisCommandPart = normalizedCommandPart
        lastJarvisCommandTime = Date()

        // DEBUG: Log all state before execution
        StreamingLogger.shared.log("=== JARVIS COMMAND START ===")
        StreamingLogger.shared.log("  Command: \"\(command.commandPart)\"")
        StreamingLogger.shared.log("  command.textBefore: \"\(command.textBefore)\"")
        StreamingLogger.shared.log("  command.fullPhrase: \"\(command.fullPhrase)\"")
        StreamingLogger.shared.log("  fullText param: \"\(fullText)\"")
        StreamingLogger.shared.log("  isInJarvisCommandMode: \(isInJarvisCommandMode)")
        StreamingLogger.shared.log("  jarvisTranscriptionBuffer: \"\(jarvisTranscriptionBuffer)\"")

        // Execute the command first to determine result type
        let result = await jarvisService.execute(command)
        StreamingLogger.shared.log("  Execution result: \(result)")

        // For resumeListening, clear buffer and start fresh
        // Text was already saved to finalTranscribedChunks during pause
        if case .resumeListening = result {
            StreamingLogger.shared.log("  -> RESUME LISTENING (early return path)")

            // Clear the audio buffer - text is already saved, audio is disposable
            await streamingRecorder.clearBuffer()
            StreamingLogger.shared.log("     Cleared audio buffer for fresh start")

            // Add listening indicator to show we're ready to transcribe again
            debugLog.append(.listening())

            isInJarvisCommandMode = false
            // Clear the preview - we're starting fresh
            interimTranscription = ""
            jarvisTranscriptionBuffer = ""
            StreamingLogger.shared.log("=== JARVIS RESUME COMPLETE === Starting fresh transcription")
            return
        }

        // For other commands, strip the command from the buffer - only keep text before "Jarvis X"
        // BUT: If we're already in command mode, DON'T overwrite the buffer with command.textBefore
        // because textBefore comes from the short detection window, not the full accumulated buffer
        StreamingLogger.shared.log("  -> STRIPPING COMMAND (non-resumeListening path)")
        StreamingLogger.shared.log("     command.textBefore: \"\(command.textBefore)\"")
        StreamingLogger.shared.log("     isInJarvisCommandMode: \(isInJarvisCommandMode)")
        StreamingLogger.shared.log("     jarvisTranscriptionBuffer BEFORE: \"\(jarvisTranscriptionBuffer)\"")

        if isInJarvisCommandMode {
            // Already in command mode - keep the preserved buffer, don't overwrite
            StreamingLogger.shared.log("     -> Already in command mode, preserving buffer")
        } else {
            // Not in command mode - use textBefore to strip the command
            let cleanedText = command.textBefore.trimmingCharacters(in: .whitespacesAndNewlines)
            StreamingLogger.shared.log("     cleanedText: \"\(cleanedText)\"")
            jarvisTranscriptionBuffer = cleanedText
            StreamingLogger.shared.log("     jarvisTranscriptionBuffer AFTER: \"\(jarvisTranscriptionBuffer)\"")

            // Update visual state to show cleaned text (without the command)
            interimTranscription = cleanedText
            StreamingLogger.shared.log("     interimTranscription: \"\(interimTranscription)\"")
        }

        switch result {
        case .sendAndContinue:
            // Transcribe FULL audio buffer, concatenate with saved chunks, paste + Enter
            StreamingLogger.shared.log("  -> SEND AND CONTINUE case")

            // Transcribe current audio buffer (final, not preview)
            var currentChunkText = ""
            if let transcribedText = await transcribeFullAudioBuffer(clearBufferAfter: true) {
                let cleanText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip the Jarvis command from the transcribed text
                currentChunkText = jarvisService.stripCommand(command, from: cleanText)
            }

            // Concatenate all saved chunks + current chunk
            var allChunks = finalTranscribedChunks
            if !currentChunkText.isEmpty {
                allChunks.append(currentChunkText)
            }
            let textToPaste = allChunks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            if !textToPaste.isEmpty {
                // Add sent text to debug log with checkmark styling
                debugLog.append(.sentTranscription(text: textToPaste))
                // Add command indicator after transcription
                debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: "sent"))
                StreamingLogger.shared.log("Jarvis: Sending FINAL: \"\(textToPaste)\" (chunks: \(allChunks.count))")
                // Save to history for Option+Cmd+V paste-last-message
                saveStreamingTranscriptionToHistory(textToPaste)
                CursorPaster.pasteAtCursor(textToPaste)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    CursorPaster.pressEnter()
                }
            }

            // Clear everything and enter command mode
            finalTranscribedChunks = []
            jarvisTranscriptionBuffer = ""
            jarvisPreListenBuffer = ""
            interimTranscription = ""
            isInJarvisCommandMode = true
            StreamingLogger.shared.log("Jarvis: Sent, now in command mode")

        case .sendAndStop:
            // Transcribe FULL audio buffer, concatenate with saved chunks, paste (no Enter), stop
            StreamingLogger.shared.log("  -> SEND AND STOP case")

            // Transcribe current audio buffer (final, not preview)
            var currentChunkText = ""
            if let transcribedText = await transcribeFullAudioBuffer(clearBufferAfter: false) {
                let cleanText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Strip the Jarvis command from the transcribed text
                currentChunkText = jarvisService.stripCommand(command, from: cleanText)
            }

            // Concatenate all saved chunks + current chunk
            var allChunks = finalTranscribedChunks
            if !currentChunkText.isEmpty {
                allChunks.append(currentChunkText)
            }
            let textToPaste = allChunks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            if !textToPaste.isEmpty {
                debugLog.append(.sentTranscription(text: textToPaste))
                debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: "stopped"))
                // Save to history for Option+Cmd+V paste-last-message
                saveStreamingTranscriptionToHistory(textToPaste)
            }

            // Store final text for toggleRecord to paste
            jarvisTranscriptionBuffer = textToPaste
            voiceCommandSetFinalText = true  // Signal that voice command set this, not preview
            finalTranscribedChunks = []  // Clear for next session
            StreamingLogger.shared.log("Jarvis: Stopping with FINAL buffer: \"\(textToPaste)\" (chunks: \(allChunks.count))")
            await toggleRecord()

        case .navigated:
            // App/tab was focused, enter command mode, preserve buffer
            StreamingLogger.shared.log("  -> NAVIGATED case (already in command mode: \(isInJarvisCommandMode))")

            // Only add transcription to debugLog if we weren't already in command mode (prevents duplicates)
            if !isInJarvisCommandMode {
                let textBeforeNavigate = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !textBeforeNavigate.isEmpty {
                    debugLog.append(.transcription(text: textBeforeNavigate))
                    StreamingLogger.shared.log("     Added to debugLog: \"\(textBeforeNavigate)\"")
                }
            }
            // Always add navigation command indicator (even if already in command mode)
            debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: command.commandPart))
            StreamingLogger.shared.log("     Added navigation indicator: \"\(command.commandPart)\"")

            isInJarvisCommandMode = true
            jarvisPreListenBuffer = jarvisTranscriptionBuffer
            StreamingLogger.shared.log("Jarvis: Navigated, now in command mode (buffer saved: \"\(jarvisTranscriptionBuffer)\", debugLog count: \(debugLog.count))")

        case .cancelled:
            // Discard everything, stop recording
            // No debug log entry - recording will end
            StreamingLogger.shared.log("Jarvis: Cancelling recording")
            jarvisTranscriptionBuffer = ""
            shouldCancelRecording = true
            await toggleRecord()

        case .paused:
            // Enter command mode - transcribe FULL audio buffer and save to finalTranscribedChunks
            StreamingLogger.shared.log("  -> PAUSED case (already in command mode: \(isInJarvisCommandMode))")

            // Only transcribe and save if we weren't already in command mode
            if !isInJarvisCommandMode {
                // Transcribe the FULL audio buffer (this is the REAL output, not preview)
                if let transcribedText = await transcribeFullAudioBuffer(clearBufferAfter: true) {
                    let cleanText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Strip the Jarvis command from the transcribed text
                    let textBeforeCommand = jarvisService.stripCommand(command, from: cleanText)
                    if !textBeforeCommand.isEmpty {
                        finalTranscribedChunks.append(textBeforeCommand)
                        debugLog.append(.transcription(text: textBeforeCommand))
                        StreamingLogger.shared.log("     FINAL chunk saved: \"\(textBeforeCommand)\"")
                    }
                }
                // Add pause command indicator
                debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: "paused"))
            } else {
                StreamingLogger.shared.log("     Skipping - already in command mode")
            }

            isInJarvisCommandMode = true
            // Clear live preview - saved chunks are in finalTranscribedChunks
            interimTranscription = ""
            StreamingLogger.shared.log("=== JARVIS PAUSED COMPLETE === finalChunks: \(finalTranscribedChunks.count), debugLog count: \(debugLog.count)")

        case .resumeListening:
            // Already handled above with early return - this case shouldn't be reached
            break

        case .failed(let error):
            StreamingLogger.shared.log("Jarvis command failed: \(error)")
            // Stay in current mode, don't change anything
        }
    }
}

