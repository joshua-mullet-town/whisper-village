import Foundation
import os.log

/// Preprocesses audio to extract speech segments and remove silence before transcription.
/// This helps reduce Whisper hallucinations caused by silent sections in audio.
class AudioPreprocessor {
    static let shared = AudioPreprocessor()

    private let logger = Logger(subsystem: "com.voiceink.app", category: "AudioPreprocessor")
    private var vad: VoiceActivityDetector?
    private var isInitialized = false

    /// Whether audio preprocessing is enabled (respects user setting)
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "IsVADEnabled") as? Bool ?? true
    }

    private init() {}

    /// Initialize VAD model asynchronously. Call this early in app lifecycle.
    func initialize() async {
        guard !isInitialized else { return }

        if let modelPath = await VADModelManager.shared.getModelPath() {
            self.vad = VoiceActivityDetector(modelPath: modelPath)
            if self.vad != nil {
                logger.notice("AudioPreprocessor: VAD initialized successfully")
            } else {
                logger.warning("AudioPreprocessor: VAD initialization failed")
            }
        } else {
            logger.warning("AudioPreprocessor: VAD model path not found")
        }
        isInitialized = true
    }

    /// Extract only speech segments from audio, removing silence.
    /// Returns the original samples if VAD is not available or disabled.
    /// - Parameters:
    ///   - samples: Audio samples at 16kHz, mono, Float32
    ///   - sampleRate: Sample rate (default 16000)
    /// - Returns: Audio samples containing only speech segments concatenated together
    func extractSpeech(from samples: [Float], sampleRate: Int = 16000) -> [Float] {
        guard isEnabled else {
            logger.debug("AudioPreprocessor: VAD disabled, returning original audio")
            return samples
        }

        guard let vad = vad else {
            logger.debug("AudioPreprocessor: VAD not initialized, returning original audio")
            return samples
        }

        guard !samples.isEmpty else {
            return samples
        }

        // Run VAD to detect speech segments
        let speechSegments = vad.process(audioSamples: samples)

        guard !speechSegments.isEmpty else {
            logger.notice("AudioPreprocessor: No speech detected, returning original audio")
            return samples
        }

        logger.notice("AudioPreprocessor: VAD detected \(speechSegments.count) speech segments")

        // Extract audio from each speech segment
        var speechAudio: [Float] = []
        for segment in speechSegments {
            let startSample = Int(segment.start * Double(sampleRate))
            var endSample = Int(segment.end * Double(sampleRate))

            // Cap endSample to the audio buffer size
            if endSample > samples.count {
                endSample = samples.count
            }

            if startSample < endSample && startSample >= 0 {
                speechAudio.append(contentsOf: samples[startSample..<endSample])
            }
        }

        let reduction = samples.count > 0 ? Int((1.0 - Double(speechAudio.count) / Double(samples.count)) * 100) : 0
        logger.notice("AudioPreprocessor: Extracted \(speechAudio.count) samples (\(reduction)% silence removed)")

        // Return extracted speech, or original if extraction resulted in too little audio
        if speechAudio.count < 8000 { // Less than 0.5 seconds
            logger.notice("AudioPreprocessor: Extracted audio too short, returning original")
            return samples
        }

        return speechAudio
    }

    /// Simple amplitude-based silence trimming (leading/trailing only).
    /// Fallback when VAD is not available.
    /// - Parameters:
    ///   - samples: Audio samples at 16kHz, mono, Float32
    ///   - thresholdDb: Amplitude threshold in dB (default -40dB)
    /// - Returns: Audio samples with leading/trailing silence trimmed
    func trimSilence(from samples: [Float], thresholdDb: Float = -40) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let windowSize = 1600 // 100ms at 16kHz
        let threshold = pow(10, thresholdDb / 20) // Convert dB to linear

        // Find first non-silent window
        var startIndex = 0
        for i in stride(from: 0, to: samples.count - windowSize, by: windowSize) {
            let windowEnd = min(i + windowSize, samples.count)
            let window = Array(samples[i..<windowEnd])
            let rms = sqrt(window.map { $0 * $0 }.reduce(0, +) / Float(window.count))
            if rms > threshold {
                startIndex = i
                break
            }
        }

        // Find last non-silent window
        var endIndex = samples.count
        for i in stride(from: samples.count - windowSize, through: 0, by: -windowSize) {
            let windowStart = max(i, 0)
            let windowEnd = min(windowStart + windowSize, samples.count)
            let window = Array(samples[windowStart..<windowEnd])
            let rms = sqrt(window.map { $0 * $0 }.reduce(0, +) / Float(window.count))
            if rms > threshold {
                endIndex = windowEnd
                break
            }
        }

        guard startIndex < endIndex else {
            logger.notice("AudioPreprocessor: All audio below threshold, returning original")
            return samples
        }

        let trimmed = Array(samples[startIndex..<endIndex])
        let trimmedMs = (samples.count - trimmed.count) * 1000 / 16000
        logger.debug("AudioPreprocessor: Trimmed \(trimmedMs)ms of silence")

        return trimmed
    }
}
