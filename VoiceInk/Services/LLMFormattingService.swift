import Foundation
import os

// MARK: - GPT-5 Model Configuration

enum GPT5Model: String, CaseIterable, Identifiable {
    case gpt5 = "gpt-5"
    case gpt5Mini = "gpt-5-mini"
    case gpt5Nano = "gpt-5-nano"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt5: return "GPT-5"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt5Nano: return "GPT-5 Nano"
        }
    }

    var description: String {
        switch self {
        case .gpt5: return "Best quality for complex formatting"
        case .gpt5Mini: return "Fast & efficient for most tasks"
        case .gpt5Nano: return "Fastest & cheapest for simple tasks"
        }
    }

    // Pricing per 1M tokens (December 2025)
    var inputPricePerMillion: Double {
        switch self {
        case .gpt5: return 1.25
        case .gpt5Mini: return 0.25
        case .gpt5Nano: return 0.05
        }
    }

    var outputPricePerMillion: Double {
        switch self {
        case .gpt5: return 10.00
        case .gpt5Mini: return 2.00
        case .gpt5Nano: return 0.40
        }
    }

    // Formatted pricing for display (input / output per 1M tokens)
    var formattedPricing: String {
        switch self {
        case .gpt5:
            return "$1.25 / $10.00 per 1M tokens"
        case .gpt5Mini:
            return "$0.25 / $2.00 per 1M tokens"
        case .gpt5Nano:
            return "$0.05 / $0.40 per 1M tokens"
        }
    }

    // Approximate cost indicator
    var costIndicator: String {
        switch self {
        case .gpt5: return "$$$"
        case .gpt5Mini: return "$$"
        case .gpt5Nano: return "$"
        }
    }
}

// MARK: - Cost Tracking

struct FormattingCostEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double

    init(model: String, inputTokens: Int, outputTokens: Int, cost: Double) {
        self.id = UUID()
        self.timestamp = Date()
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cost = cost
    }
}

class FormattingCostTracker: ObservableObject {
    static let shared = FormattingCostTracker()

    private let storageKey = "FormattingCostEntries"
    @Published private(set) var entries: [FormattingCostEntry] = []

    private init() {
        loadEntries()
    }

    // MARK: - Add Entry

    func addEntry(model: GPT5Model, inputTokens: Int, outputTokens: Int) {
        let inputCost = Double(inputTokens) / 1_000_000 * model.inputPricePerMillion
        let outputCost = Double(outputTokens) / 1_000_000 * model.outputPricePerMillion
        let totalCost = inputCost + outputCost

        let entry = FormattingCostEntry(
            model: model.rawValue,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cost: totalCost
        )

        entries.append(entry)
        saveEntries()
    }

    // MARK: - Cost Calculations

    func costForPeriod(since date: Date) -> Double {
        entries
            .filter { $0.timestamp >= date }
            .reduce(0) { $0 + $1.cost }
    }

    var costLastHour: Double {
        costForPeriod(since: Date().addingTimeInterval(-3600))
    }

    var costLastDay: Double {
        costForPeriod(since: Date().addingTimeInterval(-86400))
    }

    var costLastWeek: Double {
        costForPeriod(since: Date().addingTimeInterval(-604800))
    }

    var costLastMonth: Double {
        costForPeriod(since: Date().addingTimeInterval(-2592000))
    }

    var costAllTime: Double {
        entries.reduce(0) { $0 + $1.cost }
    }

    var requestCountLastHour: Int {
        entries.filter { $0.timestamp >= Date().addingTimeInterval(-3600) }.count
    }

    var requestCountAllTime: Int {
        entries.count
    }

    // MARK: - Persistence

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadEntries() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FormattingCostEntry].self, from: data) {
            entries = decoded
        }
    }

    func clearAllData() {
        entries = []
        saveEntries()
    }
}

// MARK: - LLM Formatting Service

/// Service for two-stage transcription with LLM formatting
/// Stage 1: User records content
/// Stage 2: User records formatting instructions (e.g., "make it professional", "translate to Japanese")
/// Result: LLM formats/transforms the content according to instructions
class LLMFormattingService: ObservableObject {
    static let shared = LLMFormattingService()

    private let logger = Logger(subsystem: "com.voiceink.formatting", category: "LLMFormattingService")

