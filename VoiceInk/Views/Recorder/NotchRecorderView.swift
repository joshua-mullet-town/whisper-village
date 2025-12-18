import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @ObservedObject var streamingRecorder: StreamingRecorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isPreviewVisible = true

    // Settings for eyeball button behavior
    @AppStorage("StreamingModeEnabled") private var isStreamingModeEnabled = false
    @AppStorage("LivePreviewEnabled") private var isLivePreviewEnabled = true
    @AppStorage("NotchAlwaysVisible") private var isAlwaysVisible = false

    /// Whether we're in idle state (always visible but not recording)
    private var isIdleState: Bool {
        isAlwaysVisible && whisperState.recordingState == .idle
    }
    
    private var menuBarHeight: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.top > 0 {
                return screen.safeAreaInsets.top
            }
            return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
        }
        return NSStatusBar.system.thickness
    }
    
    private var exactNotchWidth: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.left > 0 {
                return screen.safeAreaInsets.left * 2
            }
            return 200
        }
        return 200
    }
    
    /// Total width for each side section (content + padding)
    private let sectionWidth: CGFloat = 100

    private var leftSection: some View {
        HStack(spacing: 8) {
            // Cancel button - hide when idle
            if !isIdleState {
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
                .help("Cancel recording")
            }

            // Timer display
            if whisperState.recordingState == .recording {
                Text(formatTime(recordingDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 35)
            }

            Spacer()
        }
        .padding(.leading, 12)
        .frame(width: sectionWidth)
    }
    
    private var centerSection: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: exactNotchWidth)
            .contentShape(Rectangle())
    }
    
    private var rightSection: some View {
        HStack(spacing: 6) {
            Spacer()

            // Peek button - show full transcription toast (only when recording)
            if isStreamingModeEnabled && !isIdleState && whisperState.recordingState == .recording {
                Button(action: {
                    Task { @MainActor in
                        await whisperState.peekTranscription()
                    }
                }) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Show full transcription")
            }

            // Eyeball button - toggle ticker visibility (only in Live Preview mode)
            if isStreamingModeEnabled && isLivePreviewEnabled && !isIdleState {
                Button(action: {
                    isPreviewVisible.toggle()
                }) {
                    Image(systemName: isPreviewVisible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle ticker")
            }
        }
        .padding(.trailing, 10)
        .frame(width: sectionWidth)
    }

    /// Normalized audio level (0.0 to 1.0) from the active recorder
    private var normalizedAudioLevel: CGFloat {
        // Use streaming recorder when in streaming mode, otherwise standard recorder
        if isStreamingModeEnabled {
            // StreamingRecorder.audioMeter already normalized to 0-1 range
            let power = streamingRecorder.audioMeter.averagePower
            return CGFloat(min(1.0, max(0.0, power)))
        } else {
            // Standard recorder: averagePower is in dB, typically -160 (silence) to 0 (max)
            // Map -50dB to 0dB range to 0.0-1.0
            let power = recorder.audioMeter.averagePower
            let normalized = (power + 50) / 50
            return CGFloat(min(1.0, max(0.0, normalized)))
        }
    }

    /// How far down the highlight gradient extends (0.0 = top only, 1.0 = full height)
    private var highlightExtent: UnitPoint {
        guard whisperState.recordingState == .recording else { return UnitPoint(x: 0.5, y: 0.3) }
        // Quiet: highlight ends at 30% down. Loud: highlight extends to 80% down
        let extent = 0.3 + (Double(normalizedAudioLevel) * 0.5)
        return UnitPoint(x: 0.5, y: extent)
    }

    /// Highlight opacity based on audio
    private var highlightOpacity: Double {
        guard whisperState.recordingState == .recording else { return 0.3 }
        // Base 0.3, up to 0.6 when loud
        return 0.3 + (Double(normalizedAudioLevel) * 0.3)
    }

    /// Inner glow opacity that pulses with audio (subtle)
    private var innerGlowOpacity: Double {
        guard whisperState.recordingState == .recording else { return 0.0 }
        // 0.0 when quiet, up to 0.4 when loud (reduced from 0.7)
        return Double(normalizedAudioLevel) * 0.4
    }

    /// Inner glow blur radius
    private var innerGlowRadius: CGFloat {
        guard whisperState.recordingState == .recording else { return 0 }
        // 0 when quiet, up to 15 when loud (reduced from 20)
        return normalizedAudioLevel * 15
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Background that changes based on state
    @ViewBuilder
    private var stateBackground: some View {
        if isIdleState {
            // Idle state: very subtle, almost invisible gray
            // Brightens on hover to show interactivity
            Color.gray.opacity(isHovering ? 0.35 : 0.15)
        } else if whisperState.recordingState == .transcribing {
            // Transcribing state: subtle blue processing indicator
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.6),
                    Color.blue.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Recording state (or normal show): full orange/red gradient with animated highlight
            ZStack {
                // Base gradient - constant
                LinearGradient(
                    colors: [
                        Color(red: 0.9, green: 0.4, blue: 0.1).opacity(0.8),
                        Color(red: 0.8, green: 0.2, blue: 0.1).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Highlight gradient - extent and opacity animated with audio
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.9, blue: 0.4).opacity(highlightOpacity),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: highlightExtent
                )
            }
        }
    }
    
    /// Whether to show live transcription ticker (streaming mode + live preview enabled)
    private var shouldShowTicker: Bool {
        isStreamingModeEnabled && isLivePreviewEnabled && !isIdleState
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                VStack(spacing: 4) {
                    // Main notch bar
                    HStack(spacing: 0) {
                        leftSection
                        centerSection
                        rightSection
                    }
                    .frame(height: menuBarHeight)
                    .frame(maxWidth: windowManager.isVisible ? .infinity : 0)
                    .background(stateBackground)
                    .mask {
                        NotchShape(cornerRadius: 10)
                    }
                    .overlay {
                        // Inner glow that pulses inward with audio
                        NotchShape(cornerRadius: 10)
                            .stroke(
                                Color.white.opacity(innerGlowOpacity),
                                lineWidth: 8
                            )
                            .blur(radius: innerGlowRadius)
                            .mask {
                                NotchShape(cornerRadius: 10)
                            }
                    }
                    .overlay {
                        // Subtle constant border for definition
                        NotchShape(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }
                    .clipped()
                    .contentShape(NotchShape(cornerRadius: 10))
                    .onTapGesture {
                        // Click to start recording when idle
                        if isIdleState {
                            Task { @MainActor in
                                await whisperState.handleToggleMiniRecorder()
                            }
                        }
                    }
                    .animation(.linear(duration: 0.05), value: recorder.audioMeter.averagePower)
                    .animation(.linear(duration: 0.05), value: streamingRecorder.audioMeter.averagePower)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: whisperState.recordingState)
                    .animation(.easeInOut(duration: 0.2), value: isHovering)

                    // Live transcription ticker below notch
                    if shouldShowTicker && isPreviewVisible {
                        NotchTranscriptionTicker(
                            text: whisperState.interimTranscription,
                            isRecording: whisperState.recordingState == .recording
                        )
                        .padding(.horizontal, 8)
                    }
                }
                .opacity(windowManager.isVisible ? 1 : 0)
                .onChange(of: whisperState.recordingState) { _, newState in
                    if newState == .recording {
                        recordingDuration = 0
                        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                            recordingDuration += 0.1
                        }
                    } else {
                        timer?.invalidate()
                        timer = nil
                        recordingDuration = 0
                    }
                }
                .onAppear {
                    StreamingLogger.shared.log("🖼️ NotchRecorderView APPEARED")
                    StreamingLogger.shared.log("  windowManager.isVisible: \(windowManager.isVisible)")
                    StreamingLogger.shared.log("  shouldShowTicker: \(shouldShowTicker)")
                    StreamingLogger.shared.log("  isStreamingModeEnabled: \(isStreamingModeEnabled)")
                    StreamingLogger.shared.log("  isLivePreviewEnabled: \(isLivePreviewEnabled)")
                    StreamingLogger.shared.log("  isPreviewVisible: \(isPreviewVisible)")
                }
                .onDisappear {
                    StreamingLogger.shared.log("🖼️ NotchRecorderView DISAPPEARED")
                }
            }
        }
    }
}



 
