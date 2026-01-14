import Foundation

/// BERT WordPiece tokenizer for CoreML inference.
/// Implements the same tokenization as HuggingFace's BertTokenizer.
class BertTokenizer {
    private var vocab: [String: Int] = [:]
    private var idToToken: [Int: String] = [:]

    // Special tokens
    private let clsToken = "[CLS]"
    private let sepToken = "[SEP]"
    private let padToken = "[PAD]"
    private let unkToken = "[UNK]"
    private let maskToken = "[MASK]"

    private var clsId: Int = 101
    private var sepId: Int = 102
    private var padId: Int = 0
    private var unkId: Int = 100

    let maxSeqLen: Int

    init(vocabPath: String, maxSeqLen: Int = 128) {
        self.maxSeqLen = maxSeqLen
        loadVocab(from: vocabPath)
    }

    private func loadVocab(from path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[BertTokenizer] Failed to load vocab from \(path)")
            return
        }

        let lines = content.components(separatedBy: .newlines)
        for (index, token) in lines.enumerated() {
            if !token.isEmpty {
                vocab[token] = index
                idToToken[index] = token
            }
        }

        // Update special token IDs
        clsId = vocab[clsToken] ?? 101
        sepId = vocab[sepToken] ?? 102
        padId = vocab[padToken] ?? 0
        unkId = vocab[unkToken] ?? 100

        print("[BertTokenizer] Loaded \(vocab.count) tokens")
    }

    /// Tokenize text and return input_ids, attention_mask, and word_ids for mapping back.
    /// - Parameter text: Input text to tokenize
    /// - Returns: Tuple of (input_ids, attention_mask, wordIds) where wordIds maps each token position to original word index
    func encode(text: String) -> (inputIds: [Int32], attentionMask: [Int32], wordIds: [Int?]) {
        // Split into words (simple whitespace split, matching Python's behavior)
        let words = text.lowercased().split(separator: " ").map(String.init)

        var tokens: [String] = [clsToken]
        var wordIds: [Int?] = [nil] // [CLS] doesn't map to any word

        for (wordIdx, word) in words.enumerated() {
            let wordTokens = tokenizeWord(word)
            for token in wordTokens {
                tokens.append(token)
                wordIds.append(wordIdx)
            }
        }

        tokens.append(sepToken)
        wordIds.append(nil) // [SEP] doesn't map to any word

        // Truncate if needed
        if tokens.count > maxSeqLen {
            tokens = Array(tokens.prefix(maxSeqLen - 1)) + [sepToken]
            wordIds = Array(wordIds.prefix(maxSeqLen - 1)) + [nil]
        }

        // Convert to IDs
        var inputIds = tokens.map { vocab[$0] ?? unkId }

        // Create attention mask (1 for real tokens, 0 for padding)
        var attentionMask = [Int](repeating: 1, count: inputIds.count)

        // Pad to maxSeqLen
        let paddingLength = maxSeqLen - inputIds.count
        if paddingLength > 0 {
            inputIds += [Int](repeating: padId, count: paddingLength)
            attentionMask += [Int](repeating: 0, count: paddingLength)
            wordIds += [Int?](repeating: nil, count: paddingLength)
        }

        return (
            inputIds.map { Int32($0) },
            attentionMask.map { Int32($0) },
            wordIds
        )
    }

    /// WordPiece tokenization for a single word.
    private func tokenizeWord(_ word: String) -> [String] {
        if word.isEmpty { return [] }

        var tokens: [String] = []
        var start = word.startIndex

        while start < word.endIndex {
            var end = word.endIndex
            var foundToken: String? = nil

            // Find the longest matching subword
            while start < end {
                var substr = String(word[start..<end])

                // Add ## prefix for non-first subwords
                if start != word.startIndex {
                    substr = "##" + substr
                }

                if vocab[substr] != nil {
                    foundToken = substr
                    break
                }

                // Try shorter substring
                end = word.index(before: end)
            }

            if let token = foundToken {
                tokens.append(token)
                start = end
            } else {
                // Character not in vocab, use [UNK] and move to next character
                if start == word.startIndex {
                    tokens.append(unkToken)
                }
                start = word.index(after: start)
            }
        }

        return tokens.isEmpty ? [unkToken] : tokens
    }
}
