import Foundation

/// Service for cleaning up transcription text using local ML models.
/// Communicates with a Python Flask server running on localhost:8000.
class MLCleanupService {
    static let shared = MLCleanupService()

    private let serverURL = "http://localhost:8000"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0  // 5 second timeout
        config.timeoutIntervalForResource = 10.0
        self.session = URLSession(configuration: config)
    }

    /// Check if the ML server is running
    func isServerAvailable() async -> Bool {
        guard let url = URL(string: "\(serverURL)/health") else { return false }

        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    /// Get the list of enabled models from UserDefaults
    /// Defaults: filler=true, repetition=true, repair=false, list=false
    private func getEnabledModels() -> [String] {
        var models: [String] = []

        // Helper to get bool with default value (UserDefaults.bool returns false if key doesn't exist)
        func getBool(_ key: String, default defaultValue: Bool) -> Bool {
            if UserDefaults.standard.object(forKey: key) == nil {
                return defaultValue
            }
            return UserDefaults.standard.bool(forKey: key)
        }

        if getBool("MLCleanupFillerEnabled", default: true) {
            models.append("filler")
        }
        if getBool("MLCleanupRepetitionEnabled", default: true) {
            models.append("repetition")
        }
        if getBool("MLCleanupRepairEnabled", default: false) {
            models.append("repair")
        }
        if getBool("MLCleanupListEnabled", default: false) {
            models.append("list")
        }

        print("[MLCleanup] Enabled models: \(models)")
        return models
    }

    /// Clean up transcription text using ML models.
    /// - Parameters:
    ///   - text: The raw transcription text
    ///   - models: Which models to run. If nil, uses enabled models from settings.
    /// - Returns: Cleaned text, or original text if server unavailable
    func cleanup(text: String, models: [String]? = nil) async -> String {
        guard !text.isEmpty else { return text }

        let modelsToUse = models ?? getEnabledModels()
        guard !modelsToUse.isEmpty else {
            print("[MLCleanup] No models enabled, returning original text")
            return text
        }

        guard let url = URL(string: "\(serverURL)/process") else {
            print("[MLCleanup] Invalid URL")
            return text
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get list style preference (default: numbered)
        let listStyle = UserDefaults.standard.string(forKey: "MLCleanupListStyle") ?? "numbered"

        let body: [String: Any] = [
            "text": text,
            "models": modelsToUse,
            "list_style": listStyle
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[MLCleanup] Failed to serialize request: \(error)")
            return text
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[MLCleanup] Server returned non-200 status")
                return text
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cleanedText = json["text"] as? String {
                let appliedModels = json["models_applied"] as? [String] ?? []
                print("[MLCleanup] Applied models: \(appliedModels)")
                print("[MLCleanup] Original: \"\(text)\"")
                print("[MLCleanup] Cleaned:  \"\(cleanedText)\"")
                return cleanedText
            }

            print("[MLCleanup] Failed to parse response")
            return text

        } catch {
            print("[MLCleanup] Request failed: \(error.localizedDescription)")
            return text
        }
    }
}
