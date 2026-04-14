import Foundation
import Network
import SwiftData
import os

/// Tiny HTTP server on port 8179 for fire-and-forget presenter integration.
/// POST /claim { "cardId": "..." } — stops recording, transcribes in background,
/// POSTs result to http://localhost:3005/api/presenter/respond
class PresenterClaimServer {
    static let shared = PresenterClaimServer()

    private let port: UInt16 = 8179
    private var listener: NWListener?
    private let logger = Logger(subsystem: "town.mullet.WhisperVillage", category: "PresenterClaimServer")
    private weak var whisperState: WhisperState?

    private init() {}

    func start(whisperState: WhisperState) {
        self.whisperState = whisperState

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.logger.notice("PresenterClaimServer listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    self?.logger.error("PresenterClaimServer failed: \(error.localizedDescription)")
                default:
                    break
                }
            }
            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            logger.error("Failed to start PresenterClaimServer: \(error.localizedDescription)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self = self, let data = data else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""

            // Handle CORS preflight for all endpoints
            if request.hasPrefix("OPTIONS ") {
                self.sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
                return
            }

            if request.hasPrefix("POST /claim") {
                // Extract JSON body from HTTP request
                if let bodyStart = request.range(of: "\r\n\r\n") {
                    let bodyString = String(request[bodyStart.upperBound...])
                    self.handleClaim(bodyString: bodyString, connection: connection)
                } else {
                    self.sendResponse(connection: connection, status: 400, body: "{\"error\":\"No body\"}")
                }
            } else if request.hasPrefix("POST /peek") || request.hasPrefix("GET /peek") {
                self.handlePeek(connection: connection)
            } else if request.hasPrefix("POST /cancel") || request.hasPrefix("GET /cancel") {
                self.handleCancel(connection: connection)
            } else if request.hasPrefix("GET /status") {
                self.handleStatus(connection: connection)
            } else if request.hasPrefix("POST /log-transcription") {
                if let bodyStart = request.range(of: "\r\n\r\n") {
                    let bodyString = String(request[bodyStart.upperBound...])
                    self.handleLogTranscription(bodyString: bodyString, connection: connection)
                } else {
                    self.sendResponse(connection: connection, status: 400, body: "{\"error\":\"No body\"}")
                }
            } else if request.hasPrefix("GET /health") {
                self.sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
            } else {
                self.sendResponse(connection: connection, status: 404, body: "{\"error\":\"Not found\"}")
            }
        }
    }

    private func handlePeek(connection: NWConnection) {
        logger.notice("Peek requested")

        Task { @MainActor in
            guard let whisperState = self.whisperState else {
                self.sendResponse(connection: connection, status: 200, body: "{\"transcript\":\"Whisper Village not ready\"}")
                return
            }

            // Trigger the peek transcription (same as tapping Peek in the notch bar)
            await whisperState.peekTranscription()

            // Return the current transcription text (peek also stores, so it's cleaned)
            let rawText = whisperState.interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastText = LastTranscriptionService.shared.lastText ?? ""
            // Store interim so it gets cleaned too
            if !rawText.isEmpty {
                LastTranscriptionService.shared.store(rawText)
            }
            let result = LastTranscriptionService.shared.lastText ?? lastText

            let escaped = result.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "\"", with: "\\\"")
                                .replacingOccurrences(of: "\n", with: "\\n")
            self.sendResponse(connection: connection, status: 200, body: "{\"transcript\":\"\(escaped)\"}")
        }
    }

    private func handleStatus(connection: NWConnection) {
        Task { @MainActor in
            let isRecording = self.whisperState?.recordingState == .recording || self.whisperState?.recordingState == .paused
            let hasTranscript = !(LastTranscriptionService.shared.lastText ?? "").isEmpty
            self.sendResponse(connection: connection, status: 200, body: "{\"ok\":true,\"recording\":\(isRecording),\"hasTranscript\":\(hasTranscript)}")
        }
    }

    private func handleCancel(connection: NWConnection) {
        logger.notice("Cancel recording requested")
        sendResponse(connection: connection, status: 200, body: "{\"cancelled\":true}")

        Task { @MainActor in
            guard let whisperState = self.whisperState else { return }
            await whisperState.dismissMiniRecorder()
        }
    }

    private func handleLogTranscription(bodyString: String, connection: NWConnection) {
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let text = json["text"] as? String, !text.isEmpty else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"text required\"}")
            return
        }

        guard self.whisperState != nil else {
            logger.error("Log transcription failed: whisperState is nil")
            sendResponse(connection: connection, status: 503, body: "{\"error\":\"not ready\"}")
            return
        }

        let duration = json["duration"] as? Double ?? 0
        let source = json["source"] as? String ?? "phone"

        // Support optional timestamp from caller (Unix epoch seconds).
        // Convert to Swift Date properly — callers send seconds-since-1970,
        // NOT seconds-since-reference-date (2001-01-01).
        let timestamp: Date
        if let epochSeconds = json["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: epochSeconds)
        } else {
            timestamp = Date()
        }

        logger.notice("Log transcription from \(source): \(text.prefix(50))...")

        Task { @MainActor in
            guard let whisperState = self.whisperState else {
                self.logger.error("Log transcription failed: whisperState became nil")
                return
            }
            let newTranscription = Transcription(
                text: text,
                duration: duration,
                timestamp: timestamp,
                transcriptionModelName: source
            )
            whisperState.modelContext.insert(newTranscription)
            do {
                try whisperState.modelContext.save()
                self.logger.notice("Transcription saved successfully")
            } catch {
                self.logger.error("Failed to save transcription: \(error.localizedDescription)")
            }
        }

        sendResponse(connection: connection, status: 200, body: "{\"logged\":true}")
    }

    private func handleClaim(bodyString: String, connection: NWConnection) {
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let cardId = json["cardId"] as? String else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"cardId required\"}")
            return
        }

        logger.notice("Claim received for card: \(cardId)")

        // Return immediately — transcription happens async
        sendResponse(connection: connection, status: 200, body: "{\"claimed\":true,\"cardId\":\"\(cardId)\"}")

        // Fire-and-forget: stop recording, transcribe, send to presenter
        Task { @MainActor in
            await self.claimAndTranscribe(cardId: cardId)
        }
    }

    @MainActor
    private func claimAndTranscribe(cardId: String) async {
        guard let whisperState = whisperState else {
            logger.error("WhisperState not available")
            return
        }

        // Get current text or transcribe
        var text = ""

        if whisperState.recordingState == .recording || whisperState.recordingState == .paused {
            // Currently recording — stop, transcribe the audio
            logger.notice("Stopping recording for claim \(cardId)")

            // Get streaming interim if available
            let interim = whisperState.interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)

            // Stop recording
            await whisperState.stopStreamingTranscription()
            let samples = await whisperState.streamingRecorder.getCurrentSamples()
            _ = await whisperState.streamingRecorder.stopRecording()
            await whisperState.recorder.stopRecording()

            // Transcribe the captured audio
            if samples.count > 16000 {
                if let transcribed = await whisperState.transcribeCapturedSamples(samples) {
                    text = transcribed.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // Fall back to streaming interim if transcription failed
            if text.isEmpty && !interim.isEmpty {
                text = interim
            }

            // Dismiss the recorder UI
            await whisperState.dismissMiniRecorder()

        } else {
            // Not recording — use last transcription if available
            text = LastTranscriptionService.shared.lastText ?? ""
        }

        guard !text.isEmpty else {
            logger.notice("No text to send for claim \(cardId)")
            return
        }

        // Store as last transcription
        LastTranscriptionService.shared.store(text)

        // Save to SwiftData history
        let newTranscription = Transcription(
            text: text,
            duration: 0,
            transcriptionModelName: "Presenter Claim"
        )
        whisperState.modelContext.insert(newTranscription)
        try? whisperState.modelContext.save()

        // POST to presenter respond endpoint
        logger.notice("Sending response for card \(cardId): \(text.prefix(50))...")
        await postToPresenter(cardId: cardId, text: text)
    }

    private func postToPresenter(cardId: String, text: String) async {
        guard let url = URL(string: "http://localhost:3005/api/presenter/respond") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "id": cardId,
            "text": text,
            "button": "Reply"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                logger.notice("Presenter respond: HTTP \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("Failed to POST to presenter: \(error.localizedDescription)")
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: POST, GET, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
