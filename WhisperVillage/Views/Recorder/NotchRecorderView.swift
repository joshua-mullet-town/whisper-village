import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @ObservedObject var streamingRecorder: StreamingRecorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @StateObject private var worktreeManager = WorktreeManager.shared
    @StateObject private var spaceTabManager = SpaceTabManager.shared
    @State private var isHovering = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var formatModeDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isPreviewVisible = true
    @State private var retryPulse = false
    @State private var shimmerPhase: CGFloat = 0
    @State private var wasInFormatMode = false
    @State private var showingWorktrees = false
    @State private var showingSpaceTabs = false

    // Settings for eyeball button behavior
    @AppStorage("StreamingModeEnabled") private var isStreamingModeEnabled = false
    @AppStorage("LivePreviewEnabled") private var isLivePreviewEnabled = true
    @AppStorage("NotchAlwaysVisible") private var isAlwaysVisible = false
    @AppStorage("OpenAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("selectedHotkey1") private var selectedHotkey1Raw = "rightOption"

    /// Whether this is the Dev build (bundle ID ends with .debug)
    private var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".debug") ?? false
    }

    /// Current hotkey symbol for display
    private var hotkeySymbol: String {
        HotkeyManager.HotkeyOption(rawValue: selectedHotkey1Raw)?.symbol ?? "⌥"
    }

    /// Whether we're in format mode (recording formatting instructions)
    private var isInFormatMode: Bool {
        whisperState.isWaitingForFormattingInstruction
    }

    /// Whether we're in Command Mode (recording a voice command)
    private var isInCommandMode: Bool {
        whisperState.isInCommandMode
    }

    /// Whether AI Polish button should be visible (only when NOT in format mode and NOT in command mode)
    private var showFormatButton: Bool {
        !openAIAPIKey.isEmpty && whisperState.recordingState == .recording && !isInFormatMode && !isInCommandMode
    }

    /// Timer to display - format mode timer or regular recording timer
    private var displayDuration: TimeInterval {
        isInFormatMode ? formatModeDuration : recordingDuration
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
    
    /// Total width for each side section (content + padding)
    /// Animates to 34 when idle (enough for icon + padding), 130 when active
    private var sectionWidth: CGFloat {
        if isIdleState {
            return 34  // Enough for 24px icon + padding to be fully visible
        }
        return 130  // Increased from 100 to accommodate worktree icon during recording
    }

    /// Total width of the entire notch bar
    /// Idle: just the notch width. Recording: notch + side sections
    private var totalBarWidth: CGFloat {
        exactNotchWidth + (sectionWidth * 2)
    }

    private var leftSection: some View {
        HStack(spacing: 4) {
            // Cancel button - hide when idle
            if !isIdleState {
                NotchIconButton(
                    icon: "xmark.circle.fill",
                    color: .white,
                    tooltip: cancelTooltip
                ) {
                    Task { @MainActor in
                        // Reset format mode state before dismissing
                        if isInFormatMode {
                            whisperState.isLLMFormattingMode = false
                            whisperState.isWaitingForFormattingInstruction = false
                            whisperState.llmFormattingContent = ""
                            NotificationManager.shared.dismissFormatContentBox()
                        }
                        // Reset Command Mode if active
                        if isInCommandMode {
                            whisperState.isInCommandMode = false
                        }
                        await whisperState.dismissMiniRecorder()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Spacer()
                .frame(width: 6)

            // Hotkey indicator - between X and worktree
            if !isIdleState && !hotkeySymbol.isEmpty {
                Text(hotkeySymbol)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(minWidth: 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            
            // Worktree button - always visible when worktrees exist
            if worktreeManager.hasWorktrees {
                NotchIconButton(
                    icon: "arrow.triangle.branch",
                    color: .white.opacity(0.8),
                    tooltip: "Worktrees (\(worktreeManager.totalCount))"
                ) {
                    showingWorktrees.toggle()
                }
                .popover(isPresented: $showingWorktrees, arrowEdge: .top) {
                    WorktreeNotchPanel(worktreeManager: worktreeManager)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Command Mode indicator
            if isInCommandMode {
                Image(systemName: "command")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Timer display
            if whisperState.recordingState == .recording {
                Text(formatTime(displayDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 35, alignment: .trailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Spacer()
        }
        .padding(.leading, 6)
        .frame(width: sectionWidth)
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
        .frame(width: sectionWidth)
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
        .frame(width: sectionWidth)
    }

    private var rightSection: some View {
        HStack(spacing: 4) {
            // Space-Tab link button - always visible, positioned closest to notch
            NotchIconButton(
                icon: spaceTabManager.hasBindingForCurrentSpace ? "link.circle.fill" : "link.circle",
                color: .white.opacity(0.8),
                tooltip: spaceTabManager.hasBindingForCurrentSpace ? "Space linked to iTerm tab" : "Link Space to iTerm tab"
            ) {
                showingSpaceTabs.toggle()
            }
            .popover(isPresented: $showingSpaceTabs, arrowEdge: .top) {
                SpaceTabPopover(spaceTabManager: spaceTabManager)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))

            Spacer()

            // Hide preview buttons when in format mode
            if !isInFormatMode {
                // Peek button - show full transcription toast
                // Show UNLESS (live preview is enabled AND style is box) - in that case it's redundant
                if isStreamingModeEnabled && !isIdleState && whisperState.recordingState == .recording && !(isLivePreviewEnabled && livePreviewStyle == "box") {
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

                // Eyeball button - toggle preview visibility (ticker or box depending on mode)
                if isStreamingModeEnabled && isLivePreviewEnabled && !isIdleState {
                    NotchIconButton(
                        icon: isPreviewVisible ? "eye.fill" : "eye.slash.fill",
                        color: .white.opacity(0.9),
                        tooltip: livePreviewStyle == "box" ? "Toggle live box" : "Toggle ticker"
                    ) {
                        if livePreviewStyle == "box" {
                            NotificationManager.shared.toggleLiveBox()
                        } else {
                            isPreviewVisible.toggle()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            // AI Polish button - always on right when API key is set and recording
            // Shows as "engaged" (highlighted) when in format mode
            if !openAIAPIKey.isEmpty && whisperState.recordingState == .recording {
                if isInFormatMode {
                    // Engaged state - highlighted wand
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.3))
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    // Normal state - clickable button
                    NotchIconButton(
                        icon: "wand.and.stars",
                        color: .white,
                        tooltip: "AI Polish"
                    ) {
                        Task { @MainActor in
                            await whisperState.triggerLLMFormatting()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

        }
        .padding(.trailing, 8)
        .frame(width: sectionWidth)
        .clipped()
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
        } else if isInCommandMode {
            // Command Mode: orange/yellow gradient to show voice navigation mode
            ZStack {
                // Base gradient - orange/yellow (matches Command Mode branding)
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.85),
                        Color(red: 0.9, green: 0.4, blue: 0.1).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Highlight gradient - extent and opacity animated with audio
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.9, blue: 0.5).opacity(highlightOpacity),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: highlightExtent
                )
            }
        } else if isInFormatMode {
            // Format mode: purple/blue gradient to show we're in AI formatting mode
            ZStack {
                // Base gradient - purple/blue (matches Format with AI branding)
                LinearGradient(
                    colors: [
                        Color(red: 0.5, green: 0.3, blue: 0.8).opacity(0.85),
                        Color(red: 0.3, green: 0.4, blue: 0.9).opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Highlight gradient - extent and opacity animated with audio
                LinearGradient(
                    colors: [
                        Color(red: 0.8, green: 0.7, blue: 1.0).opacity(highlightOpacity),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: highlightExtent
                )
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
                VStack(spacing: 4) {
                    // Main notch bar
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
                    .frame(maxWidth: .infinity)  // Center the shrinking bar within full-width parent

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
                        formatModeDuration = 0
                        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                            recordingDuration += 0.1
                            if isInFormatMode {
                                formatModeDuration += 0.1
                            }
                        }
                    } else {
                        timer?.invalidate()
                        timer = nil
                        recordingDuration = 0
                        formatModeDuration = 0
                    }
                }
                .onChange(of: whisperState.isWaitingForFormattingInstruction) { oldValue, newValue in
                    // When entering format mode, reset the format timer
                    if newValue && !oldValue {
                        formatModeDuration = 0
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

// MARK: - Worktree Notch Panel

/// Panel showing all worktrees grouped by project, displayed from the notch
struct WorktreeNotchPanel: View {
    @ObservedObject var worktreeManager: WorktreeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worktrees")
                .font(.headline)
                .padding(.bottom, 4)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(worktreeManager.worktrees.keys.sorted()), id: \.self) { project in
                        if let projectWorktrees = worktreeManager.worktrees[project] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                ForEach(projectWorktrees, id: \.branch) { worktree in
                                    WorktreeNotchRow(worktree: worktree, worktreeManager: worktreeManager)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding()
        .frame(width: 350)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
        .onAppear {
            Task {
                await worktreeManager.scan()
            }
        }
    }
}

/// Individual worktree row with copy path and delete actions
struct WorktreeNotchRow: View {
    let worktree: Worktree
    @ObservedObject var worktreeManager: WorktreeManager
    @State private var showingDeleteConfirm = false

    private var isDeleting: Bool {
        worktreeManager.isDeleting(worktree)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(worktree.branch)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(isDeleting ? .secondary : .primary)

                    if isDeleting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(worktree.path.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !isDeleting {
                HStack(spacing: 8) {
                    WorktreeActionButton(
                        icon: "doc.on.doc",
                        color: .primary,
                        tooltip: "Copy path"
                    ) {
                        worktreeManager.copyPath(worktree)
                    }

                    WorktreeActionButton(
                        icon: "chevron.left.forwardslash.chevron.right",
                        color: .blue,
                        tooltip: "Open in VS Code"
                    ) {
                        worktreeManager.openInVSCode(worktree)
                    }

                    WorktreeActionButton(
                        icon: "trash",
                        color: .red,
                        tooltip: "Delete worktree"
                    ) {
                        showingDeleteConfirm = true
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .opacity(isDeleting ? 0.6 : 1.0)
        .alert("Delete Worktree", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                worktreeManager.delete(worktree)
            }
        } message: {
            Text("Are you sure you want to delete the worktree for '\(worktree.branch)'? This will remove the directory and all its contents.")
        }
    }
}

/// Interactive button for worktree actions with hover and click feedback
struct WorktreeActionButton: View {
    let icon: String
    let color: Color
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isPressed ? color.opacity(0.6) : color)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovered)
                .animation(.easeInOut(duration: 0.05), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(_):
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .pressEvents(
            onPress: { isPressed = true },
            onRelease: { isPressed = false }
        )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        self
            .onTapGesture {
                // Tap gesture is handled by the button itself
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

