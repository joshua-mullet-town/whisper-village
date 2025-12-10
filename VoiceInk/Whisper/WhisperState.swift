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
    @Published var recordingState: RecordingState = .idle
    @Published var isModelLoaded = false
    @Published var loadedLocalModel: WhisperModel?
    @Published var currentTranscriptionModel: (any TranscriptionModel)?
    @Published var isModelLoading = false
    @Published var availableModels: [WhisperModel] = []
    @Published var allAvailableModels: [any TranscriptionModel] = PredefinedModels.models
    @Published var clipboardMessage = ""
    @Published var miniRecorderError: String?
    @Published var shouldCancelRecording = false


    @Published var recorderType: String = UserDefaults.standard.string(forKey: "RecorderType") ?? "mini" {
        didSet {
            UserDefaults.standard.set(recorderType, forKey: "RecorderType")
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

    // MARK: - Streaming Transcription (Chunk-Commit)
    private var streamingTranscriptionTimer: Timer?
    private var isStreamingTranscriptionInProgress = false

    /// Committed chunks (locked in, won't change)
    @Published var committedChunks: [String] = []

    /// Current live preview (still being corrected)
    @Published var interimTranscription: String = ""

    /// Debug log entries for the current recording session (never cleared until new recording starts)
    @Published var debugLog: [DebugLogEntry] = []

    /// When the current chunk started (sample index in the buffer)
    private var currentChunkStartSample: Int = 0

    /// How often to run interim transcription (in seconds)
    private let streamingIntervalSeconds: TimeInterval = 1.0

    /// How long before committing a chunk (in seconds)
    private let chunkCommitIntervalSeconds: TimeInterval = 30.0

    /// Timer to track when to commit chunks
    private var chunkStartTime: Date?

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
    let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "WhisperState")
    var notchWindowManager: NotchWindowManager?
    var miniWindowManager: MiniWindowManager?
    
    // For model progress tracking
    @Published var downloadProgress: [String: Double] = [:]
    @Published var isDownloadingParakeet = false
    
    init(modelContext: ModelContext, enhancementService: AIEnhancementService? = nil) {
        self.modelContext = modelContext
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        
        self.modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")
        self.recordingsDirectory = appSupportDirectory.appendingPathComponent("Recordings")
        self.parakeetModelsDirectory = appSupportDirectory.appendingPathComponent("ParakeetModels")
        
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
    }
    
    private func createRecordingsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            logger.error("Error creating recordings directory: \(error.localizedDescription)")
        }
    }
    
    func toggleRecord() async {
        if recordingState == .recording {
            // Stop streaming transcription and recorder if enabled
            if isStreamingModeEnabled {
                stopStreamingTranscription()
                let samples = await streamingRecorder.stopRecording()
                StreamingLogger.shared.log("Streaming stopped. Got \(samples.count) samples (\(String(format: "%.2f", Double(samples.count) / 16000.0)) seconds)")
            }

            await recorder.stopRecording()

            // If Jarvis streaming mode was used, use the buffer directly instead of re-transcribing
            if isStreamingModeEnabled && jarvisService.isEnabled {
                let textToPaste = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                StreamingLogger.shared.log("Using Jarvis buffer for final paste: \"\(textToPaste)\"")

                if shouldCancelRecording || textToPaste.isEmpty {
                    // Cancelled or nothing to paste
                    await MainActor.run {
                        recordingState = .idle
                    }
                    await cleanupModelResources()
                    await dismissMiniRecorder()
                } else {
                    // Paste the buffer content directly
                    await MainActor.run {
                        recordingState = .idle
                    }

                    // Apply word replacements if enabled
                    var finalText = textToPaste
                    if UserDefaults.standard.bool(forKey: "IsWordReplacementEnabled") {
                        finalText = WordReplacementService.shared.applyReplacements(to: finalText)
                    }

                    let shouldAddSpace = UserDefaults.standard.object(forKey: "AppendTrailingSpace") as? Bool ?? true
                    if shouldAddSpace {
                        finalText += " "
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        CursorPaster.pasteAtCursor(finalText)
                    }

                    await dismissMiniRecorder()
                }
                return
            }

            // Fall back to traditional transcription for non-Jarvis mode
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
                                self.committedChunks = []
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

                                StreamingLogger.shared.log("  debugLog.count AFTER clear: \(self.debugLog.count)")
                                StreamingLogger.shared.log("=== RECORDING START COMPLETE ===")
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
                            if self.isStreamingModeEnabled {
                                if let model = self.currentTranscriptionModel,
                                   (model.provider == .local || model.provider == .parakeet) {
                                    self.startStreamingTranscription()
                                } else {
                                    StreamingLogger.shared.log("Streaming transcription only works with local/parakeet models (current: \(self.currentTranscriptionModel?.provider.rawValue ?? "none"))")
                                }
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
        
        // Play stop sound when transcription starts with a small delay
        Task {
            let isSystemMuteEnabled = UserDefaults.standard.bool(forKey: "isSystemMuteEnabled")
            if isSystemMuteEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200 milliseconds delay
            }
            await MainActor.run {
                SoundManager.shared.playStopSound()
            }
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
            
            await MainActor.run {
                NotificationManager.shared.showNotification(
                    title: "Transcription Failed",
                    type: .error
                )
            }
            
            await self.dismissMiniRecorder()
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

    /// Start the streaming transcription timer
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

        StreamingLogger.shared.log("Starting streaming transcription timer (every \(streamingIntervalSeconds)s, commit every \(chunkCommitIntervalSeconds)s) [provider: \(model.provider.rawValue)]")

        // Reset chunk tracking
        committedChunks = []
        interimTranscription = ""
        currentChunkStartSample = 0
        chunkStartTime = Date()

        // Create timer on main thread
        streamingTranscriptionTimer = Timer.scheduledTimer(withTimeInterval: streamingIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performInterimTranscription()
            }
        }
    }

    /// Stop the streaming transcription timer
    func stopStreamingTranscription() {
        StreamingLogger.shared.log("Stopping streaming transcription timer")
        streamingTranscriptionTimer?.invalidate()
        streamingTranscriptionTimer = nil
        isStreamingTranscriptionInProgress = false

        // Commit any remaining interim transcription as final chunk
        if !interimTranscription.isEmpty {
            committedChunks.append(interimTranscription)
            debugLog.append(.transcription(text: interimTranscription))
            StreamingLogger.shared.log("Committed final chunk: \"\(interimTranscription)\"")
        }

        interimTranscription = ""
        chunkStartTime = nil
    }

    /// Clear all streaming UI (call after final transcription is shown)
    func clearStreamingPreview() {
        committedChunks = []
        interimTranscription = ""
    }

    /// Perform one interim transcription on the current chunk
    private func performInterimTranscription() async {
        // Skip if in Jarvis command mode (not transcribing, waiting for commands)
        if isInJarvisCommandMode {
            // Still check for Jarvis commands even in command mode
            // (to detect "Jarvis listen" or other commands)
            checkForJarvisCommandInCommandMode()
            return
        }

        // Skip if already transcribing (previous one still running)
        guard !isStreamingTranscriptionInProgress else {
            StreamingLogger.shared.log("Skipping interim transcription - previous still in progress")
            return
        }

        // Get current model
        guard let model = currentTranscriptionModel else {
            StreamingLogger.shared.log("Skipping interim transcription - no model selected")
            return
        }

        // Check if it's time to commit the current chunk
        if let startTime = chunkStartTime,
           Date().timeIntervalSince(startTime) >= chunkCommitIntervalSeconds,
           !interimTranscription.isEmpty {
            // Commit current chunk
            committedChunks.append(interimTranscription)
            debugLog.append(.transcription(text: interimTranscription))
            StreamingLogger.shared.log("Committed chunk \(committedChunks.count): \"\(interimTranscription)\"")

            // Reset for new chunk
            interimTranscription = ""
            currentChunkStartSample = await streamingRecorder.getCurrentSampleCount()
            chunkStartTime = Date()
        }

        // Get samples for current chunk only (from chunk start to now)
        let samples = await streamingRecorder.getSamplesFromIndex(currentChunkStartSample)

        guard samples.count > 0 else {
            StreamingLogger.shared.log("Skipping interim transcription - no samples in current chunk")
            return
        }

        let sampleDuration = Double(samples.count) / 16000.0
        StreamingLogger.shared.log("Transcribing chunk \(committedChunks.count + 1) with \(samples.count) samples (\(String(format: "%.2f", sampleDuration))s) [provider: \(model.provider.rawValue)]")

        isStreamingTranscriptionInProgress = true
        let startTime = Date()

        // Run transcription based on provider
        var trimmedText = ""

        if model.provider == .parakeet {
            // Use Parakeet
            do {
                let text = try await parakeetTranscriptionService.transcribeSamples(samples)
                trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let elapsed = Date().timeIntervalSince(startTime)
                StreamingLogger.shared.log("Parakeet interim result (\(String(format: "%.2f", elapsed))s): \"\(trimmedText)\"")
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                StreamingLogger.shared.log("Parakeet interim transcription failed after \(String(format: "%.2f", elapsed))s: \(error)")
            }
        } else if model.provider == .local, let context = whisperContext {
            // Use Whisper
            let success = await context.fullTranscribe(samples: samples)
            let elapsed = Date().timeIntervalSince(startTime)

            if success {
                let text = await context.getTranscription()
                trimmedText = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                StreamingLogger.shared.log("Whisper interim result (\(String(format: "%.2f", elapsed))s): \"\(trimmedText)\"")
            } else {
                StreamingLogger.shared.log("Whisper interim transcription failed after \(String(format: "%.2f", elapsed))s")
            }
        }

        // Apply built-in fixes (e.g., I' -> I'm) to streaming preview
        if !trimmedText.isEmpty {
            trimmedText = WordReplacementService.shared.applyBuiltInFixes(to: trimmedText)
            interimTranscription = trimmedText

            // DON'T log every interim update - only log when chunks commit
            // The interimTranscription updates in place in the view

            // Update Jarvis buffer (only when not in command mode, which we already checked above)
            // committedChunks already contains any preserved pre-listen content, so just combine
            // all chunks + current interim to get the full buffer
            let currentSessionText = (committedChunks + [trimmedText]).joined(separator: " ")
            jarvisTranscriptionBuffer = currentSessionText

            // Check for voice commands at end of transcription
            checkForVoiceCommand(in: trimmedText)
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
            if !text.isEmpty, let jarvisCommand = jarvisService.detectCommand(in: text) {
                StreamingLogger.shared.log("Jarvis command detected in command mode: \"\(jarvisCommand.commandPart)\"")
                await executeJarvisCommand(jarvisCommand, fullText: text)
            }
        }
    }

    // MARK: - Jarvis Command Detection

    /// Check if the transcription contains a Jarvis command
    private func checkForVoiceCommand(in text: String) {
        // Check for Jarvis command (if enabled)
        if jarvisService.isEnabled {
            // Build full text from all chunks + current interim
            var fullText = committedChunks.joined(separator: " ")
            if !text.isEmpty {
                if !fullText.isEmpty { fullText += " " }
                fullText += text
            }

            if let jarvisCommand = jarvisService.detectCommand(in: fullText) {
                StreamingLogger.shared.log("Jarvis command detected: \"\(jarvisCommand.commandPart)\"")
                // Execute command - visual feedback is handled in executeJarvisCommand
                // (transcription bubble shows text, pause indicator/checkmark shows state)
                Task { @MainActor in
                    await self.executeJarvisCommand(jarvisCommand, fullText: fullText)
                }
                return
            }
        }
    }

    // MARK: - Jarvis Command Execution

    /// Execute a Jarvis command
    @MainActor
    private func executeJarvisCommand(_ command: JarvisCommandService.DetectedCommand, fullText: String) async {
        guard recordingState == .recording else { return }

        // Check if this is a built-in command FIRST (before duplicate check)
        // Built-in commands should be able to interrupt slow LLM commands
        let isBuiltInCommand = jarvisService.isBuiltInCommand(command.commandPart)

        // Prevent duplicate execution (but allow built-in commands to interrupt)
        if isExecutingJarvisCommand && !isBuiltInCommand {
            StreamingLogger.shared.log("Jarvis: Skipping - already executing a command (not built-in)")
            return
        }

        // Prevent re-executing similar commands (compare commandPart + time debounce)
        let timeSinceLastCommand = Date().timeIntervalSince(lastJarvisCommandTime)
        let normalizedCommandPart = command.commandPart.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isSimilarCommand = normalizedCommandPart.hasPrefix(lastExecutedJarvisCommandPart.lowercased()) ||
                               lastExecutedJarvisCommandPart.lowercased().hasPrefix(normalizedCommandPart)

        if isSimilarCommand && timeSinceLastCommand < 3.0 {
            StreamingLogger.shared.log("Jarvis: Skipping - similar command within 3s: \"\(command.commandPart)\" (last: \"\(lastExecutedJarvisCommandPart)\")")
            return
        }

        isExecutingJarvisCommand = true
        lastExecutedJarvisCommandPart = normalizedCommandPart
        lastJarvisCommandTime = Date()
        defer { isExecutingJarvisCommand = false }

        // DEBUG: Log all state before execution
        StreamingLogger.shared.log("=== JARVIS COMMAND START ===")
        StreamingLogger.shared.log("  Command: \"\(command.commandPart)\"")
        StreamingLogger.shared.log("  command.textBefore: \"\(command.textBefore)\"")
        StreamingLogger.shared.log("  command.fullPhrase: \"\(command.fullPhrase)\"")
        StreamingLogger.shared.log("  fullText param: \"\(fullText)\"")
        StreamingLogger.shared.log("  isInJarvisCommandMode: \(isInJarvisCommandMode)")
        StreamingLogger.shared.log("  jarvisTranscriptionBuffer: \"\(jarvisTranscriptionBuffer)\"")
        StreamingLogger.shared.log("  jarvisPreListenBuffer: \"\(jarvisPreListenBuffer)\"")
        StreamingLogger.shared.log("  committedChunks: \(committedChunks)")

        // Execute the command first to determine result type
        let result = await jarvisService.execute(command)
        StreamingLogger.shared.log("  Execution result: \(result)")

        // For resumeListening, don't strip - just exit command mode
        // The buffer is already preserved from the pause
        if case .resumeListening = result {
            StreamingLogger.shared.log("  -> RESUME LISTENING (early return path)")
            StreamingLogger.shared.log("     jarvisTranscriptionBuffer before: \"\(jarvisTranscriptionBuffer)\"")

            // Add listening indicator to show we're ready to transcribe again
            debugLog.append(.listening())

            isInJarvisCommandMode = false
            // Visual: show the preserved buffer
            let existingText = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            StreamingLogger.shared.log("     existingText: \"\(existingText)\"")
            if !existingText.isEmpty && committedChunks.isEmpty {
                committedChunks = [existingText]
                StreamingLogger.shared.log("     Set committedChunks to: \(committedChunks)")
            }
            interimTranscription = ""
            currentChunkStartSample = streamingRecorder.sampleCount
            jarvisBufferStartSample = streamingRecorder.sampleCount
            chunkStartTime = Date()
            StreamingLogger.shared.log("=== JARVIS RESUME COMPLETE === buffer: \"\(jarvisTranscriptionBuffer)\", visual: \(committedChunks)")
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

            // Update visual state to show cleaned text (without the command) as a single chunk
            committedChunks = cleanedText.isEmpty ? [] : [cleanedText]
            interimTranscription = ""
            StreamingLogger.shared.log("     committedChunks: \(committedChunks)")
        }

        switch result {
        case .sendAndContinue:
            // Paste current buffer + Enter, clear buffer, enter command mode
            let textToPaste = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !textToPaste.isEmpty {
                // Add sent text to debug log with checkmark styling
                debugLog.append(.sentTranscription(text: textToPaste))
                // Add command indicator after transcription
                debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: "sent"))
                StreamingLogger.shared.log("Jarvis: Sending: \"\(textToPaste)\"")
                CursorPaster.pasteAtCursor(textToPaste)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    CursorPaster.pressEnter()
                }
            }

            // Clear buffer and enter command mode
            jarvisTranscriptionBuffer = ""
            jarvisPreListenBuffer = ""
            committedChunks = []
            interimTranscription = ""
            isInJarvisCommandMode = true
            StreamingLogger.shared.log("Jarvis: Sent, now in command mode")

        case .sendAndStop:
            // Paste current buffer (no Enter), stop recording
            let textToPaste = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !textToPaste.isEmpty {
                debugLog.append(.sentTranscription(text: textToPaste))
                debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: "stopped"))
            }
            jarvisTranscriptionBuffer = textToPaste  // Store for final paste
            StreamingLogger.shared.log("Jarvis: Stopping with buffer: \"\(textToPaste)\"")
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
            // Enter command mode, preserve buffer for when we resume
            StreamingLogger.shared.log("  -> PAUSED case (already in command mode: \(isInJarvisCommandMode))")
            StreamingLogger.shared.log("     jarvisTranscriptionBuffer before save: \"\(jarvisTranscriptionBuffer)\"")

            // Only add to debugLog if we weren't already in command mode (prevents duplicates)
            if !isInJarvisCommandMode {
                let textBeforePause = jarvisTranscriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !textBeforePause.isEmpty {
                    debugLog.append(.transcription(text: textBeforePause))
                    StreamingLogger.shared.log("     Added to debugLog: \"\(textBeforePause)\"")
                }
                // Add pause command indicator after transcription
                debugLog.append(.commandDetected(raw: command.fullPhrase, parsed: "paused"))
            } else {
                StreamingLogger.shared.log("     Skipping debugLog add - already in command mode")
            }

            isInJarvisCommandMode = true
            jarvisPreListenBuffer = jarvisTranscriptionBuffer
            StreamingLogger.shared.log("     jarvisPreListenBuffer after save: \"\(jarvisPreListenBuffer)\"")
            StreamingLogger.shared.log("=== JARVIS PAUSED COMPLETE === buffer: \"\(jarvisTranscriptionBuffer)\", preListen: \"\(jarvisPreListenBuffer)\", debugLog count: \(debugLog.count)")

        case .resumeListening:
            // Already handled above with early return - this case shouldn't be reached
            break

        case .failed(let error):
            StreamingLogger.shared.log("Jarvis command failed: \(error)")
            // Stay in current mode, don't change anything
        }
    }
}

