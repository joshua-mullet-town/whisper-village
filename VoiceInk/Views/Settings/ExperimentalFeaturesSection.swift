import SwiftUI

struct ExperimentalFeaturesSection: View {
    @AppStorage("isExperimentalFeaturesEnabled") private var isExperimentalFeaturesEnabled = false
    @AppStorage("StreamingModeEnabled") private var isStreamingModeEnabled = false
    @AppStorage("LivePreviewEnabled") private var isLivePreviewEnabled = true
    @ObservedObject private var playbackController = PlaybackController.shared

    // Jarvis settings
    @AppStorage("JarvisEnabled") private var isJarvisEnabled = true
    @AppStorage("JarvisWakeWord") private var jarvisWakeWord = "jarvis"
    @AppStorage("RecordingLingerMs") private var recordingLingerMs = 750
    @State private var ollamaStatus: String = "Checking..."

    // LLM Correction settings
    @AppStorage("LLMCorrectionEnabled") private var isLLMCorrectionEnabled = false
    @State private var correctionOllamaStatus: String = "Checking..."

    // ML Cleanup settings (native CoreML)
    @AppStorage("IsMLCleanupEnabled") private var isMLCleanupEnabled = false
    @AppStorage("MLCleanupFillerEnabled") private var isFillerEnabled = true
    @AppStorage("MLCleanupRepetitionEnabled") private var isRepetitionEnabled = true

