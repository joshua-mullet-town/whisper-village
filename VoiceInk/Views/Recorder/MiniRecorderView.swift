import SwiftUI
import SwiftData
import AppKit

// MARK: - Window Drag Blocker
// Blocks isMovableByWindowBackground for specific areas (like resize handles)
struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> BlockingView {
        BlockingView()
    }

    func updateNSView(_ nsView: BlockingView, context: Context) {}

    class BlockingView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @Environment(\.modelContext) private var modelContext
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?

    /// Whether streaming mode is enabled (for showing preview)
    private var isStreamingModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "StreamingModeEnabled")
    }

    /// Whether preview box is visible (persisted)
    @AppStorage("StreamingPreviewVisible") private var isPreviewVisible: Bool = true

    /// Preview box opacity (persisted)
    @AppStorage("StreamingPreviewOpacity") private var previewOpacity: Double = 0.85

    /// Preview box dimensions (persisted)
    @AppStorage("StreamingPreviewWidth") private var previewWidth: Double = 416
    @AppStorage("StreamingPreviewHeight") private var previewHeight: Double = 210

    // MARK: - Chat Bubble Streaming Preview

    /// Min/max dimensions for resizing
    private let minPreviewWidth: CGFloat = 280
    private let maxPreviewWidth: CGFloat = 600
    private let minPreviewHeight: CGFloat = 100
    private let maxPreviewHeight: CGFloat = 400

    /// Single chat bubble view
    private func chatBubble(text: String, isLive: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isLive
                        ? Color(red: 0.3, green: 0.3, blue: 0.35).opacity(previewOpacity)
                        : Color(red: 0.2, green: 0.2, blue: 0.25).opacity(previewOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isLive
                            ? Color(red: 1.0, green: 0.5, blue: 0.2).opacity(0.5 * previewOpacity)
                            : Color.white.opacity(0.1 * previewOpacity),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: CGFloat(previewWidth) - 40, alignment: .leading)
    }

    /// Debug log entry view - unified bubble design with state indicators
    @ViewBuilder
    private func debugLogEntryView(_ entry: DebugLogEntry) -> some View {
        switch entry {
        case .transcription(_, let text):
            transcriptionBubble(text: text)
        case .sentTranscription(_, let text):
            sentTranscriptionBubble(text: text)
        case .commandDetected(_, _, let parsed):
            commandPillView(parsed: parsed)
        case .listening:
            listeningPillView
        }
    }

    /// Pending transcription bubble - gray waveform
    private func transcriptionBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.2, green: 0.25, blue: 0.3).opacity(previewOpacity))
        )
        .frame(maxWidth: CGFloat(previewWidth) - 40, alignment: .leading)
    }

    /// Sent transcription bubble - green checkmark
    private func sentTranscriptionBubble(text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green.opacity(0.7))
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.15, green: 0.2, blue: 0.18).opacity(previewOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.green.opacity(0.2), lineWidth: 1)
        )
        .frame(maxWidth: CGFloat(previewWidth) - 40, alignment: .leading)
    }

    /// Listening pill view
    private var listeningPillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 9))
            Text("Listening...")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.green.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.1 * previewOpacity))
        )
    }

    /// Helper to create command pill views with contextual icon and color
    private func commandPillView(parsed: String) -> some View {
        let icon: String
        let color: Color

        switch parsed.lowercased() {
        case "paused": icon = "pause.fill"; color = .orange
        case "listening": icon = "ear.fill"; color = .green
        case "sent": icon = "paperplane.fill"; color = .blue
        case "stopped": icon = "stop.fill"; color = .red
        default: icon = "arrow.right.circle.fill"; color = .yellow  // navigation/other
        }

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(parsed)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(color.opacity(0.9))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.15 * previewOpacity))
        )
    }

    /// Live transcription bubble - orange, currently being transcribed (larger font for readability)
    private var liveTranscriptionBubble: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundColor(.orange.opacity(0.8))
            Text(whisperState.interimTranscription)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.3, green: 0.25, blue: 0.2).opacity(previewOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1.5)
        )
        .frame(maxWidth: CGFloat(previewWidth) - 40, alignment: .leading)
        .id("live-transcription")
    }

    /// Pause help indicator - tells user how to resume
    private var pauseHelpIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "pause.fill")
                .font(.system(size: 10))
            Text("Say \"Jarvis listen\" to resume")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.2 * previewOpacity))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .id("pause-indicator")
    }

    private var streamingBubblesView: some View {
        Group {
            let hasContent = !whisperState.debugLog.isEmpty
            let isRecording = whisperState.recordingState == .recording
            let shouldShow = isStreamingModeEnabled && isRecording && isPreviewVisible

            // Always allocate space when streaming mode enabled, use opacity to hide/show
            if isStreamingModeEnabled {
                ZStack(alignment: .topTrailing) {
                    // Using defaultScrollAnchor(.bottom) - iOS 17+ / macOS 14+
                    // This automatically:
                    // - Starts at bottom
                    // - Stays anchored to bottom when content changes
                    // - If user scrolls manually, it scrolls freely (no auto-scroll back)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            // Placeholder when empty and no live transcription
                            if !hasContent && whisperState.interimTranscription.isEmpty {
                                Text("Listening...")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }

                            // Debug log entries (permanent, never removed)
                            ForEach(whisperState.debugLog) { entry in
                                debugLogEntryView(entry)
                            }

                            // Live interim transcription (updates in place, not permanent)
                            if !whisperState.interimTranscription.isEmpty && !whisperState.isInJarvisCommandMode {
                                liveTranscriptionBubble
                            }

                            // Current pause indicator (if paused) - more prominent pill with help text
                            if whisperState.isInJarvisCommandMode {
                                pauseHelpIndicator
                            }

                            // Bottom spacer for breathing room
                            Color.clear
                                .frame(height: 24)
                        }
                        .padding(12)
                        .padding(.top, 24) // Space for controls
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)

                    // Controls overlay (top-right)
                    HStack(spacing: 8) {
                        // Transparency controls
                        Button(action: { previewOpacity = max(0.3, previewOpacity - 0.15) }) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { previewOpacity = min(1.0, previewOpacity + 0.15) }) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(6)
                }
                .frame(width: CGFloat(previewWidth), height: CGFloat(previewHeight))
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(previewOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    // Resize handle - uses WindowDragBlocker to prevent window movement
                    ZStack {
                        WindowDragBlocker()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let newWidth = previewWidth + Double(value.translation.width)
                                let newHeight = previewHeight - Double(value.translation.height)
                                previewWidth = min(maxPreviewWidth, max(minPreviewWidth, newWidth))
                                previewHeight = min(maxPreviewHeight, max(minPreviewHeight, newHeight))
                            }
                    )
                }
                .opacity(shouldShow ? 1 : 0) // Hide via opacity instead of removing from layout
            }
        }
    }

    private var backgroundView: some View {
        ZStack {
            // Mullet Town themed background
            LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.4, blue: 0.1).opacity(0.8), // Orange
                    Color(red: 0.8, green: 0.2, blue: 0.1).opacity(0.9)  // Red
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Hazy yellow accent overlay
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.9, blue: 0.4).opacity(0.3), // Hazy yellow
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .opacity(0.1)
        }
        .clipShape(Capsule())
    }
    
    private var statusView: some View {
        RecorderStatusDisplay(
            currentState: whisperState.recordingState,
            audioMeter: recorder.audioMeter
        )
    }
    
    private var contentLayout: some View {
        HStack(spacing: 8) {
            // Cancel button
            Button(action: {
                Task { @MainActor in
                    await whisperState.dismissMiniRecorder()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 16)

            Spacer()
            statusView
                .frame(width: 80)
            Spacer()

            // Eyeball toggle (only when streaming mode enabled) - right side near timer
            if isStreamingModeEnabled {
                Button(action: { isPreviewVisible.toggle() }) {
                    Image(systemName: isPreviewVisible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Timer display
            Text(formatTime(recordingDuration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(whisperState.recordingState == .recording ? .white : .white.opacity(0.6))
                .frame(width: 35)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 6)
    }
    
    private var recorderCapsule: some View {
        Capsule()
            .fill(.clear)
            .background(backgroundView)
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.0) // More prominent border
            }
            .overlay {
                contentLayout
            }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                // Fixed layout: preview box space always allocated, capsule always at bottom
                VStack(spacing: 16) {
                    Spacer(minLength: 0)

                    // Preview box - always takes space, hidden via opacity when not active
                    streamingBubblesView

                    // Orange capsule - always at bottom
                    recorderCapsule
                        .frame(width: 250, height: 36)
                }
                .padding(.bottom, 8)
                .onChange(of: whisperState.recordingState) { _, newState in
                    if newState == .recording {
                        recordingDuration = 0
                        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                            recordingDuration += 0.1
                        }
                    } else if newState == .transcribing {
                        // Keep timer visible but stop updating
                        timer?.invalidate()
                        timer = nil
                    } else {
                        // Only reset on other states (idle, error, etc.)
                        timer?.invalidate()
                        timer = nil
                        recordingDuration = 0
                    }
                }
            }
        }
    }
}


