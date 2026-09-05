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
    private var modelContainer: ModelContainer?

    private init() {}

    func start(whisperState: WhisperState, modelContainer: ModelContainer? = nil) {
        self.whisperState = whisperState
        self.modelContainer = modelContainer

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
            } else if request.hasPrefix("POST /start") || request.hasPrefix("GET /start") {
                let bodyString = request.range(of: "\r\n\r\n").map { String(request[$0.upperBound...]) } ?? ""
                self.handleStart(bodyString: bodyString, connection: connection)
            } else if request.hasPrefix("GET /health") {
                self.sendResponse(connection: connection, status: 200, body: "{\"ok\":true}")
            } else {
                self.sendResponse(connection: connection, status: 404, body: "{\"error\":\"Not found\"}")
            }
        }
    }

    // MARK: - Voice-triggered dictation ("Hey Alfred")
    //
    // POST /start { "deliverTo": "holler-alfred", "silenceMs": 1800, "maxMs": 30000 }
    //
    // Opens the normal mini recorder — the same one the hotkey opens, with the
    // same start sound — then stops on its own once you stop talking, and sends
    // the transcript to a steward instead of pasting it at the cursor.
    //
    // Stopping is hands-free by design: you can't press a key from across the
    // room. We watch the live audio meter and end the message after a pause,
    // which is why `silenceMs` is tunable rather than hard-coded.

    private func handleStart(bodyString: String, connection: NWConnection) {
        let json = (try? JSONSerialization.jsonObject(
            with: Data(bodyString.utf8))) as? [String: Any] ?? [:]

        let deliverTo = json["deliverTo"] as? String ?? "holler-alfred"
        let silenceMs = json["silenceMs"] as? Int ?? 1800
        let maxMs = json["maxMs"] as? Int ?? 30000

        Task { @MainActor in
            guard let whisperState = self.whisperState else {
                self.sendResponse(connection: connection, status: 503,
                                  body: "{\"error\":\"not ready\"}")
                return
            }
            guard whisperState.recordingState != .recording else {
                // Already recording (hotkey, or a second wake fired). Don't
                // hijack a dictation the user started themselves.
                self.sendResponse(connection: connection, status: 409,
                                  body: "{\"error\":\"already recording\"}")
                return
            }

            self.logger.notice("Voice-triggered dictation starting, will deliver to \(deliverTo)")
            self.sendResponse(connection: connection, status: 200,
                              body: "{\"started\":true,\"deliverTo\":\"\(deliverTo)\"}")

            // Paint the recorder gold — this one is going to a steward, not the cursor.
            whisperState.deliveringToSteward = deliverTo

            // Ride the hotkey's own path: post the notification rather than
            // calling toggleMiniRecorder() directly. The observer wraps the call
            // in its own un-awaited Task, so it returns immediately; awaiting the
            // method here instead pinned the main actor for the whole recording
            // and deadlocked every other request.
            NotificationCenter.default.post(name: .toggleMiniRecorder, object: nil)

            // Detached on purpose: called from a @MainActor task, this would
            // otherwise INHERIT the main actor and hold it for the whole wait,
            // which deadlocks every other request (and the UI) until the
            // recording ends.
            Task.detached { [weak self] in
                await self?.stopOnSilenceThenDeliver(deliverTo: deliverTo,
                                                     silenceMs: silenceMs,
                                                     maxMs: maxMs)
            }
        }
    }

    /// Wait for the speaker to finish, then stop and hand the text off.
    ///
    /// Deliberately NOT @MainActor as a whole: this waits for up to `maxMs`, and
    /// holding the main actor that long would stall every other request (and the
    /// UI). It hops onto the main actor only for the instant it takes to read
    /// state, then gets off again.
    private func stopOnSilenceThenDeliver(deliverTo: String, silenceMs: Int, maxMs: Int) async {
        let tick = 100                     // how often we look at the meter
        let speechLevel = 0.14             // above this counts as "still talking"
        let graceMs = 3000                 // give them a moment to start talking

        // The recorder is started via a notification, so it comes up a moment
        // after we're asked to watch it. Wait for it to actually be recording
        // before we start judging silence — otherwise we'd see "not recording"
        // on the first tick and bail out as if the user had cancelled.
        var waitedToStart = 0
        while waitedToStart < 4000 {
            let isRecording = await MainActor.run {
                self.whisperState?.recordingState == .recording
            }
            if isRecording { break }
            try? await Task.sleep(nanoseconds: 100 * 1_000_000)
            waitedToStart += 100
        }
        let didStart = await MainActor.run {
            self.whisperState?.recordingState == .recording
        }
        guard didStart else {
            logger.notice("Recorder never started; nothing to deliver")
            return
        }

        var elapsed = 0
        var quietFor = 0
        var heardSpeech = false

        while elapsed < maxMs {
            try? await Task.sleep(nanoseconds: UInt64(tick) * 1_000_000)
            elapsed += tick

            // One quick hop onto the main actor to read state, then straight off.
            let snapshot: (stillRecording: Bool, level: Double)? = await MainActor.run {
                guard let ws = self.whisperState else { return nil }
                return (ws.recordingState == .recording,
                        ws.streamingRecorder.audioMeter.averagePower)
            }
            guard let snapshot else { return }

            // User stopped it themselves (hotkey / cancel) — leave it alone.
            if !snapshot.stillRecording {
                logger.notice("Recording ended by the user; not delivering")
                return
            }

            if snapshot.level > speechLevel {
                heardSpeech = true
                quietFor = 0
            } else {
                quietFor += tick
            }

            if heardSpeech && quietFor >= silenceMs { break }
            if !heardSpeech && elapsed > graceMs { break }
        }

        await finishAndDeliver(deliverTo: deliverTo, heardSpeech: heardSpeech)
    }

    @MainActor
    private func finishAndDeliver(deliverTo: String, heardSpeech: Bool) async {
        guard let whisperState = whisperState else { return }

        guard heardSpeech else {
            // Nothing was said — discard rather than send an empty message.
            logger.notice("No speech heard; discarding")
            await whisperState.stopStreamingTranscription()
            _ = await whisperState.streamingRecorder.stopRecording()
            await whisperState.recorder.stopRecording()
            await whisperState.dismissMiniRecorder()
            return
        }

        let interim = whisperState.interimTranscription
            .trimmingCharacters(in: .whitespacesAndNewlines)

        await whisperState.stopStreamingTranscription()
        let samples = await whisperState.streamingRecorder.getCurrentSamples()
        _ = await whisperState.streamingRecorder.stopRecording()
        await whisperState.recorder.stopRecording()

        var text = ""
        if samples.count > 16000, let transcribed =
            await whisperState.transcribeCapturedSamples(samples) {
            text = transcribed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty { text = interim }

        await whisperState.dismissMiniRecorder()

        guard !text.isEmpty else {
            logger.notice("Nothing transcribed; nothing sent")
            return
        }

        LastTranscriptionService.shared.store(text)
        if let container = self.modelContainer {
            let context = container.mainContext
            context.insert(Transcription(text: text, duration: 0,
                                         transcriptionModelName: "Voice → \(deliverTo)"))
            try? context.save()
        }

        await deliverToSteward(session: deliverTo, text: text)
    }

    /// Hand the spoken message to a steward through the Homestead queue.
    private func deliverToSteward(session: String, text: String) async {
        guard let url = URL(string: "http://localhost:3005/api/queue") else { return }

        // The reply instructions ride along in the message itself, so any steward
        // reached this way knows to answer out loud rather than with a card --
        // Joshua is across the room, not looking at a screen.
        let speakTool = "\(NSHomeDirectory())/.homestead/stewards/mcgucket/workers/"
            + "hey-alfred/listener/speak.mjs"

        let instruction = """
        Joshua spoke this out loud to the listening device in the room. Treat it as a \
        direct message from him and act on it.

        He said: "\(text)"

        HOW TO REPLY — OUT LOUD, NOT WITH A CARD. He is across the room and is not \
        looking at a screen, so a card is invisible to him. Do NOT send him a card for \
        this. Reply by running:

            node "\(speakTool)" --text "your reply"

        Add --ask when your reply is a question:

            node "\(speakTool)" --text "Which Thursday?" --ask

        --ask reopens the microphone the moment you stop speaking, so he can answer \
        straight away without saying the wake phrase again. His answer comes back to \
        you as another message like this one. Keep asking until you know what he wants, \
        then do it and confirm out loud.

        KEEP IT VERY SHORT. This is spoken aloud, so every word costs him time. A \
        confirmation should be about three words ("Added to your calendar."). A question \
        should be the shortest one that resolves the ambiguity ("Which Thursday?"). Never \
        read back what he said, never explain what you are about to do, never list \
        options unless he must choose between them. Most requests should be one and done: \
        do the thing, say it is done, stop.
        """

        let envelope: [String: Any] = [
            "type": "action",
            "from": "hey-alfred-device",
            "instruction": instruction,
            "spoken_text": text,
            "source": "hey-alfred-room-device",
            "reply_with": "voice",
            "speak_tool": speakTool,
        ]
        guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelope),
              let envelopeString = String(data: envelopeData, encoding: .utf8) else { return }

        let payload: [String: Any] = [
            "target_session": session,
            "message_override": envelopeString,
            "type": "action",
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                logger.notice("Delivered to \(session): \(text.prefix(50))...")
                SoundManager.shared.playStopSound()
            } else {
                logger.error("Delivery to \(session) failed: HTTP \(code)")
            }
        } catch {
            logger.error("Delivery to \(session) failed: \(error.localizedDescription)")
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

        guard let container = self.modelContainer else {
            logger.error("Log transcription failed: modelContainer is nil")
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

        logger.notice("Log transcription from \(source), timestamp: \(timestamp): \(text.prefix(50))...")

        Task.detached {
            let context = ModelContext(container)
            let newTranscription = Transcription(
                text: text,
                duration: duration,
                timestamp: timestamp,
                transcriptionModelName: source
            )
            context.insert(newTranscription)
            do {
                try context.save()
                self.logger.notice("Transcription saved via background context, timestamp=\(timestamp.timeIntervalSinceReferenceDate)")
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
        if let container = self.modelContainer {
            let context = container.mainContext
            let newTranscription = Transcription(
                text: text,
                duration: 0,
                transcriptionModelName: "Presenter Claim"
            )
            context.insert(newTranscription)
            try? context.save()
        }

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
