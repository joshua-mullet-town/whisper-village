import Foundation
import CoreML

/// Native CoreML-based transcript cleanup service.
/// Replaces MLCleanupService's HTTP calls with local inference.
@available(macOS 13.0, *)
class CoreMLCleanupService {
    static let shared = CoreMLCleanupService()

    private var fillerModel: MLModel?
    private var repetitionModel: MLModel?
    private var tokenizer: BertTokenizer?

    private let maxSeqLen = 128

    private init() {
        loadModels()
    }

    private func loadModels() {
        // Try to load from CleanupModelManager first (Application Support)
        Task { @MainActor in
            let manager = CleanupModelManager.shared
            await manager.checkAndLoadModels()

            if let vocabPath = manager.vocabPath {
                self.tokenizer = BertTokenizer(vocabPath: vocabPath, maxSeqLen: self.maxSeqLen)
            }

            self.fillerModel = manager.fillerModel
            self.repetitionModel = manager.repetitionModel

            if self.fillerModel != nil {
                print("[CoreMLCleanup] Loaded filler model from Application Support")
            }
            if self.repetitionModel != nil {
                print("[CoreMLCleanup] Loaded repetition model from Application Support")
            }

            // Fall back to bundle if not in Application Support
            if self.tokenizer == nil, let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
                self.tokenizer = BertTokenizer(vocabPath: vocabURL.path, maxSeqLen: self.maxSeqLen)
            }

            if self.fillerModel == nil {
                self.loadBundleModel(name: "filler_remover") { model in
                    self.fillerModel = model
                    if model != nil {
                        print("[CoreMLCleanup] Loaded filler model from bundle")
                    }
                }
            }

            if self.repetitionModel == nil {
                self.loadBundleModel(name: "repetition_remover") { model in
                    self.repetitionModel = model
                    if model != nil {
                        print("[CoreMLCleanup] Loaded repetition model from bundle")
                    }
                }
            }
        }
    }

    /// Load model from bundle as fallback
    private func loadBundleModel(name: String, completion: @escaping (MLModel?) -> Void) {
        // Try compiled model first
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            do {
                let model = try MLModel(contentsOf: url)
                completion(model)
                return
            } catch {
                print("[CoreMLCleanup] Failed to load \(name).mlmodelc: \(error)")
            }
        }

        // Try mlpackage
        if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            Task {
                do {
                    let compiled = try await MLModel.compileModel(at: url)
                    let model = try MLModel(contentsOf: compiled)
                    completion(model)
                } catch {
                    print("[CoreMLCleanup] Failed to compile \(name).mlpackage: \(error)")
                    completion(nil)
                }
            }
        } else {
            completion(nil)
        }
    }

    /// Reload models (call after download completes)
    func reloadModels() {
        loadModels()
    }

    /// Check if CoreML models are available
    var isAvailable: Bool {
        return tokenizer != nil && (fillerModel != nil || repetitionModel != nil)
    }

    /// Clean up transcription text using CoreML models.
    func cleanup(text: String, removeFiller: Bool = true, removeRepetition: Bool = true) -> String {
        guard !text.isEmpty, let tokenizer = tokenizer else { return text }

        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }

        // Track which words to keep
        var keepWord = [Bool](repeating: true, count: words.count)

        // Run filler removal
        if removeFiller, let model = fillerModel {
            let fillerMask = runFillerInference(model: model, text: text, tokenizer: tokenizer)
            for (i, shouldRemove) in fillerMask.enumerated() where i < keepWord.count {
                if shouldRemove { keepWord[i] = false }
            }
        }

        // Run repetition removal
        if removeRepetition, let model = repetitionModel {
            let repMask = runRepetitionInference(model: model, text: text, tokenizer: tokenizer)
            for (i, shouldRemove) in repMask.enumerated() where i < keepWord.count {
                if shouldRemove { keepWord[i] = false }
            }
        }

        // Build result
        var result: [String] = []
        for (i, word) in words.enumerated() {
            if keepWord[i] {
                result.append(word)
            }
        }

        let cleanedText = result.joined(separator: " ")
        if cleanedText != text {
            print("[CoreMLCleanup] '\(text)' → '\(cleanedText)'")
        }
        return cleanedText
    }

    /// Run model inference (generic for both filler and repetition models)
    private func runInference(model: MLModel, text: String, tokenizer: BertTokenizer, modelName: String) -> [Bool] {
        let words = text.split(separator: " ").map(String.init)
        var shouldRemove = [Bool](repeating: false, count: words.count)

        // Tokenize
        let (inputIds, attentionMask, wordIds) = tokenizer.encode(text: text)

        // Create MLMultiArray inputs
        guard let inputIdsArray = try? MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .int32),
              let attentionMaskArray = try? MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .int32) else {
            return shouldRemove
        }

        for i in 0..<maxSeqLen {
            inputIdsArray[i] = NSNumber(value: inputIds[i])
            attentionMaskArray[i] = NSNumber(value: attentionMask[i])
        }

        // Create feature provider with input arrays
        let inputFeatures = try? MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIdsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray)
        ])

        guard let input = inputFeatures,
              let output = try? model.prediction(from: input),
              let logits = output.featureValue(for: "logits")?.multiArrayValue else {
            print("[CoreMLCleanup] \(modelName) inference failed")
            return shouldRemove
        }

        // Process logits
        return processLogits(logits: logits, wordIds: wordIds, numWords: words.count)
    }

    /// Run filler model inference
    private func runFillerInference(model: MLModel, text: String, tokenizer: BertTokenizer) -> [Bool] {
        return runInference(model: model, text: text, tokenizer: tokenizer, modelName: "Filler")
    }

    /// Run repetition model inference
    private func runRepetitionInference(model: MLModel, text: String, tokenizer: BertTokenizer) -> [Bool] {
        return runInference(model: model, text: text, tokenizer: tokenizer, modelName: "Repetition")
    }

    /// Process logits to determine which words to remove
    private func processLogits(logits: MLMultiArray, wordIds: [Int?], numWords: Int) -> [Bool] {
        var shouldRemove = [Bool](repeating: false, count: numWords)

        // logits shape is [1, seq_len, num_labels]
        let seqLen = logits.shape[1].intValue
        let numLabels = logits.shape[2].intValue

        // Track which word indices we've seen
        var seenWordIdx = Set<Int>()

        for tokenIdx in 0..<seqLen {
            guard let wordIdx = wordIds[tokenIdx] else { continue }
            if seenWordIdx.contains(wordIdx) { continue }
            seenWordIdx.insert(wordIdx)

            // Get prediction for this token (argmax)
            var maxVal: Float = -Float.infinity
            var maxLabel = 0

            for labelIdx in 0..<numLabels {
                let idx = tokenIdx * numLabels + labelIdx
                let val = logits[idx].floatValue
                if val > maxVal {
                    maxVal = val
                    maxLabel = labelIdx
                }
            }

            // Label 0 = O (keep), anything else = remove
            if maxLabel != 0 && wordIdx < shouldRemove.count {
                shouldRemove[wordIdx] = true
            }
        }

        return shouldRemove
    }
}