    // MARK: - Published State
    @Published var isProcessing = false
    @Published var stage1Text: String = ""
    @Published var stage2Instructions: String = ""
    @Published var formattedResult: String = ""
    @Published var lastError: String?

    // MARK: - Configuration
    private let timeout: TimeInterval = 30

    /// Get the currently selected provider
    var selectedProvider: AIPolishProvider {
        if let saved = UserDefaults.standard.string(forKey: "AIPolishProvider"),
           let provider = AIPolishProvider(rawValue: saved) {
            return provider
        }
        return .groq // Default to Groq (fastest)
    }

    /// Get the base URL for the selected provider
    private var baseURL: String {
        selectedProvider.baseURL
    }

    /// Get the API key for the selected provider
    private var apiKey: String? {
        UserDefaults.standard.string(forKey: selectedProvider.apiKeyUserDefaultsKey)
    }

    /// Get the selected model for the current provider
    var currentModel: String {
        let modelKey = "\(selectedProvider.rawValue)PolishModel"
        return UserDefaults.standard.string(forKey: modelKey) ?? selectedProvider.defaultModel
    }

    // Legacy GPT5Model support for backward compatibility
    var selectedModel: GPT5Model {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: "FormatWithAIModel"),
               let model = GPT5Model(rawValue: rawValue) {
                return model
            }
            return .gpt5Mini
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "FormatWithAIModel")
        }
    }

    private init() {}

    // MARK: - System Prompt
    // Based on industry best practices for LLM text cleanup
    // Sources: SuperAnnotate, DocsBot, RightBlogger, Medium prompt engineering guides
    private let systemPrompt = """
    You are an expert transcript editor. Your job is to clean up voice-to-text transcriptions.

    BASELINE RULES (always apply unless user explicitly says otherwise):
    1. Fix all spelling errors and typos
    2. Fix grammar mistakes
    3. Add proper punctuation (periods, commas, question marks, etc.)
    4. Fix capitalization (sentence starts, proper nouns, "I", etc.)
    5. Remove filler words: um, uh, er, ah, like, you know, I mean, sort of, kind of
    6. Remove false starts and stutters: "I I I think" → "I think"
    7. Remove verbal corrections: "Tuesday, no wait, Wednesday" → "Wednesday"

    CRITICAL - DO NOT:
    - Add new content, ideas, or information that wasn't in the original
    - Expand or elaborate on what the user said
    - Add examples, explanations, or embellishments
    - Be creative or "helpful" by adding more than what was spoken
    - Change the length significantly (cleaned text should be similar length to original)

    PRESERVE (never change unless explicitly asked):
    - The user's voice, tone, and style
    - Word choices and phrasing (except for errors above)
    - The meaning and intent
    - Sentence structure (unless grammatically wrong)
    - The original scope and length of the content

    USER INSTRUCTIONS:
    The user may provide additional instructions. These ADD TO or OVERRIDE the baseline rules.
    - If they say "keep filler words" → don't remove them
    - If they say "make it professional" → adjust tone while keeping meaning
    - If they say "translate to X" → translate the entire content
    - If they say "expand on this" or "add more detail" → ONLY THEN add content
    - If they give no instructions or minimal instructions → apply baseline rules only

    OUTPUT:
    Return ONLY the cleaned text. No explanations, no commentary, no quotes around the output.
    Work with what was given. Don't add, don't embellish, just clean.
    """

    // MARK: - Public Methods

    /// Format the content using Stage 1 text and Stage 2 instructions
    /// Baseline cleanup rules always apply (see systemPrompt)
    /// User instructions add to or override the baseline rules
    func format(content: String, instructions: String) async throws -> String {
        guard !content.isEmpty else {
            throw FormattingError.emptyContent
        }

        // User instructions are passed directly - baseline rules in system prompt always apply
        // Empty instructions = baseline cleanup only (grammar, punctuation, spelling, fillers)
        let userInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if userInstructions.isEmpty {
            StreamingLogger.shared.log("🎨 AI Polish: Baseline cleanup only (no additional instructions)")
        } else {
            StreamingLogger.shared.log("🎨 AI Polish: Baseline + user instructions: \(userInstructions.prefix(50))...")
        }

        // Get API key for the selected provider
        guard let providerApiKey = self.apiKey, !providerApiKey.isEmpty else {
            throw FormattingError.missingAPIKey
        }

        await MainActor.run {
            self.isProcessing = true
            self.stage1Text = content
            self.stage2Instructions = userInstructions
            self.lastError = nil
        }

        defer {
            Task { @MainActor in
                self.isProcessing = false
            }
        }

        // Build user message - baseline rules in system prompt always apply
        let userMessage: String
        if userInstructions.isEmpty {
            userMessage = """
            MESSAGE TO CLEAN UP:
            \(content)
            """
        } else {
            userMessage = """
            MESSAGE TO CLEAN UP:
            \(content)

            ADDITIONAL INSTRUCTIONS:
            \(userInstructions)
            """
        }

        logger.notice("LLM Formatting - Provider: \(self.selectedProvider.rawValue, privacy: .public)")
        logger.notice("LLM Formatting - Model: \(self.currentModel, privacy: .public)")
        logger.notice("LLM Formatting - Content: \(content.prefix(100), privacy: .public)...")
        logger.notice("LLM Formatting - User instructions: \(userInstructions.isEmpty ? "(none)" : userInstructions, privacy: .public)")

        // Build request
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(providerApiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        // Build request body - all providers use OpenAI-compatible format
        var requestBody: [String: Any] = [
            "model": currentModel,
            "messages": messages,
            "stream": false
        ]

        // Add temperature for non-GPT-5 models (Groq, Cerebras work better with lower temp)
        if selectedProvider != .openAI {
            requestBody["temperature"] = 0.3
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FormattingError.invalidResponse
            }

            if httpResponse.statusCode == 200 {
                guard let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = jsonResponse["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let formattedText = message["content"] as? String else {
                    throw FormattingError.parsingFailed
                }

                // Extract token usage for cost tracking
                if let usage = jsonResponse["usage"] as? [String: Any],
                   let inputTokens = usage["prompt_tokens"] as? Int,
                   let outputTokens = usage["completion_tokens"] as? Int {
                    FormattingCostTracker.shared.addEntry(
                        model: selectedModel,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens
                    )
                    logger.notice("LLM Formatting - Tokens: \(inputTokens) in, \(outputTokens) out")
                }

                let result = formattedText.trimmingCharacters(in: .whitespacesAndNewlines)

                await MainActor.run {
                    self.formattedResult = result
                }

                logger.notice("LLM Formatting - Result: \(result.prefix(100), privacy: .public)...")
                return result

            } else if httpResponse.statusCode == 401 {
                logger.error("LLM Formatting - 401 Invalid API Key")
                throw FormattingError.invalidAPIKey
            } else if httpResponse.statusCode == 429 {
                logger.error("LLM Formatting - 429 Rate Limited")
                throw FormattingError.rateLimitExceeded
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("LLM Formatting - API Error \(httpResponse.statusCode): \(errorString, privacy: .public)")
                StreamingLogger.shared.log("❌ LLM API ERROR (\(httpResponse.statusCode)): \(errorString)")
                throw FormattingError.apiError(statusCode: httpResponse.statusCode, message: errorString)
            }

        } catch let error as FormattingError {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
            throw error
        } catch {
            let formattingError = FormattingError.networkError(error.localizedDescription)
            await MainActor.run {
                self.lastError = formattingError.localizedDescription
            }
            throw formattingError
        }
    }

    /// Clear the current formatting state
    func reset() {
        stage1Text = ""
        stage2Instructions = ""
        formattedResult = ""
        lastError = nil
        isProcessing = false
    }
}

// MARK: - Errors

enum FormattingError: LocalizedError {
    case emptyContent
    case emptyInstructions
    case missingAPIKey
    case invalidAPIKey
    case invalidResponse
    case parsingFailed
    case rateLimitExceeded
    case apiError(statusCode: Int, message: String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "No content to format"
        case .emptyInstructions:
            return "No formatting instructions provided"
        case .missingAPIKey:
            return "OpenAI API key not configured. Go to Settings > AI Polish to add your key."
        case .invalidAPIKey:
            return "Invalid OpenAI API key"
        case .invalidResponse:
            return "Invalid response from server"
        case .parsingFailed:
            return "Failed to parse response"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
