import SwiftUI

struct ExperimentalFeaturesSection: View {
    @AppStorage("isExperimentalFeaturesEnabled") private var isExperimentalFeaturesEnabled = false
    @AppStorage("StreamingModeEnabled") private var isStreamingModeEnabled = false
    @ObservedObject private var playbackController = PlaybackController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "flask")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Experimental")
                        .font(.headline)
                    Text("Beta features that may be unstable")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isExperimentalFeaturesEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isExperimentalFeaturesEnabled) { _, newValue in
                        if newValue {
                            isStreamingModeEnabled = true
                        } else {
                            playbackController.isPauseMediaEnabled = false
                            isStreamingModeEnabled = false
                        }
                    }
            }

            if isExperimentalFeaturesEnabled {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $playbackController.isPauseMediaEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pause Media During Recording")
                            Text("Automatically pause music/video and resume after")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    // Debug Tools section (Dev only)
                    #if DEBUG
                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug Tools")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Developer testing tools")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button(action: {
                                simulateTranscriptionError()
                            }) {
                                Label("Simulate Error", systemImage: "exclamationmark.triangle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            Button(action: {
                                simulateCrash()
                            }) {
                                Label("Simulate Crash", systemImage: "xmark.octagon")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    #endif
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExperimentalFeaturesEnabled)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false, useAccentGradientWhenSelected: true))
        .onAppear {
            if isExperimentalFeaturesEnabled {
                isStreamingModeEnabled = true
            }
        }
    }

    #if DEBUG
    private func simulateTranscriptionError() {
        NotificationCenter.default.post(
            name: NSNotification.Name("SimulateTranscriptionError"),
            object: nil,
            userInfo: [
                "error": "Simulated transcription error for testing",
                "context": "Debug button pressed in settings"
            ]
        )
        StreamingLogger.shared.log("🧪 DEBUG: Simulated transcription error triggered")
    }

    private func simulateCrash() {
        StreamingLogger.shared.log("🧪 DEBUG: Simulating crash...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let crash: String? = nil
            print(crash!)
        }
    }
    #endif
}
