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

    /// When the current chunk started (sample index in the buffer)
    private var currentChunkStartSample: Int = 0

    /// How often to run interim transcription (in seconds)
    private let streamingIntervalSeconds: TimeInterval = 1.0

    /// How long before committing a chunk (in seconds)
    private let chunkCommitIntervalSeconds: TimeInterval = 30.0

    /// Timer to track when to commit chunks
    private var chunkStartTime: Date?

    // MARK: - Voice Commands
    /// Voice command actions
    enum VoiceCommandAction: String, Codable, CaseIterable {
        case stopAndPaste = "stop"              // Same as releasing hotkey
        case stopPasteAndEnter = "stopAndSend"  // Paste + hit Enter
        case sendAndContinue = "sendContinue"   // Paste + Enter + keep recording
        case focusApp = "focusApp"              // Focus an app, keep recording

        var displayName: String {
            switch self {
            case .stopAndPaste: return "Stop & Paste"
            case .stopPasteAndEnter: return "Stop, Paste & Send"
            case .sendAndContinue: return "Send & Continue"
            case .focusApp: return "Focus App"
            }
        }
    }

    /// Voice command model for persistence
    struct VoiceCommand: Codable, Identifiable, Equatable {
        var id = UUID()
        var phrase: String
        var action: VoiceCommandAction
        var targetApp: String?  // For focusApp action
    }

    /// Default voice commands
    static let defaultVoiceCommands: [VoiceCommand] = [
        VoiceCommand(phrase: "send it", action: .stopPasteAndEnter),
        VoiceCommand(phrase: "stop recording", action: .stopAndPaste),
        VoiceCommand(phrase: "execute", action: .stopPasteAndEnter),
        VoiceCommand(phrase: "next", action: .sendAndContinue),
        VoiceCommand(phrase: "go to chrome", action: .focusApp, targetApp: "Google Chrome"),
        VoiceCommand(phrase: "go to terminal", action: .focusApp, targetApp: "iTerm"),
        VoiceCommand(phrase: "go to safari", action: .focusApp, targetApp: "Safari"),
        VoiceCommand(phrase: "go to finder", action: .focusApp, targetApp: "Finder"),
    ]

    /// Load voice commands from UserDefaults or return defaults
    private var voiceCommandTriggers: [VoiceCommand] {
        if let data = UserDefaults.standard.data(forKey: "VoiceCommands"),
           let commands = try? JSONDecoder().decode([VoiceCommand].self, from: data) {
            return commands
        }
        return WhisperState.defaultVoiceCommands
    }

    /// Detected voice command (set during streaming, used during final transcription)
    private var detectedVoiceCommand: VoiceCommand?

    // Prompt detection service for trigger word handling
    private let promptDetectionService = PromptDetectionService()
    
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
                                // Clear streaming preview from last session
                                self.committedChunks = []
                                self.interimTranscription = ""
                                self.detectedVoiceCommand = nil  // Reset voice command detection
                                self.recordingState = .recording
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

            // Strip voice command trigger phrase from final text
            if let voiceCommand = detectedVoiceCommand {
                text = stripVoiceCommand(voiceCommand.phrase, from: text)
                StreamingLogger.shared.log("Stripped voice command \"\(voiceCommand.phrase)\" from final text")
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

                // Check if we should press Enter (voice command or power mode auto-send)
                let shouldPressEnter: Bool = {
                    // Voice command requested Enter
                    if let voiceCommand = detectedVoiceCommand, voiceCommand.action == .stopPasteAndEnter {
                        StreamingLogger.shared.log("Voice command action: pressing Enter")
                        return true
                    }
                    // Power mode auto-send enabled
                    let powerMode = PowerModeManager.shared
                    if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.isAutoSendEnabled {
                        return true
                    }
                    return false
                }()

                if shouldPressEnter {
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

            // Check for voice commands at end of transcription
            checkForVoiceCommand(in: trimmedText)
        }

        isStreamingTranscriptionInProgress = false
    }

    // MARK: - Voice Command Detection

    /// Check if the transcription ends with a voice command trigger phrase
    private func checkForVoiceCommand(in text: String) {
        // Already detected a command in this session? Don't detect again.
        guard detectedVoiceCommand == nil else { return }

        let lowercasedText = text.lowercased()

        for trigger in voiceCommandTriggers {
            // Check if text ends with the trigger phrase (with optional trailing punctuation)
            let pattern = trigger.phrase.lowercased()

            // Match: ends with phrase, possibly followed by punctuation
            if lowercasedText.hasSuffix(pattern) ||
               lowercasedText.hasSuffix(pattern + ".") ||
               lowercasedText.hasSuffix(pattern + "!") ||
               lowercasedText.hasSuffix(pattern + ",") {
                StreamingLogger.shared.log("Voice command detected: \"\(trigger.phrase)\" -> \(trigger.action)")
                detectedVoiceCommand = trigger

                // Trigger stop recording
                Task { @MainActor in
                    await self.executeVoiceCommand()
                }
                return
            }
        }
    }

    /// Execute the detected voice command
    @MainActor
    private func executeVoiceCommand() async {
        guard recordingState == .recording else { return }
        guard let command = detectedVoiceCommand else { return }

        // Handle "focus app" - switch to an app, keep recording
        if command.action == .focusApp, let appName = command.targetApp {
            StreamingLogger.shared.log("Executing voice command: focus app '\(appName)'")

            // Strip the command phrase from transcription (don't include "go to chrome" in text)
            if !interimTranscription.isEmpty {
                interimTranscription = stripVoiceCommand(command.phrase, from: interimTranscription)
            }

            // Run AppleScript to focus the app
            let script = "tell application \"\(appName)\" to activate"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            do {
                try process.run()
                process.waitUntilExit()
                StreamingLogger.shared.log("Focused app: \(appName)")
            } catch {
                StreamingLogger.shared.log("Failed to focus app: \(error)")
            }

            // Reset voice command detection so we can detect again
            detectedVoiceCommand = nil
            return
        }

        // Handle "send and continue" - paste but keep recording
        if command.action == .sendAndContinue {
            StreamingLogger.shared.log("Executing voice command: send and continue")

            // Build the full text from committed chunks + interim
            var fullText = committedChunks.joined(separator: " ")
            if !interimTranscription.isEmpty {
                if !fullText.isEmpty {
                    fullText += " "
                }
                fullText += interimTranscription
            }

            // Strip the voice command phrase
            fullText = stripVoiceCommand(command.phrase, from: fullText)
            fullText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)

            if !fullText.isEmpty {
                StreamingLogger.shared.log("Pasting and continuing: \"\(fullText)\"")

                // Paste the text
                CursorPaster.pasteAtCursor(fullText)

                // Press Enter after a small delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    CursorPaster.pressEnter()
                }
            }

            // Clear the buffers but keep recording
            committedChunks = []
            interimTranscription = ""
            currentChunkStartSample = streamingRecorder.sampleCount
            chunkStartTime = Date()

            // Reset voice command detection so we can detect again
            detectedVoiceCommand = nil

            StreamingLogger.shared.log("Buffers cleared, continuing to record")
            return
        }

        // For other actions (stop), trigger the normal flow
        StreamingLogger.shared.log("Executing voice command - stopping recording")
        await toggleRecord()
    }

    /// Strip the voice command phrase from the end of the transcription
    private func stripVoiceCommand(_ phrase: String, from text: String) -> String {
        let lowercasedText = text.lowercased()
        let lowercasedPhrase = phrase.lowercased()

        // Find the phrase at the end (with optional trailing punctuation)
        for suffix in [lowercasedPhrase, lowercasedPhrase + ".", lowercasedPhrase + "!", lowercasedPhrase + ","] {
            if lowercasedText.hasSuffix(suffix) {
                // Remove from original text (preserving case)
                let startIndex = text.index(text.endIndex, offsetBy: -suffix.count)
                var result = String(text[..<startIndex])
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
                return result
            }
        }

        // Phrase not found at end, return original
        return text
    }
}

