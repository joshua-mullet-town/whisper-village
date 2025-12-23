import SwiftUI

/// Simple transcription model selector for Settings
/// Replaces the complex Voice Engine page with a dropdown
struct TranscriptionModelSection: View {
    @EnvironmentObject private var whisperState: WhisperState

    // Check if any download is in progress
    private var activeDownload: (name: String, progress: Double)? {
        for (key, value) in whisperState.downloadProgress {
            if value > 0 && value < 1.0 {
                // Clean up the key to get a nice name
                let displayName = key.replacingOccurrences(of: "_main", with: "")
                    .replacingOccurrences(of: "_coreml", with: "")
                return (displayName, value)
            }
        }
        return nil
    }

    var body: some View {
        SettingsSection(
            icon: "waveform",
            title: "Transcription",
            subtitle: "Voice-to-text engine"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                CurrentModelRow(whisperState: whisperState)

                // Download progress if active
                if let download = activeDownload {
                    DownloadProgressRow(modelName: download.name, progress: download.progress)
                }

                // Language selection (only show if model supports multiple languages)
                if whisperState.currentTranscriptionModel?.isMultilingualModel == true {
                    Divider()
                    LanguageRow(whisperState: whisperState)
                }
            }
        }
    }
}

// MARK: - Current Model Row

private struct CurrentModelRow: View {
    @ObservedObject var whisperState: WhisperState

    private var localModels: [any TranscriptionModel] {
        whisperState.allAvailableModels.filter { model in
            model.provider == .local || model.provider == .nativeApple || model.provider == .parakeet
        }.sorted { model1, model2 in
            if model1.provider == .parakeet { return true }
            if model2.provider == .parakeet { return false }
            return model1.displayName < model2.displayName
        }
    }

    private var downloadedModels: [any TranscriptionModel] {
        localModels.filter { model in
            whisperState.availableModels.contains { $0.name == model.name }
        }
    }

    private var notDownloadedModels: [any TranscriptionModel] {
        localModels.filter { model in
            !whisperState.availableModels.contains { $0.name == model.name }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Circle()
                .fill(whisperState.currentTranscriptionModel?.provider == .parakeet ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(whisperState.currentTranscriptionModel?.displayName ?? "No model selected")
                    .font(.system(size: 14, weight: .medium))

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }

            Spacer()

            ModelPickerMenu(
                whisperState: whisperState,
                downloadedModels: downloadedModels,
                notDownloadedModels: notDownloadedModels
            )
        }
    }

    private var statusText: String {
        if whisperState.currentTranscriptionModel?.provider == .parakeet {
            return "Recommended - Fast & accurate local transcription"
        } else if whisperState.currentTranscriptionModel == nil {
            return "Downloading default model..."
        } else {
            return "For best results, consider Parakeet V3"
        }
    }

    private var statusColor: Color {
        if whisperState.currentTranscriptionModel?.provider == .parakeet {
            return .secondary
        } else if whisperState.currentTranscriptionModel == nil {
            return .orange
        } else {
            return .orange
        }
    }
}

// MARK: - Model Picker Menu

private struct ModelPickerMenu: View {
    @ObservedObject var whisperState: WhisperState
    let downloadedModels: [any TranscriptionModel]
    let notDownloadedModels: [any TranscriptionModel]

    var body: some View {
        Menu {
            if !downloadedModels.isEmpty {
                Section("Downloaded") {
                    ForEach(downloadedModels, id: \.id) { model in
                        DownloadedModelButton(model: model, whisperState: whisperState)
                    }
                }
            }

            if !notDownloadedModels.isEmpty {
                Section("Available to Download") {
                    ForEach(notDownloadedModels, id: \.id) { model in
                        DownloadModelButton(model: model, whisperState: whisperState)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Change")
                    .font(.system(size: 12))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Model Buttons

private struct DownloadedModelButton: View {
    let model: any TranscriptionModel
    @ObservedObject var whisperState: WhisperState

    var body: some View {
        Button(action: {
            Task {
                await whisperState.setDefaultTranscriptionModel(model)
            }
        }) {
            HStack {
                Text(model.displayName)
                if whisperState.currentTranscriptionModel?.name == model.name {
                    Image(systemName: "checkmark")
                }
                if model.provider == .parakeet {
                    Text("Recommended")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }
}

private struct DownloadModelButton: View {
    let model: any TranscriptionModel
    @ObservedObject var whisperState: WhisperState

    var body: some View {
        Button(action: {
            if let localModel = model as? LocalModel {
                Task {
                    await whisperState.downloadModel(localModel)
                }
            }
        }) {
            HStack {
                Text(model.displayName)
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Download Progress Row

private struct DownloadProgressRow: View {
    let modelName: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text("Downloading \(modelName)... \(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Language Row

private struct LanguageRow: View {
    @ObservedObject var whisperState: WhisperState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Text("Language")
                .font(.system(size: 13, weight: .medium))

            Spacer()

            LanguageSelectionView(
                whisperState: whisperState,
                displayMode: .menuItem,
                whisperPrompt: whisperState.whisperPrompt
            )
        }
    }
}
