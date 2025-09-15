import SwiftUI

struct NotchRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @State private var isHovering = false
    @State private var showPowerModePopover = false
    @State private var showEnhancementPromptPopover = false
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @Environment(\.modelContext) private var modelContext
    
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
    
    private var leftSection: some View {
        HStack(spacing: 8) {
            RecorderPromptButton(
                showPopover: $showEnhancementPromptPopover,
                buttonSize: 22,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
            
            RecorderPowerModeButton(
                showPopover: $showPowerModePopover,
                buttonSize: 22,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
            
            Spacer()
        }
        .frame(width: 84)
        .padding(.leading, 16)
    }
    
    private var centerSection: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: exactNotchWidth)
            .contentShape(Rectangle())
    }
    
    private var rightSection: some View {
        HStack(spacing: 8) {
            Spacer()
            
            // Timer display
            if whisperState.recordingState == .recording {
                Text(formatTime(recordingDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 35)
            }
            
            // Paste button
            Button(action: {
                LastTranscriptionService.pasteLastTranscription(from: modelContext)
            }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Paste last transcription")
            
            statusDisplay
        }
        .frame(width: 150) // Increased width to accommodate new buttons
        .padding(.trailing, 16)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var statusDisplay: some View {
        RecorderStatusDisplay(
            currentState: whisperState.recordingState,
            audioMeter: recorder.audioMeter,
            menuBarHeight: menuBarHeight
        )
        .frame(width: 70)
        .padding(.trailing, 8)
    }
    
    var body: some View {
        Group {
            if windowManager.isVisible {
                HStack(spacing: 0) {
                    leftSection
                    centerSection
                    rightSection
                }
                .frame(height: menuBarHeight)
                .frame(maxWidth: windowManager.isVisible ? .infinity : 0)
                .background(
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
                    }
                )
                .mask {
                    NotchShape(cornerRadius: 10)
                }
                .clipped()
                .onHover { hovering in
                    isHovering = hovering
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
            }
        }
    }
}



 
