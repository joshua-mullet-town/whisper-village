import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @ObservedObject var streamingRecorder: StreamingRecorder
    @EnvironmentObject var windowManager: NotchWindowManager
    // WorktreeManager, SpaceTabManager, ClaudeSessionManager removed
    @State private var isHovering = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var formatModeDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isPreviewVisible = true
    @State private var retryPulse = false
    @State private var shimmerPhase: CGFloat = 0
    @State private var wasInFormatMode = false
    @State private var showingHistory = false
    @State private var showingSpaceTabs = false
    @State private var isSummaryHidden = false
    @AppStorage("SessionBarHidden") private var isSessionBarHidden = false

    // Settings for eyeball button behavior
    @AppStorage("StreamingModeEnabled") private var isStreamingModeEnabled = false
    @AppStorage("LivePreviewEnabled") private var isLivePreviewEnabled = true
    @AppStorage("NotchAlwaysVisible") private var isAlwaysVisible = false
    // Cloud API keys removed — local only
    @AppStorage("selectedHotkey1") private var selectedHotkey1Raw = "rightOption"

    /// Whether this is the Dev build (bundle ID ends with .debug)
    private var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".debug") ?? false
    }

    /// Current hotkey symbol for display
    private var hotkeySymbol: String {
        HotkeyManager.HotkeyOption(rawValue: selectedHotkey1Raw)?.symbol ?? "⌥"
    }

    /// Format mode and command mode removed
    private var isInFormatMode: Bool { false }
    private var isInCommandMode: Bool { false }

    /// Timer to display
    private var displayDuration: TimeInterval {
        recordingDuration
    }


    /// Whether we're in idle state (always visible but not recording)
    private var isIdleState: Bool {
        isAlwaysVisible && whisperState.recordingState == .idle
    }

    /// Check if we're in error state
    private var isInErrorState: Bool {
        if case .error = whisperState.recordingState {
            return true
        }
        return false
    }

    /// Get error message if in error state
    private var errorMessage: String? {
        if case .error(let message) = whisperState.recordingState {
            return message
        }
        return nil
    }
    
    private var menuBarHeight: CGFloat {
        if let screen = NSScreen.main {
            if screen.safeAreaInsets.top > 0 {
                // Extend slightly below the notch to fill the full header
                return screen.safeAreaInsets.top + 4
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
    
    /// Width for the left section — all controls live here
    private var leftSectionWidth: CGFloat {
        if isIdleState {
            return 50  // History icon when idle
        }
        return 130  // Compact: start/stop + hotkey + timer + peek + history
    }

    /// Total width — just left section + notch gap (no right side)
    private var totalBarWidth: CGFloat {
        exactNotchWidth + leftSectionWidth
    }

    /// Whether we're in paused state
    private var isPaused: Bool {
        whisperState.recordingState == .paused
    }

    private var leftSection: some View {
        HStack(spacing: 5) {
            // 1. Start/stop (pause/play + stop stacked)
            if whisperState.recordingState == .recording || isPaused {
                VStack(spacing: 1) {
                    Button {
                        Task { @MainActor in
                            if isPaused {
                                await whisperState.resumeRecording()
                            } else {
                                await whisperState.pauseRecording()
                            }
                        }
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 11)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isPaused ? "Resume" : "Pause")

                    Button {
                        Task { @MainActor in
                            await whisperState.cancelRecording()
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 18, height: 11)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Stop (discard)")
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // 2. Hotkey indicator
            if !isIdleState && !hotkeySymbol.isEmpty {
                Text(hotkeySymbol)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(minWidth: 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // 3. Timer
            if whisperState.recordingState == .recording || isPaused {
                Text(formatTime(displayDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isPaused ? .white.opacity(0.6) : .white)
                    .frame(width: 35, alignment: .trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // 4. Peek button
            if isStreamingModeEnabled && !isIdleState && (whisperState.recordingState == .recording || isPaused) && !(isLivePreviewEnabled && livePreviewStyle == "box") {
                NotchIconButton(
                    icon: "doc.text.magnifyingglass",
                    color: .white.opacity(0.9),
                    tooltip: "Show full transcription"
                ) {
                    Task { @MainActor in
                        await whisperState.peekTranscription()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // 5. History button — always visible
            NotchIconButton(
                icon: "clock.arrow.circlepath",
                color: .white.opacity(0.7),
                tooltip: "Transcription History"
            ) {
                showingHistory.toggle()
            }
            .popover(isPresented: $showingHistory, arrowEdge: .top) {
                TranscriptionHistoryDropdown()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
        .padding(.leading, 6)
        .frame(width: leftSectionWidth)
        .clipped()
    }

    private var cancelTooltip: String {
        if isInCommandMode { return "Cancel command" }
        if isInFormatMode { return "Cancel formatting" }
        return "Cancel recording"
    }

    private var centerSection: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: exactNotchWidth)
            .contentShape(Rectangle())
    }
    
    // MARK: - Error UI Sections

    private var errorLeftSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.yellow)

            Text(errorMessage ?? "Error")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.leading, 12)
        .frame(width: leftSectionWidth)
    }

    private var errorRightSection: some View {
        HStack(spacing: 12) {
            Spacer()

            Button(action: {
                Task { @MainActor in
                    await whisperState.retryAfterError()
                }
            }) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .scaleEffect(retryPulse ? 1.15 : 1.0)
                    .opacity(retryPulse ? 1.0 : 0.85)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Retry")
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    retryPulse = true
                }
            }
            .onDisappear {
                retryPulse = false
            }

            Button(action: {
                whisperState.dismissError()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Dismiss")
        }
        .padding(.trailing, 10)
        .frame(width: leftSectionWidth)
    }

    private var rightSection: some View {
        EmptyView()
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
        if isInErrorState {
            // Error state: red background
            LinearGradient(
                colors: [
                    Color(red: 0.8, green: 0.2, blue: 0.2).opacity(0.9),
                    Color(red: 0.6, green: 0.1, blue: 0.1).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if whisperState.recordingState == .paused {
            // Paused state: muted orange, no audio-reactive animation
            LinearGradient(
                colors: [
                    Color(red: 0.7, green: 0.35, blue: 0.1).opacity(0.6),
                    Color(red: 0.6, green: 0.2, blue: 0.1).opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isIdleState {
            // Idle state: very subtle, almost invisible gray
            // Brightens on hover to show interactivity
            Color.gray.opacity(isHovering ? 0.35 : 0.15)
        } else if whisperState.recordingState == .transcribing {
            // Transcribing state: animated shimmer loading effect
            ZStack {
                // Base gradient - purple/blue processing colors
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.3, blue: 0.7).opacity(0.7),
                        Color(red: 0.3, green: 0.4, blue: 0.8).opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Shimmer overlay - sweeping highlight
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.3),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: shimmerPhase * geometry.size.width * 1.5 - geometry.size.width * 0.25)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1
                }
            }
            .onDisappear {
                shimmerPhase = 0
            }
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
    
    /// Live preview style: "ticker" (horizontal scrolling) or "box" (draggable floating box)
    @AppStorage("LivePreviewStyle") private var livePreviewStyle = "box"

    /// Whether to show live transcription ticker (streaming mode + live preview enabled + ticker mode)
    private var shouldShowTicker: Bool {
        isStreamingModeEnabled && isLivePreviewEnabled && !isIdleState && livePreviewStyle == "ticker"
    }

    var body: some View {
        Group {
            if windowManager.isVisible {
                // Outer container ignores mouse - only inner elements with explicit contentShape receive clicks
                VStack(alignment: .center, spacing: 0) {
                    // Main notch bar - aligned to top of window
                    HStack(spacing: 0) {
                        if isInErrorState {
                            errorLeftSection
                            centerSection
                            errorRightSection
                        } else {
                            leftSection
                            centerSection
                            rightSection
                        }
                    }
                    .frame(width: totalBarWidth, height: menuBarHeight)
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
                    .overlay(alignment: .topLeading) {
                        // DEV badge - small corner indicator for dev builds
                        if isDevBuild {
                            Text("DEV")
                                .font(.system(size: 7, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.yellow)
                                )
                                .offset(x: 2, y: 2)
                        }
                    }
                    .clipped()
                    .contentShape(NotchShape(cornerRadius: 10))
                    .clickableRegion(id: "notchBar")
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
                    .animation(.easeInOut(duration: 0.4), value: isIdleState)
                    .animation(.easeInOut(duration: 0.2), value: isSessionBarHidden)
                    .frame(maxWidth: .infinity, alignment: .trailing)  // Align bar to right edge (notch gap meets physical notch)

                    // Live transcription ticker below notch
                    if shouldShowTicker && isPreviewVisible {
                        NotchTranscriptionTicker(
                            text: whisperState.interimTranscription,
                            isRecording: whisperState.recordingState == .recording
                        )
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(windowManager.isVisible ? 1 : 0)
                .onChange(of: whisperState.recordingState) { oldState, newState in
                    if newState == .recording {
                        // Only reset duration on fresh start (not when resuming from pause)
                        if oldState != .paused {
                            recordingDuration = 0
                        }
                        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                            recordingDuration += 0.1
                        }
                    } else if newState == .paused {
                        // Freeze timer: stop incrementing but preserve duration value
                        timer?.invalidate()
                        timer = nil
                    } else {
                        timer?.invalidate()
                        timer = nil
                        recordingDuration = 0
                    }
                }
                // Format mode timer removed
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

// MARK: - Notch Icon Button

/// A styled button for the notch UI with hover effects and pointer cursor
private struct NotchIconButton: View {
    let icon: String
    let color: Color
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovered ? color : color.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.15) : Color.clear)
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// Worktree panels removed

