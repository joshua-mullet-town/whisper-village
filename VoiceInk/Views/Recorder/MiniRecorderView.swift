import SwiftUI
import SwiftData

struct MiniRecorderView: View {
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @Environment(\.modelContext) private var modelContext
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    
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
        HStack(spacing: 4) { // Even tighter spacing
            // Cancel button
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
            .padding(.leading, 6)
            
            // Constrained visualizer zone - no more infinite width!
            statusView
                .frame(width: 90) // Reduced to make room for timer
            
            // Timer display - always reserve space to prevent layout shift
            Text(whisperState.recordingState == .recording ? formatTime(recordingDuration) : "")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 35) // Fixed width so layout doesn't shift
            
            // Just a small spacer for padding
            Spacer()
                .frame(width: 8)
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
                recorderCapsule
                    .frame(maxWidth: 200) // Actually constrain the overall width!
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


