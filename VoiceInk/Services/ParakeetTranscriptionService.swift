import Foundation
import AVFoundation
import FluidAudio
import os.log



class ParakeetTranscriptionService: TranscriptionService {
    private var asrManager: AsrManager?
    private let customModelsDirectory: URL?
    @Published var isModelLoaded = false
    
    // Logger for Parakeet transcription service
    private let logger = Logger(subsystem: "com.voiceink.app", category: "ParakeetTranscriptionService")
    
    init(customModelsDirectory: URL? = nil) {
        self.customModelsDirectory = customModelsDirectory
        logger.notice("🦜 ParakeetTranscriptionService initialized with directory: \(customModelsDirectory?.path ?? "default")")
    }

    func loadModel() async throws {
        if isModelLoaded {
            return
        }

        logger.notice("🦜 Starting Parakeet model loading")
        
        do {
         
            asrManager = AsrManager(config: .default) 
            let models: AsrModels
            if let customDirectory = customModelsDirectory {
                logger.notice("🦜 Loading models from custom directory: \(customDirectory.path)")
                models = try await AsrModels.downloadAndLoad(to: customDirectory)
            } else {
                logger.notice("🦜 Loading models from default directory")
                models = try await AsrModels.downloadAndLoad()
            }
            
            try await asrManager?.initialize(models: models)
            isModelLoaded = true
            logger.notice("🦜 Parakeet model loaded successfully")
            
        } catch let error as ASRError {
            logger.notice("🦜 Parakeet-specific error loading model: \(error.localizedDescription)")
            isModelLoaded = false
            asrManager = nil
            throw error
        } catch let error as AsrModelsError {
            logger.notice("🦜 Parakeet model management error loading model: \(error.localizedDescription)")
            isModelLoaded = false
            asrManager = nil
            throw error
        } catch {
            logger.notice("🦜 Unexpected error loading Parakeet model: \(error.localizedDescription)")
            isModelLoaded = false
            asrManager = nil
            throw error
        }
    }

    /// Transcribe raw audio samples directly (for streaming preview)
    /// Does NOT cleanup after transcription to allow repeated calls
    func transcribeSamples(_ samples: [Float]) async throws -> String {
        // Wait a moment if cleanup might be in progress (race condition mitigation)
        if !isModelLoaded && asrManager != nil {
            logger.notice("🦜 Model marked as not loaded but manager exists - possible cleanup in progress, waiting...")
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        if asrManager == nil || !isModelLoaded {
            logger.notice("🦜 Loading model for streaming transcription...")
            try await loadModel()
        }

        guard let manager = asrManager, isModelLoaded else {
            logger.notice("🦜 Parakeet manager is still nil or not loaded after attempting to load the model.")
            throw ASRError.notInitialized
        }

        // Need at least 1 second of audio (16000 samples at 16kHz)
        guard samples.count >= 16000 else {
            logger.notice("🦜 Audio too short for streaming transcription: \(samples.count) samples")
            return ""
        }

        // Wrap transcription in do/catch to handle internal FluidAudio crashes gracefully
        do {
            let result = try await manager.transcribe(samples)

            var text = result.text

            if UserDefaults.standard.object(forKey: "IsTextFormattingEnabled") as? Bool ?? true {
                text = WhisperTextFormatter.format(text)
            }

            text = WhisperHallucinationFilter.filter(text)

            return text
        } catch {
            logger.error("🦜 Streaming transcription failed: \(error.localizedDescription)")
            // Mark model as not loaded so next attempt will reload
            isModelLoaded = false
            throw error
        }
    }

    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        if asrManager == nil || !isModelLoaded {
            try await loadModel()
        }

        guard let asrManager = asrManager else {
            logger.notice("🦜 Parakeet manager is still nil after attempting to load the model.")
            throw ASRError.notInitialized
        }

        let audioSamples = try readAudioSamples(from: audioURL)
        
        // Validate audio data before VAD
        guard !audioSamples.isEmpty else {
            logger.notice("🦜 Audio is empty, skipping transcription.")
            throw ASRError.invalidAudioData
        }

        // Use VAD to get speech segments
        var speechAudio: [Float] = []
        let isVADEnabled = UserDefaults.standard.object(forKey: "IsVADEnabled") as? Bool ?? true

        if isVADEnabled {
            if let modelPath = await VADModelManager.shared.getModelPath() {
                if let vad = VoiceActivityDetector(modelPath: modelPath) {
                    let speechSegments = vad.process(audioSamples: audioSamples)
                    logger.notice("🦜 VAD detected \(speechSegments.count) speech segments.")

                    let sampleRate = 16000 // Assuming 16kHz sample rate
                    for segment in speechSegments {
                        let startSample = Int(segment.start * Double(sampleRate))
                        var endSample = Int(segment.end * Double(sampleRate))

                        // Cap endSample to the audio buffer size
                        if endSample > audioSamples.count {
                            endSample = audioSamples.count
                        }

                        if startSample < endSample {
                            speechAudio.append(contentsOf: audioSamples[startSample..<endSample])
                        } else {
                            logger.warning("🦜 Invalid sample range for segment: start=\(startSample), end=\(endSample). Skipping.")
                        }
                    }
                    logger.notice("🦜 Extracted \(speechAudio.count) samples from VAD segments.")
                } else {
                    logger.warning("🦜 VAD could not be initialized. Transcribing original audio.")
                    speechAudio = audioSamples
                }
            } else {
                logger.warning("🦜 VAD model path not found. Transcribing original audio.")
                speechAudio = audioSamples
            }
        } else {
            logger.notice("🦜 VAD is disabled by user setting. Transcribing original audio.")
            speechAudio = audioSamples
        }
        
        // Validate audio data after VAD
        guard speechAudio.count >= 16000 else {
            logger.notice("🦜 Audio too short for transcription after VAD: \(speechAudio.count) samples")
            throw ASRError.invalidAudioData
        }
        
        let result = try await asrManager.transcribe(speechAudio)
        
        // Reset decoder state and cleanup after transcription to avoid blocking the transcription start
        Task {
            asrManager.cleanup()
            isModelLoaded = false
            logger.notice("🦜 Parakeet ASR models cleaned up from memory")
        }
        
        // Check for empty results (vocabulary issue indicator)
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.notice("🦜 Warning: Empty transcription result for \(audioSamples.count) samples - possible vocabulary issue")
        }
        
        var text = result.text
        
        if UserDefaults.standard.object(forKey: "IsTextFormattingEnabled") as? Bool ?? true {
            text = WhisperTextFormatter.format(text)
        }
        
        // Apply hallucination and filler word filtering
        text = WhisperHallucinationFilter.filter(text)
        
        return text
    }

    private func readAudioSamples(from url: URL) throws -> [Float] {
        do {
            let data = try Data(contentsOf: url)
            
            // Check minimum file size for valid WAV header
            guard data.count > 44 else {
                logger.notice("🦜 Audio file too small (\(data.count) bytes), expected > 44 bytes")
                throw ASRError.invalidAudioData
            }

            let floats = stride(from: 44, to: data.count, by: 2).map {
                return data[$0..<$0 + 2].withUnsafeBytes {
                    let short = Int16(littleEndian: $0.load(as: Int16.self))
                    return max(-1.0, min(Float(short) / 32767.0, 1.0))
                }
            }
            
            return floats
        } catch {
            logger.notice("🦜 Failed to read audio file: \(error.localizedDescription)")
            throw ASRError.invalidAudioData
        }
    }

}
