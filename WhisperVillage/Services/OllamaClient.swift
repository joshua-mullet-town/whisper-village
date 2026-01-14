import Foundation

/// Client for communicating with local Ollama LLM
class OllamaClient {
    static let shared = OllamaClient()

    private let baseURL: String
    private let model: String
    private let session: URLSession
    private let logger = StreamingLogger.shared

    /// Track if we've already attempted recovery this session to avoid loops
    private var hasAttemptedRecoveryThisSession = false

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.2:3b") {
        self.baseURL = baseURL
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Reset recovery flag (call when app becomes active or user manually triggers)
    func resetRecoveryState() {
        hasAttemptedRecoveryThisSession = false
    }

    // MARK: - Dependency Status

    /// Status of Command Mode dependencies
    struct DependencyStatus {
        let ollamaInstalled: Bool
        let ollamaRunning: Bool
        let modelAvailable: Bool
        let modelName: String

        var isReady: Bool {
            ollamaInstalled && ollamaRunning && modelAvailable
        }

        var userMessage: String? {
            if !ollamaInstalled {
                return "Ollama is not installed"
            }
            if !ollamaRunning {
                return "Ollama is not running"
            }
            if !modelAvailable {
                return "AI model '\(modelName)' is not downloaded"
            }
            return nil
        }

        /// The actual command they can paste into Terminal
        var terminalCommand: String? {
            if !ollamaInstalled {
                return "brew install ollama"
            }
            if !ollamaRunning {
                return "ollama serve"
            }
            if !modelAvailable {
                return "ollama pull \(modelName)"
            }
            return nil
        }
    }

