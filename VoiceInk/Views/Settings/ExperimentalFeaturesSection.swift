import SwiftUI

struct ExperimentalFeaturesSection: View {
    @AppStorage("isExperimentalFeaturesEnabled") private var isExperimentalFeaturesEnabled = false
    @AppStorage("StreamingModeEnabled") private var isStreamingModeEnabled = false
    @ObservedObject private var playbackController = PlaybackController.shared

    // Voice commands state
    @State private var voiceCommands: [WhisperState.VoiceCommand] = []
    @State private var newPhrase: String = ""
    @State private var newAction: WhisperState.VoiceCommandAction = .stopPasteAndEnter

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
                        if !newValue {
                            playbackController.isPauseMediaEnabled = false
                            isStreamingModeEnabled = false
                        }
                    }
            }

            Divider()
                .padding(.vertical, 4)

            if isExperimentalFeaturesEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $playbackController.isPauseMediaEnabled) {
                        Text("Pause Media during recording")
                    }
                    .toggleStyle(.switch)
                    .help("Automatically pause active media playback during recordings and resume afterward.")

                    Toggle(isOn: $isStreamingModeEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Real-Time Streaming Preview")
                            Text("Show live transcription bubbles as you speak")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .help("Shows real-time transcription preview while recording. Requires a local Whisper model.")

                    // Voice Commands section (only when streaming enabled)
                    if isStreamingModeEnabled {
                        Divider()
                            .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice Commands")
                                .font(.headline)
                            Text("Say these phrases to control recording with your voice")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // List of existing commands
                            ForEach(voiceCommands) { command in
                                HStack {
                                    Text("\"\(command.phrase)\"")
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text(command.action.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Button(action: { deleteCommand(command) }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.vertical, 4)
                            }

                            // Add new command
                            HStack {
                                TextField("New phrase...", text: $newPhrase)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(maxWidth: 200)

                                Picker("", selection: $newAction) {
                                    ForEach(WhisperState.VoiceCommandAction.allCases, id: \.self) { action in
                                        Text(action.displayName).tag(action)
                                    }
                                }
                                .frame(width: 150)

                                Button("Add") {
                                    addCommand()
                                }
                                .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            // Reset to defaults button
                            Button("Reset to Defaults") {
                                resetToDefaults()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExperimentalFeaturesEnabled)
        .animation(.easeInOut(duration: 0.2), value: isStreamingModeEnabled)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false, useAccentGradientWhenSelected: true))
        .onAppear {
            loadVoiceCommands()
        }
    }

    // MARK: - Voice Command Management

    private func loadVoiceCommands() {
        if let data = UserDefaults.standard.data(forKey: "VoiceCommands"),
           let commands = try? JSONDecoder().decode([WhisperState.VoiceCommand].self, from: data) {
            voiceCommands = commands
        } else {
            voiceCommands = WhisperState.defaultVoiceCommands
        }
    }

    private func saveVoiceCommands() {
        if let data = try? JSONEncoder().encode(voiceCommands) {
            UserDefaults.standard.set(data, forKey: "VoiceCommands")
        }
    }

    private func addCommand() {
        let phrase = newPhrase.trimmingCharacters(in: .whitespaces).lowercased()
        guard !phrase.isEmpty else { return }

        // Check for duplicates
        guard !voiceCommands.contains(where: { $0.phrase.lowercased() == phrase }) else { return }

        let command = WhisperState.VoiceCommand(phrase: phrase, action: newAction)
        voiceCommands.append(command)
        saveVoiceCommands()
        newPhrase = ""
    }

    private func deleteCommand(_ command: WhisperState.VoiceCommand) {
        voiceCommands.removeAll { $0.id == command.id }
        saveVoiceCommands()
    }

    private func resetToDefaults() {
        voiceCommands = WhisperState.defaultVoiceCommands
        saveVoiceCommands()
    }
}


