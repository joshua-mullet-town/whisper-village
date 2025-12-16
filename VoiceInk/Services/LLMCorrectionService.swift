import Foundation

/// Service for cleaning up voice transcriptions using local LLM (Ollama)
/// Removes filler words, handles self-corrections, fixes stuttering
class LLMCorrectionService {
    static let shared = LLMCorrectionService()

    private let baseURL: String
    private let model: String
    private let session: URLSession

    /// Whether LLM correction is enabled (toggle in settings)
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "LLMCorrectionEnabled")
    }

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.1:8b-instruct-q4_0") {
        self.baseURL = baseURL
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10 // Fast timeout - if LLM is slow, skip it
        self.session = URLSession(configuration: config)
    }

    /// Clean up a transcription using the LLM
    /// Returns the cleaned text, or original text if correction fails/disabled
    func correct(_ text: String) async -> String {
        guard isEnabled else {
            return text
        }

        // Skip very short transcriptions (not worth the latency)
        let wordCount = text.split(separator: " ").count
        guard wordCount >= 3 else {
            return text
        }

        do {
            let cleaned = try await callOllama(text: text)
            // Sanity check - if LLM returned empty or much longer text, use original
            if cleaned.isEmpty || cleaned.count > text.count * 2 {
                print("[LLMCorrection] Sanity check failed, using original")
                return text
            }
            return cleaned
        } catch {
            print("[LLMCorrection] Error: \(error.localizedDescription)")
            return text // Fail gracefully - return original
        }
    }

    private func callOllama(text: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw LLMCorrectionError.invalidURL
        }

        let prompt = buildPrompt(text: text)

        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.1,  // Low temperature for consistent corrections
                "num_predict": 500   // Enough for most transcriptions
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMCorrectionError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw LLMCorrectionError.invalidResponse
        }

        let rawResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[LLMCorrection] Completed in \(Int(elapsed * 1000))ms")
        print("[LLMCorrection] Raw response: \(rawResponse)")

        // Parse JSON response to extract cleaned text
        let cleaned = extractCleanedText(from: rawResponse, originalText: text)
        print("[LLMCorrection] Original: \(text)")
        print("[LLMCorrection] Cleaned: \(cleaned)")

        return cleaned
    }

    /// Extract cleaned text from JSON response, fallback to original if parsing fails
    private func extractCleanedText(from response: String, originalText: String) -> String {
        // Try to parse as JSON first
        if let jsonData = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let cleaned = json["cleaned"] as? String {
            return cleaned
        }

        // Fallback: try to find JSON substring (model might add extra text around it)
        if let start = response.range(of: "{"),
           let end = response.range(of: "}", options: .backwards) {
            let jsonSubstring = String(response[start.lowerBound...end.upperBound])
            if let jsonData = jsonSubstring.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let cleaned = json["cleaned"] as? String {
                return cleaned
            }
        }

        // If all else fails, return original
        print("[LLMCorrection] Failed to parse JSON response, using original")
        return originalText
    }

    private func buildPrompt(text: String) -> String {
        """
        You are a transcript cleaner. Your ONLY job is to remove filler words.

        ABSOLUTE RULES - VIOLATING THESE IS FAILURE:
        1. NEVER fix spelling
        2. NEVER fix grammar
        3. NEVER add punctuation
        4. NEVER change any word that is not: um, uh, like, you know
        5. NEVER interpret self-corrections - leave them as-is

        You may ONLY delete these exact filler words: um, uh, like, you know
        You may ONLY fix repeated words: "I I" becomes "I"

        EVERYTHING ELSE MUST BE PRESERVED EXACTLY - including typos, bad grammar, wrong words.

        Output ONLY valid JSON:
        {"cleaned": "text here"}

        Input: \(text)
        """
    }

    /// Check if Ollama is available and model is loaded
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelPrefix = model.split(separator: ":").first.map(String.init) ?? model
                return models.contains { ($0["name"] as? String)?.hasPrefix(modelPrefix) ?? false }
            }
            return false
        } catch {
            return false
        }
    }

    enum LLMCorrectionError: Error, LocalizedError {
        case invalidURL
        case requestFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Ollama URL"
            case .requestFailed: return "Ollama request failed"
            case .invalidResponse: return "Invalid response from Ollama"
            }
        }
    }
}
