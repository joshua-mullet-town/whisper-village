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

    private var streamingBubblesView: some View {
        Group {
            let hasContent = !whisperState.committedChunks.isEmpty || !whisperState.interimTranscription.isEmpty
            let isRecording = whisperState.recordingState == .recording
            let shouldShow = isStreamingModeEnabled && isRecording && isPreviewVisible

            // Always allocate space when streaming mode enabled, use opacity to hide/show
            if isStreamingModeEnabled {
                ZStack(alignment: .topTrailing) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                // Placeholder when waiting for first words
                                if !hasContent {
                                    Text("Listening...")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .id("placeholder")
                                }

                                // Committed chunks (locked in)
                                ForEach(Array(whisperState.committedChunks.enumerated()), id: \.offset) { index, chunk in
                                    if !chunk.isEmpty {
                                        chatBubble(text: chunk, isLive: false)
                                            .id("chunk-\(index)")
                                    }
                                }

                                // Live preview (still being corrected)
                                if !whisperState.interimTranscription.isEmpty {
                                    chatBubble(text: whisperState.interimTranscription, isLive: true)
                                        .id("live")
                                }
                            }
                            .padding(12)
                            .padding(.top, 24) // Space for controls
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .onChange(of: whisperState.interimTranscription) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("live", anchor: .bottom)
                            }
                        }
                        .onChange(of: whisperState.committedChunks.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("live", anchor: .bottom)
                            }
                        }
                    }

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


