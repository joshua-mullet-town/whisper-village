import Foundation
import SwiftData

@Model
final class Transcription {
    var id: UUID
    var text: String
    var timestamp: Date
    var duration: TimeInterval
    var transcriptionModelName: String?

    init(text: String, duration: TimeInterval, timestamp: Date = Date(), transcriptionModelName: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.transcriptionModelName = transcriptionModelName
    }
}
