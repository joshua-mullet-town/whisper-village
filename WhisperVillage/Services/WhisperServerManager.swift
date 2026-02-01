import Foundation
import OSLog

/// Manages a local whisper-cpp HTTP server for external transcription requests
/// This allows other apps (like Homestead) to use the same Whisper engine
@MainActor
final class WhisperServerManager: ObservableObject {
    static let shared = WhisperServerManager()

    private let logger = Logger(subsystem: "town.mullet.WhisperVillage", category: "WhisperServerManager")

    /// The running server process
    private var serverProcess: Process?

    /// Published state for UI binding
    @Published var isRunning = false
    @Published var port: Int = 8178
    @Published var lastError: String?

    /// UserDefaults key for auto-launch setting
    private let autoLaunchKey = "WhisperServerAutoLaunchEnabled"

    /// Whether to auto-launch server on app start
    var isAutoLaunchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoLaunchKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: autoLaunchKey)
            if newValue && !isRunning {
                start()
            } else if !newValue && isRunning {
                stop()
            }
        }
    }

    private init() {
        logger.notice("WhisperServerManager initialized")

        // Auto-start if enabled
        if isAutoLaunchEnabled {
            start()
        }
    }

    // MARK: - Server Control

    /// Start the whisper-cpp HTTP server
    func start() {
        guard !isRunning else {
            logger.notice("Server already running")
            return
        }

        // Find the model to use
        guard let modelPath = findBestModel() else {
            lastError = "No Whisper model found"
            logger.error("Cannot start server: no model found")
            return
        }

        // Find whisper-server binary
        guard let serverPath = findWhisperServer() else {
            lastError = "whisper-server not found. Install with: brew install whisper-cpp"
            logger.error("Cannot start server: whisper-server binary not found")
            return
        }

        logger.notice("Starting whisper-server with model: \(modelPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        process.arguments = [
            "--model", modelPath,
            "--port", String(port),
            "--host", "0.0.0.0"  // Listen on all interfaces for network access
        ]

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Handle process termination
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                self?.logger.notice("whisper-server exited with code: \(proc.terminationStatus)")
                self?.isRunning = false
                self?.serverProcess = nil

                if proc.terminationStatus != 0 {
                    // Read error output
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                        self?.lastError = errorString.prefix(200).description
                        self?.logger.error("Server error: \(errorString)")
                    }
                }
            }
        }

        do {
            try process.run()
            serverProcess = process
            isRunning = true
            lastError = nil
            logger.notice("whisper-server started on port \(self.port)")
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to start whisper-server: \(error.localizedDescription)")
        }
    }

    /// Stop the whisper-cpp HTTP server
    func stop() {
        guard let process = serverProcess, isRunning else {
            logger.notice("Server not running")
            return
        }

        logger.notice("Stopping whisper-server")
        process.terminate()
        serverProcess = nil
        isRunning = false
    }

    /// Restart the server (useful after model changes)
    func restart() {
        stop()
        // Small delay to ensure port is released
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start()
        }
    }

    // MARK: - Model Discovery

    /// Find the best available Whisper model
    private func findBestModel() -> String? {
        let fm = FileManager.default

        // Check Whisper Village's model directory
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let whisperVillageModels = appSupport?
            .appendingPathComponent("town.mullet.WhisperVillage/WhisperModels")

        // Model preference order (best quality first)
        let modelPreference = [
            "ggml-large-v3-turbo.bin",
            "ggml-large-v3-turbo-q5_0.bin",
            "ggml-large-v3.bin",
            "ggml-medium.bin",
            "ggml-small.bin",
            "ggml-base.bin",
            "ggml-tiny.bin"
        ]

        if let modelsDir = whisperVillageModels {
            for modelName in modelPreference {
                let modelPath = modelsDir.appendingPathComponent(modelName)
                if fm.fileExists(atPath: modelPath.path) {
                    return modelPath.path
                }
            }

            // Fallback: find any .bin file
            if let contents = try? fm.contentsOfDirectory(atPath: modelsDir.path) {
                for file in contents where file.hasSuffix(".bin") && file.hasPrefix("ggml-") {
                    return modelsDir.appendingPathComponent(file).path
                }
            }
        }

        return nil
    }

    /// Find the whisper-server binary
    private func findWhisperServer() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/whisper-server",  // Apple Silicon Homebrew
            "/usr/local/bin/whisper-server",     // Intel Homebrew
            "/usr/bin/whisper-server"            // System install
        ]

        let fm = FileManager.default
        for path in possiblePaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        // Try which command as fallback
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["whisper-server"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {
            // Ignore
        }

        return nil
    }

    // MARK: - Lifecycle

    deinit {
        serverProcess?.terminate()
    }
}
