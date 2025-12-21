import Foundation
import SwiftUI

@MainActor
extension WhisperState {
    // Loads the default transcription model from UserDefaults
    // If no model is saved, defaults to Parakeet V3 (auto-downloads if needed)
    func loadCurrentTranscriptionModel() {
        // If user has a saved model preference, use it
        if let savedModelName = UserDefaults.standard.string(forKey: "CurrentTranscriptionModel"),
           let savedModel = allAvailableModels.first(where: { $0.name == savedModelName }) {
            currentTranscriptionModel = savedModel
            return
        }

        // No saved model - default to Parakeet V3
        // If Parakeet is already downloaded, set it as default immediately
        if isParakeetModelDownloaded {
            if let parakeetModel = allAvailableModels.first(where: { $0.name == "parakeet-tdt-0.6b" }) {
                setDefaultTranscriptionModel(parakeetModel)
                StreamingLogger.shared.log("🦜 Auto-selected Parakeet V3 as default (already downloaded)")
            }
            return
        }

        // Parakeet not downloaded - auto-start download for new users
        Task {
            StreamingLogger.shared.log("🦜 Auto-downloading Parakeet V3 for new user...")
            await downloadParakeetModel()

            // After download completes, set as default
            if isParakeetModelDownloaded {
                if let parakeetModel = allAvailableModels.first(where: { $0.name == "parakeet-tdt-0.6b" }) {
                    setDefaultTranscriptionModel(parakeetModel)
                    StreamingLogger.shared.log("🦜 Parakeet V3 download complete - set as default")
                }
            }
        }
    }

    // Function to set any transcription model as default
    func setDefaultTranscriptionModel(_ model: any TranscriptionModel) {
        self.currentTranscriptionModel = model
        UserDefaults.standard.set(model.name, forKey: "CurrentTranscriptionModel")
        
        // For cloud models, clear the old loadedLocalModel
        if model.provider != .local {
            self.loadedLocalModel = nil
        }
        
        // Enable transcription for cloud models immediately since they don't need loading
        if model.provider != .local {
            self.isModelLoaded = true
        }
        // Post notification about the model change
        NotificationCenter.default.post(name: .didChangeModel, object: nil, userInfo: ["modelName": model.name])
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }
    
    func refreshAllAvailableModels() {
        let currentModelName = currentTranscriptionModel?.name
        var models = PredefinedModels.models

        // Append dynamically discovered local models (imported .bin files) with minimal metadata
        for whisperModel in availableModels {
            if !models.contains(where: { $0.name == whisperModel.name }) {
                let importedModel = ImportedLocalModel(fileBaseName: whisperModel.name)
                models.append(importedModel)
            }
        }

        allAvailableModels = models

        // Preserve current selection by name (IDs may change for dynamic models)
        if let currentName = currentModelName,
           let updatedModel = allAvailableModels.first(where: { $0.name == currentName }) {
            setDefaultTranscriptionModel(updatedModel)
        }
    }
} 