    // Inline placeholder setting
    @AppStorage("InlinePlaceholderEnabled") private var isInlinePlaceholderEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "flask")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Experimental Features")
                        .font(.headline)
                    Text("Experimental features that might be unstable & bit buggy.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("Experimental Features", isOn: $isExperimentalFeaturesEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isExperimentalFeaturesEnabled) { _, newValue in
                        if newValue {
                            // Auto-enable streaming mode when experimental features is on
                            isStreamingModeEnabled = true
                        } else {
                            playbackController.isPauseMediaEnabled = false
                            isStreamingModeEnabled = false
                        }
                    }
            }

            Divider()
                .padding(.vertical, 4)

            if isExperimentalFeaturesEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    // Basic toggles
                    Toggle(isOn: $playbackController.isPauseMediaEnabled) {
                        Text("Pause Media during recording")
                    }
                    .toggleStyle(.switch)
                    .help("Automatically pause active media playback during recordings and resume afterward.")

                    Toggle(isOn: $isLivePreviewEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Preview")
                            Text(isLivePreviewEnabled
                                ? "Show transcription as you speak"
                                : "Transcribe only when recording stops")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .help("When ON: continuous transcription preview. When OFF: transcribe only on stop/peek.")

                    Toggle(isOn: $isInlinePlaceholderEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Inline Loading Placeholder")
                            Text("Show '\u{23F3} Transcribing...' in text field while processing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .help("Pastes a placeholder in the target text field during transcription for visual feedback.")

                    // Jarvis Commands section
                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Jarvis Commands")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $isJarvisEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        Text("Say your wake word followed by a command (e.g., \"Jarvis send it\")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isJarvisEnabled {
                            // Wake word field
                            HStack {
                                Text("Wake Word:")
                                    .frame(width: 80, alignment: .leading)
                                TextField("jarvis", text: $jarvisWakeWord)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: 150)
                                Spacer()
                            }
                            .padding(.top, 4)

                            // Ollama status
                            HStack {
                                Text("LLM Status:")
                                    .frame(width: 80, alignment: .leading)
                                Text(ollamaStatus)
                                    .font(.caption)
                                    .foregroundColor(ollamaStatus.contains("Ready") ? .green : .orange)
                                Button("Check") {
                                    checkOllamaStatus()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                Spacer()
                            }

                            Divider()
                                .padding(.vertical, 4)

                            // Trailing words capture (linger) setting
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trailing Words Capture")
                                    .font(.subheadline)
                                Text("Continue recording briefly after hotkey stop to capture final words")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    Text("Delay:")
                                        .frame(width: 80, alignment: .leading)
                                    Slider(
                                        value: Binding(
                                            get: { Double(recordingLingerMs) },
                                            set: { recordingLingerMs = Int($0) }
                                        ),
                                        in: 0...1500,
                                        step: 50
                                    )
                                    .frame(maxWidth: 200)
                                    Text("\(recordingLingerMs)ms")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                if recordingLingerMs == 0 {
                                    Text("Disabled - stops immediately on hotkey")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.vertical, 4)

                            Divider()
                                .padding(.vertical, 4)

                            // Built-in commands reference
                            Text("Built-in Commands:")
                                .font(.subheadline)
                                .padding(.top, 8)

                            VStack(alignment: .leading, spacing: 4) {
                                jarvisCommandRow("send it", "Paste + Enter, enter command mode")
                                jarvisCommandRow("stop", "Paste (no Enter), stop recording")
                                jarvisCommandRow("cancel", "Discard, stop recording")
                                jarvisCommandRow("pause", "Enter command mode, preserve buffer")
                                jarvisCommandRow("listen", "Resume transcribing")
                                jarvisCommandRow("go to [app]", "Focus app, enter command mode")
                                jarvisCommandRow("[nth] terminal tab", "Focus iTerm tab")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    // LLM Correction section
                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("LLM Correction")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $isLLMCorrectionEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        Text("Use local LLM to clean up transcriptions before pasting")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isLLMCorrectionEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Fixes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Filler words (um, uh, like, you know)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Self-corrections (\"2pm, no wait, 4pm\" → \"4pm\")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Stuttering and word duplications")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 8)

                            HStack {
                                Text("LLM Status:")
                                    .frame(width: 80, alignment: .leading)
                                Text(correctionOllamaStatus)
                                    .font(.caption)
                                    .foregroundColor(correctionOllamaStatus.contains("Ready") ? .green : .orange)
                                Button("Check") {
                                    checkCorrectionOllamaStatus()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                Spacer()
                            }
                            .padding(.top, 4)

                            Text("Requires: ollama serve + llama3.1:8b-instruct-q4_0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // ML Cleanup section
                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ML Cleanup (Beta)")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $isMLCleanupEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        Text("Use local ML models to clean up transcriptions")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isMLCleanupEnabled {
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: $isFillerEnabled) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Filler Removal")
                                            .font(.subheadline)
                                        Text("uh, um, er → removed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .toggleStyle(.switch)

                                Toggle(isOn: $isRepetitionEnabled) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Repetition Removal")
                                            .font(.subheadline)
                                        Text("I I I think → I think")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .toggleStyle(.switch)
                            }
                            .padding(.leading, 8)
                            .padding(.top, 4)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExperimentalFeaturesEnabled)
        .animation(.easeInOut(duration: 0.2), value: isLivePreviewEnabled)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false, useAccentGradientWhenSelected: true))
        .onAppear {
            // Auto-enable streaming mode if experimental features is on
            if isExperimentalFeaturesEnabled {
                isStreamingModeEnabled = true
            }
            if isJarvisEnabled {
                checkOllamaStatus()
            }
        }
    }

    // MARK: - Jarvis UI Helpers

    @ViewBuilder
    private func jarvisCommandRow(_ command: String, _ description: String) -> some View {
        HStack {
            Text("\"\(jarvisWakeWord) \(command)\"")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 200, alignment: .leading)
            Text(description)
        }
    }

    private func checkOllamaStatus() {
        ollamaStatus = "Checking..."
        Task {
            let isReady = await OllamaClient.shared.healthCheck()
            await MainActor.run {
                ollamaStatus = isReady ? "Ready (llama3.2:3b)" : "Not available - run 'ollama serve'"
            }
        }
    }

    private func checkCorrectionOllamaStatus() {
        correctionOllamaStatus = "Checking..."
        Task {
            let isReady = await LLMCorrectionService.shared.healthCheck()
            await MainActor.run {
                correctionOllamaStatus = isReady ? "Ready (llama3.1:8b)" : "Not available - run 'ollama serve'"
            }
        }
    }
}
