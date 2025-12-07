import Foundation

/// A simple file-based logger for debugging streaming transcription.
/// Logs are written to ~/Library/Logs/WhisperVillage/streaming.log
class StreamingLogger {
    static let shared = StreamingLogger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.whispervillage.streaminglogger")

    private init() {
        // Create log directory
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WhisperVillage")

        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        logFileURL = logsDir.appendingPathComponent("streaming.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        // Clear old log on init
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)

        log("=== StreamingLogger initialized ===")
        log("Log file: \(logFileURL.path)")
    }

    func log(_ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"

            if let data = line.data(using: .utf8),
               let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                // File doesn't exist, create it
                try? line.write(to: self.logFileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Get the log file path for reading
    var path: String {
        logFileURL.path
    }
}