    /// Start Ollama serve in background
    func startOllama() {
        logger.log("🚀 Starting Ollama...")

        // Try the standard path first
        var process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            logger.log("🚀 Ollama started (standard path)")
            return
        } catch {
            // Try Homebrew path
            process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                logger.log("🚀 Ollama started (homebrew path)")
            } catch {
                logger.log("🚀 Failed to start Ollama: \(error)")
            }
        }
    }

    /// Pull a model in background (for downloading missing models)
    func pullModel(_ modelName: String) {
        logger.log("📥 Pulling model: \(modelName)")

        var process = Process()
        let ollamaPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
            ? "/opt/homebrew/bin/ollama"
            : "/usr/local/bin/ollama"

        process.executableURL = URL(fileURLWithPath: ollamaPath)
        process.arguments = ["pull", modelName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            logger.log("📥 Started pulling model: \(modelName)")
        } catch {
            logger.log("📥 Failed to pull model: \(error)")
        }
    }

    /// Check what dependencies are available for Command Mode
    func checkDependencies() async -> DependencyStatus {
        logger.log("🔍 Checking Command Mode dependencies...")

        // Check if Ollama binary exists
        let ollamaInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/ollama") ||
                              FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")

        // Check if Ollama is responding
        var ollamaRunning = false
        var modelAvailable = false

        if ollamaInstalled {
            guard let url = URL(string: "\(baseURL)/api/tags") else {
                return DependencyStatus(ollamaInstalled: true, ollamaRunning: false, modelAvailable: false, modelName: model)
            }

            do {
                let (data, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    ollamaRunning = true

                    // Check if our model is available
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let models = json["models"] as? [[String: Any]] {
                        let modelPrefix = model.split(separator: ":").first.map(String.init) ?? model
                        modelAvailable = models.contains { modelInfo in
                            guard let name = modelInfo["name"] as? String else { return false }
                            return name.hasPrefix(modelPrefix)
                        }
                    }
                }
            } catch {
                logger.log("🔍 Ollama not responding: \(error.localizedDescription)")
            }
        }

        let status = DependencyStatus(
            ollamaInstalled: ollamaInstalled,
            ollamaRunning: ollamaRunning,
            modelAvailable: modelAvailable,
            modelName: model
        )

        logger.log("🔍 Dependencies: installed=\(ollamaInstalled), running=\(ollamaRunning), model=\(modelAvailable)")
        return status
    }

    /// Context about currently open applications
    struct AppContext {
        let openApps: [String]
        let itermTabs: [(window: Int, tab: Int, name: String)]
        let chromeTabs: [(window: Int, tab: Int, title: String)]

        var description: String {
            var lines: [String] = []
            lines.append("Open apps: \(openApps.joined(separator: ", "))")

            if !itermTabs.isEmpty {
                lines.append("\niTerm2 tabs:")
                for tab in itermTabs {
                    lines.append("  Window \(tab.window), Tab \(tab.tab): \(tab.name)")
                }
            }

            if !chromeTabs.isEmpty {
                lines.append("\nChrome tabs:")
                for tab in chromeTabs.prefix(10) { // Limit to first 10 to keep prompt short
                    lines.append("  Window \(tab.window), Tab \(tab.tab): \(tab.title)")
                }
                if chromeTabs.count > 10 {
                    lines.append("  ... and \(chromeTabs.count - 10) more")
                }
            }

            return lines.joined(separator: "\n")
        }
    }

    /// Parsed result from LLM
    enum JarvisAction: Equatable {
        case send           // Paste current text + Enter
        case stop           // Paste current text, stop recording
        case cancel         // Discard text, stop recording
        case listen         // Clear buffer, continue listening
        case focusApp(name: String)
        case focusTab(app: String, window: Int, tab: Int)
        case unknown
    }

    /// Interpret a command using the LLM
    func interpret(command: String, context: AppContext) async throws -> JarvisAction {
        let prompt = buildPrompt(command: command, context: context)

        let requestBody: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.1,
                "num_predict": 100
            ]
        ]

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw OllamaError.invalidResponse
        }

        return parseResponse(responseText)
    }

    /// Check if Ollama is running and model is available
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            // Check if our model is in the list
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.contains { ($0["name"] as? String)?.hasPrefix(model.split(separator: ":").first.map(String.init) ?? "") ?? false }
            }
            return false
        } catch {
            return false
        }
    }

    private func buildPrompt(command: String, context: AppContext) -> String {
        """
        You interpret voice commands for Mac app switching. ONLY recognize clear navigation commands.

        CONTEXT:
        \(context.description)

        VALID COMMANDS (ONLY these patterns):
        - "go to [app]" or "switch to [app]" -> {"action": "focus_app", "app_name": "..."}
        - "[first/second/third] terminal tab" -> {"action": "focus_tab", "app_name": "iTerm2", "window": 1, "tab": N}
        - "[first/second/third] chrome tab" -> {"action": "focus_tab", "app_name": "Google Chrome", "window": 1, "tab": N}

        EXAMPLES:
        Command: "go to chrome" -> {"action": "focus_app", "app_name": "Google Chrome"}
        Command: "switch to terminal" -> {"action": "focus_app", "app_name": "iTerm2"}
        Command: "second terminal tab" -> {"action": "focus_tab", "app_name": "iTerm2", "window": 1, "tab": 2}
        Command: "go to spotify" -> {"action": "focus_app", "app_name": "Spotify"}
        Command: "hello how are you" -> {"action": "unknown"}
        Command: "testing one two three" -> {"action": "unknown"}
        Command: "um let me think" -> {"action": "unknown"}

        RULES:
        - "terminal" means iTerm2
        - "browser" or "chrome" means Google Chrome
        - Use exact app names from the context
        - "second" = 2, "third" = 3, etc.
        - If the command is NOT clearly a navigation request, return {"action": "unknown"}
        - Random speech or unclear phrases should return {"action": "unknown"}

        Command: "\(command)"
        JSON:
        """
    }

    private func parseResponse(_ response: String) -> JarvisAction {
        // Find JSON in response
        guard let jsonStart = response.firstIndex(of: "{"),
              let jsonEnd = response.lastIndex(of: "}") else {
            return .unknown
        }

        let jsonString = String(response[jsonStart...jsonEnd])

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return .unknown
        }

        switch action {
        case "send":
            return .send
        case "stop":
            return .stop
        case "cancel":
            return .cancel
        case "listen":
            return .listen
        case "focus_app":
            if let appName = json["app_name"] as? String {
                return .focusApp(name: appName)
            }
            return .unknown
        case "focus_tab":
            if let appName = json["app_name"] as? String,
               let window = json["window"] as? Int,
               let tab = json["tab"] as? Int {
                return .focusTab(app: appName, window: window, tab: tab)
            }
            return .unknown
        default:
            return .unknown
        }
    }

    enum OllamaError: Error, LocalizedError {
        case invalidURL
        case requestFailed
        case invalidResponse
        case ollamaNotRunning
        case modelNotLoaded
        case metalGPUError          // Recoverable - needs Ollama restart
        case recoveryFailed         // Tried to restart but failed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Ollama URL"
            case .requestFailed: return "Ollama request failed"
            case .invalidResponse: return "Invalid response from Ollama"
            case .ollamaNotRunning: return "Ollama is not running"
            case .modelNotLoaded: return "AI model not loaded"
            case .metalGPUError: return "GPU error - restarting Ollama..."
            case .recoveryFailed: return "Could not recover Ollama. Try restarting your Mac."
            }
        }

        var isRecoverable: Bool {
            switch self {
            case .metalGPUError: return true
            default: return false
            }
        }
    }

    // MARK: - Auto-Recovery

    /// Attempt to restart Ollama when it's in a bad state
    private func attemptOllamaRestart() async -> Bool {
        logger.log("🔄 Ollama: Attempting automatic restart...")

        // Kill existing Ollama processes
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-f", "ollama"]
        try? killProcess.run()
        killProcess.waitUntilExit()

        // Wait a moment for cleanup
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Start Ollama serve in background
        let startProcess = Process()
        startProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        startProcess.arguments = ["serve"]
        startProcess.standardOutput = FileHandle.nullDevice
        startProcess.standardError = FileHandle.nullDevice

        do {
            try startProcess.run()
            logger.log("🔄 Ollama: Started serve process")
        } catch {
            // Try alternate path (Homebrew on Apple Silicon)
            let altProcess = Process()
            altProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
            altProcess.arguments = ["serve"]
            altProcess.standardOutput = FileHandle.nullDevice
            altProcess.standardError = FileHandle.nullDevice

            do {
                try altProcess.run()
                logger.log("🔄 Ollama: Started serve process (homebrew path)")
            } catch {
                logger.log("🔄 Ollama: Failed to start - \(error)")
                return false
            }
        }

        // Wait for Ollama to be ready (up to 10 seconds)
        for attempt in 1...10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            if await quickHealthCheck() {
                logger.log("🔄 Ollama: Restarted successfully after \(attempt)s")
                return true
            }
        }

        logger.log("🔄 Ollama: Restart timed out")
        return false
    }

    /// Quick check if Ollama is responding (doesn't test generation)
    private func quickHealthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }

        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Deep health check - actually tests generation to catch GPU errors
    func deepHealthCheck() async -> Result<Void, OllamaError> {
        logger.log("🏥 Ollama: Running deep health check...")

        // First check if Ollama is responding at all
        guard await quickHealthCheck() else {
            logger.log("🏥 Ollama: Not responding")
            return .failure(.ollamaNotRunning)
        }

        // Now try a minimal generation to test GPU/Metal
        let testBody: [String: Any] = [
            "model": model,
            "prompt": "Hi",
            "stream": false,
            "options": ["num_predict": 1]
        ]

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.requestFailed)
            }

            // Check for error in response body (Metal errors come back as JSON with "error" field)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {

                // Detect Metal/GPU errors
                if errorMessage.contains("Metal") ||
                   errorMessage.contains("metal") ||
                   errorMessage.contains("GPU") ||
                   errorMessage.contains("ggml_backend") ||
                   errorMessage.contains("XPC_ERROR") {
                    logger.log("🏥 Ollama: Detected GPU/Metal error: \(errorMessage.prefix(100))")
                    return .failure(.metalGPUError)
                }

                logger.log("🏥 Ollama: Error from API: \(errorMessage.prefix(100))")
                return .failure(.requestFailed)
            }

            if httpResponse.statusCode == 200 {
                logger.log("🏥 Ollama: Deep health check passed ✓")
                return .success(())
            } else {
                logger.log("🏥 Ollama: HTTP \(httpResponse.statusCode)")
                return .failure(.requestFailed)
            }
        } catch {
            logger.log("🏥 Ollama: Request error - \(error)")
            return .failure(.requestFailed)
        }
    }

    /// Ensure Ollama is healthy, attempting recovery if needed
    func ensureHealthy() async -> Result<Void, OllamaError> {
        let healthResult = await deepHealthCheck()

        switch healthResult {
        case .success:
            return .success(())

        case .failure(let error) where error.isRecoverable && !hasAttemptedRecoveryThisSession:
            hasAttemptedRecoveryThisSession = true
            logger.log("🔄 Ollama: Attempting auto-recovery for \(error.localizedDescription)")

            if await attemptOllamaRestart() {
                // Verify it's actually working now
                let retryResult = await deepHealthCheck()
                if case .success = retryResult {
                    logger.log("🔄 Ollama: Auto-recovery successful!")
                    return .success(())
                }
            }

            logger.log("🔄 Ollama: Auto-recovery failed")
            return .failure(.recoveryFailed)

        case .failure(let error):
            return .failure(error)
        }
    }
}
