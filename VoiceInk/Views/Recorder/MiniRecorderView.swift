import SwiftUI
import SwiftData

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

    // MARK: - Chat Bubble Streaming Preview

    /// Dimensions for the preview area (30% larger)
    private let previewBoxHeight: CGFloat = 210
    private let previewBoxWidth: CGFloat = 416

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
                        ? Color(red: 0.3, green: 0.3, blue: 0.35) // Slightly lighter for live
                        : Color(red: 0.2, green: 0.2, blue: 0.25)) // Darker for committed
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isLive
                            ? Color(red: 1.0, green: 0.5, blue: 0.2).opacity(0.5) // Orange tint for live
                            : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: previewBoxWidth - 40, alignment: .leading)
    }

    private var streamingBubblesView: some View {
        Group {
            let hasContent = !whisperState.committedChunks.isEmpty || !whisperState.interimTranscription.isEmpty
            let isRecording = whisperState.recordingState == .recording

            if isStreamingModeEnabled && isRecording {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: previewBoxWidth, height: hasContent ? previewBoxHeight : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .opacity(hasContent ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: hasContent)
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
                .transition(.opacity)
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
        HStack(spacing: 8) { // More balanced spacing
            // Cancel button with debug background
            Button(action: {
                Task { @MainActor in
                    await whisperState.dismissMiniRecorder()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14)) // Smaller
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 24) // Comfortable padding from edge
            
            // Constrained visualizer zone - centered with balanced spacing
            Spacer()
            statusView
                .frame(width: 80) // Slightly smaller to accommodate more padding
            Spacer()
            
            // Timer display with debug background - always visible, changes color based on state
            Text(formatTime(recordingDuration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(whisperState.recordingState == .recording ? .white : .white.opacity(0.6))
                .frame(width: 35) // Fixed width so layout doesn't shift
                .padding(.trailing, 24) // Comfortable padding from edge
        }
        .padding(.vertical, 6) // Even more compact
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
                VStack(spacing: 16) {
                    Spacer(minLength: 0)

                    // Chat bubble streaming preview
                    streamingBubblesView

                    // The orange capsule recorder (fixed size to prevent balloon bug)
                    recorderCapsule
                        .frame(width: 250, height: 36)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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


