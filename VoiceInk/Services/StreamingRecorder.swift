import Foundation
import AVFoundation
import Accelerate

/// A recorder that captures audio samples in real-time using AVAudioEngine.
/// Unlike the standard Recorder (which uses AVAudioRecorder and writes to file),
/// this captures samples directly into a buffer for streaming transcription.
@MainActor
class StreamingRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    /// Buffer to accumulate audio samples (16kHz, mono, Float32)
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// Published state for UI
    @Published var isRecording = false
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    @Published var sampleCount: Int = 0

    /// Target format for Whisper (16kHz, mono, Float32)
    private let targetSampleRate: Double = 16000.0

    private let logger = StreamingLogger.shared

    init() {
        logger.log("StreamingRecorder initialized")
    }

    /// Start capturing audio samples
    func startRecording() throws {
        logger.log("startRecording() called")

        guard !isRecording else {
            logger.log("Already recording, ignoring")
            return
        }

        // Clear buffer
        bufferLock.lock()
        sampleBuffer.removeAll()
        bufferLock.unlock()

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            logger.log("ERROR: Failed to create AVAudioEngine")
            throw RecorderError.engineCreationFailed
        }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            logger.log("ERROR: Failed to get input node")
            throw RecorderError.inputNodeFailed
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.log("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Create format for our target (16kHz, mono, Float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            logger.log("ERROR: Failed to create target format")
            throw RecorderError.formatCreationFailed
        }

        logger.log("Target format: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount) channels")

        // Install tap on input node
        // We'll convert to our target format
        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, inputFormat: inputFormat)
        }

        logger.log("Tap installed, starting engine...")

        do {
            try audioEngine.start()
            isRecording = true
            logger.log("Engine started successfully")
        } catch {
            logger.log("ERROR: Failed to start engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            throw RecorderError.engineStartFailed(error)
        }
    }

    /// Stop recording and return all captured samples
    func stopRecording() -> [Float] {
        logger.log("stopRecording() called")

        guard isRecording else {
            logger.log("Not recording, returning empty buffer")
            return []
        }

        // Stop engine and remove tap
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)

        isRecording = false
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)

        // Return samples
        bufferLock.lock()
        let samples = sampleBuffer
        sampleBuffer.removeAll()
        bufferLock.unlock()

        logger.log("Stopped. Returning \(samples.count) samples (\(String(format: "%.2f", Double(samples.count) / targetSampleRate)) seconds)")

        return samples
    }

    /// Get current samples without stopping (for interim transcription)
    func getCurrentSamples() -> [Float] {
        bufferLock.lock()
        let samples = sampleBuffer
        bufferLock.unlock()
        return samples
    }

    /// Get samples from the last N milliseconds (for sliding window)
    func getRecentSamples(lastMs: Int) -> [Float] {
        let sampleCount = Int(Double(lastMs) / 1000.0 * targetSampleRate)

        bufferLock.lock()
        let samples: [Float]
        if sampleBuffer.count <= sampleCount {
            samples = sampleBuffer
        } else {
            samples = Array(sampleBuffer.suffix(sampleCount))
        }
        bufferLock.unlock()

        return samples
    }

    /// Get samples from a specific start index to now (for chunk-based transcription)
    func getSamplesFromIndex(_ startIndex: Int) -> [Float] {
        bufferLock.lock()
        let samples: [Float]
        if startIndex >= sampleBuffer.count {
            samples = []
        } else {
            samples = Array(sampleBuffer[startIndex...])
        }
        bufferLock.unlock()
        return samples
    }

    /// Get current sample count (for tracking chunk boundaries)
    func getCurrentSampleCount() -> Int {
        bufferLock.lock()
        let count = sampleBuffer.count
        bufferLock.unlock()
        return count
    }

    /// Clear the buffer without stopping recording (for cancel/reset)
    func clearBuffer() {
        logger.log("clearBuffer() called - clearing \(sampleBuffer.count) samples")
        bufferLock.lock()
        sampleBuffer.removeAll()
        bufferLock.unlock()
        sampleCount = 0
    }

    /// Process incoming audio buffer - convert to 16kHz mono and store
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(inputFormat.channelCount)
        let inputSampleRate = inputFormat.sampleRate

        // Convert to mono if stereo
        var monoSamples = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            memcpy(&monoSamples, channelData[0], frameCount * MemoryLayout<Float>.size)
        } else {
            // Average channels for mono
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }

        // Resample to 16kHz if needed
        let resampledSamples: [Float]
        if abs(inputSampleRate - targetSampleRate) > 1.0 {
            resampledSamples = resample(monoSamples, from: inputSampleRate, to: targetSampleRate)
        } else {
            resampledSamples = monoSamples
        }

        // Calculate audio level for meter
        var rms: Float = 0
        vDSP_rmsqv(resampledSamples, 1, &rms, vDSP_Length(resampledSamples.count))
        let db = 20 * log10(max(rms, 0.0001))
        let normalized = max(0, min(1, (db + 60) / 60))

        // Append to buffer
        bufferLock.lock()
        sampleBuffer.append(contentsOf: resampledSamples)
        let currentCount = sampleBuffer.count
        bufferLock.unlock()

        // Update UI on main thread
        Task { @MainActor in
            self.sampleCount = currentCount
            self.audioMeter = AudioMeter(averagePower: Double(normalized), peakPower: Double(normalized))
        }

        // Log occasionally (every ~1 second worth of samples)
        if currentCount % Int(targetSampleRate) < resampledSamples.count {
            logger.log("Buffer: \(currentCount) samples (\(String(format: "%.1f", Double(currentCount) / targetSampleRate))s), level: \(String(format: "%.2f", normalized))")
        }
    }

    /// Simple linear interpolation resampling
    private func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        let ratio = inputRate / outputRate
        let outputCount = Int(Double(samples.count) / ratio)

        var output = [Float](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let inputIndex = Double(i) * ratio
            let index0 = Int(inputIndex)
            let index1 = min(index0 + 1, samples.count - 1)
            let fraction = Float(inputIndex - Double(index0))

            output[i] = samples[index0] * (1 - fraction) + samples[index1] * fraction
        }

        return output
    }

    enum RecorderError: Error {
        case engineCreationFailed
        case inputNodeFailed
        case formatCreationFailed
        case engineStartFailed(Error)
    }
}
