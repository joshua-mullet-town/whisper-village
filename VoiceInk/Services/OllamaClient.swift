import Foundation

/// Client for communicating with local Ollama LLM
class OllamaClient {
    static let shared = OllamaClient()

    private let baseURL: String
    private let model: String
    private let session: URLSession

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.2:3b") {
        self.baseURL = baseURL
        self.model = model

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
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

    enum OllamaError: Error {
        case invalidURL
        case requestFailed
        case invalidResponse
    }
}
