import Foundation
import CoreML

/// Native CoreML-based transcript cleanup service.
/// Replaces MLCleanupService's HTTP calls with local inference.
@available(macOS 13.0, *)
class CoreMLCleanupService {
    static let shared = CoreMLCleanupService()

    private var fillerModel: filler_remover?
    private var repetitionModel: repetition_remover?
    private var tokenizer: BertTokenizer?

    private let maxSeqLen = 128

    private init() {
        loadModels()
    }

    private func loadModels() {
        // Load vocab for tokenizer
        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            print("[CoreMLCleanup] vocab.txt not found in bundle")
            return
        }

        tokenizer = BertTokenizer(vocabPath: vocabURL.path, maxSeqLen: maxSeqLen)

        // Load models using Xcode-generated classes
        do {
            fillerModel = try filler_remover(configuration: MLModelConfiguration())
            print("[CoreMLCleanup] Loaded filler model")
        } catch {
            print("[CoreMLCleanup] Failed to load filler model: \(error)")
        }

        do {
            repetitionModel = try repetition_remover(configuration: MLModelConfiguration())
            print("[CoreMLCleanup] Loaded repetition model")
        } catch {
            print("[CoreMLCleanup] Failed to load repetition model: \(error)")
        }
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

    /// Run filler model inference
    private func runFillerInference(model: filler_remover, text: String, tokenizer: BertTokenizer) -> [Bool] {
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

        // Run inference
        let input = filler_removerInput(input_ids: inputIdsArray, attention_mask: attentionMaskArray)

        guard let output = try? model.prediction(input: input) else {
            print("[CoreMLCleanup] Filler inference failed")
            return shouldRemove
        }

        // Process logits
        return processLogits(logits: output.logits, wordIds: wordIds, numWords: words.count)
    }

    /// Run repetition model inference
    private func runRepetitionInference(model: repetition_remover, text: String, tokenizer: BertTokenizer) -> [Bool] {
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

        // Run inference
        let input = repetition_removerInput(input_ids: inputIdsArray, attention_mask: attentionMaskArray)

        guard let output = try? model.prediction(input: input) else {
            print("[CoreMLCleanup] Repetition inference failed")
            return shouldRemove
        }

        // Process logits
        return processLogits(logits: output.logits, wordIds: wordIds, numWords: words.count)
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
