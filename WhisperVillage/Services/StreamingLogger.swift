import Foundation
import os

/// Minimal logging stub — replaced the heavy StreamingLogger with os.Logger
class StreamingLogger {
    static let shared = StreamingLogger()
    private let logger = Logger(subsystem: "com.voiceink.app", category: "StreamingLogger")

    func log(_ message: String) {
        logger.notice("\(message)")
    }
}
