import Foundation
import CoreML

/// Manages ML cleanup models (filler_remover, repetition_remover)
/// Handles downloading, storage, and loading from Application Support
@MainActor
class CleanupModelManager: ObservableObject {
    static let shared = CleanupModelManager()

    // MARK: - Published State

    @Published var fillerModelStatus: ModelStatus = .checking
    @Published var repetitionModelStatus: ModelStatus = .checking
    @Published var downloadProgress: Double = 0

    enum ModelStatus: Equatable {
        case checking
        case notDownloaded
        case downloading
        case downloaded
        case error(String)

        var isReady: Bool {
            self == .downloaded
        }
    }

    // MARK: - Model URLs

    private let modelsDirectory: URL
    private let fillerModelName = "filler_remover"
    private let repetitionModelName = "repetition_remover"
    private let vocabFileName = "vocab.txt"

    // GitHub Release URLs (update these when uploading models)
    private let baseDownloadURL = "https://github.com/joshua-mullet-town/whisper-village/releases/download/models-v1"

    // MARK: - Loaded Models

    private(set) var fillerModel: MLModel?
    private(set) var repetitionModel: MLModel?
    private(set) var vocabPath: String?

    // MARK: - Initialization

    private init() {
        // Set up models directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("Whisper Village/Models")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // Check model status on init
        Task {
            await checkAndLoadModels()
        }
    }

    // MARK: - Public API

    /// Check if models exist and load them
    func checkAndLoadModels() async {
        // First check if we need to migrate from bundle
        await migrateFromBundleIfNeeded()

        // Check each model
        fillerModelStatus = await checkModelStatus(name: fillerModelName)
        repetitionModelStatus = await checkModelStatus(name: repetitionModelName)

        // Load models if available
        if fillerModelStatus == .downloaded {
            fillerModel = await loadModel(name: fillerModelName)
        }
        if repetitionModelStatus == .downloaded {
            repetitionModel = await loadModel(name: repetitionModelName)
        }

        // Check vocab
        let vocabURL = modelsDirectory.appendingPathComponent(vocabFileName)
        if FileManager.default.fileExists(atPath: vocabURL.path) {
            vocabPath = vocabURL.path
        } else if let bundleVocab = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
            // Vocab is small, can stay in bundle
            vocabPath = bundleVocab.path
        }
    }

    /// Download all models
    func downloadModels() async {
        fillerModelStatus = .downloading
        repetitionModelStatus = .downloading
        downloadProgress = 0

        // Download filler model
        let fillerSuccess = await downloadModel(name: fillerModelName)
        fillerModelStatus = fillerSuccess ? .downloaded : .error("Download failed")
        downloadProgress = 0.33

        // Download repetition model
        let repetitionSuccess = await downloadModel(name: repetitionModelName)
        repetitionModelStatus = repetitionSuccess ? .downloaded : .error("Download failed")
        downloadProgress = 0.66

        // Download vocab if not in bundle
        if vocabPath == nil {
            _ = await downloadVocab()
        }
        downloadProgress = 1.0

        // Load models
        if fillerModelStatus == .downloaded {
            fillerModel = await loadModel(name: fillerModelName)
        }
        if repetitionModelStatus == .downloaded {
            repetitionModel = await loadModel(name: repetitionModelName)
        }

        // Reset progress after a delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        downloadProgress = 0
    }

    /// Check if models are ready to use
    var modelsReady: Bool {
        fillerModelStatus == .downloaded && repetitionModelStatus == .downloaded && vocabPath != nil
    }

    /// Total size of models to download
    var downloadSizeDescription: String {
        "~250 MB"
    }

    // MARK: - Private Methods

    private func checkModelStatus(name: String) async -> ModelStatus {
        let compiledURL = modelsDirectory.appendingPathComponent("\(name).mlmodelc")
        let packageURL = modelsDirectory.appendingPathComponent("\(name).mlpackage")

        if FileManager.default.fileExists(atPath: compiledURL.path) ||
           FileManager.default.fileExists(atPath: packageURL.path) {
            return .downloaded
        }
        return .notDownloaded
    }

    private func loadModel(name: String) async -> MLModel? {
        let compiledURL = modelsDirectory.appendingPathComponent("\(name).mlmodelc")
        let packageURL = modelsDirectory.appendingPathComponent("\(name).mlpackage")

        do {
            // Prefer compiled model
            if FileManager.default.fileExists(atPath: compiledURL.path) {
                return try MLModel(contentsOf: compiledURL)
            }

            // Fall back to package (will compile on first use)
            if FileManager.default.fileExists(atPath: packageURL.path) {
                // Compile the model
                let compiled = try await MLModel.compileModel(at: packageURL)
                // Move to permanent location
                try? FileManager.default.removeItem(at: compiledURL)
                try FileManager.default.moveItem(at: compiled, to: compiledURL)
                return try MLModel(contentsOf: compiledURL)
            }

            print("[CleanupModelManager] Model not found: \(name)")
            return nil
        } catch {
            print("[CleanupModelManager] Failed to load \(name): \(error)")
            return nil
        }
    }

    private func downloadModel(name: String) async -> Bool {
        let url = URL(string: "\(baseDownloadURL)/\(name).mlpackage.zip")!
        let destinationZip = modelsDirectory.appendingPathComponent("\(name).mlpackage.zip")
        let destinationPackage = modelsDirectory.appendingPathComponent("\(name).mlpackage")

        do {
            // Download
            let (tempURL, _) = try await URLSession.shared.download(from: url)

            // Move to destination
            try? FileManager.default.removeItem(at: destinationZip)
            try FileManager.default.moveItem(at: tempURL, to: destinationZip)

            // Unzip
            try? FileManager.default.removeItem(at: destinationPackage)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", destinationZip.path, "-d", modelsDirectory.path]
            try process.run()
            process.waitUntilExit()

            // Clean up zip
            try? FileManager.default.removeItem(at: destinationZip)

            return process.terminationStatus == 0
        } catch {
            print("[CleanupModelManager] Download failed for \(name): \(error)")
            return false
        }
    }

    private func downloadVocab() async -> Bool {
        let url = URL(string: "\(baseDownloadURL)/\(vocabFileName)")!
        let destination = modelsDirectory.appendingPathComponent(vocabFileName)

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            vocabPath = destination.path
            return true
        } catch {
            print("[CleanupModelManager] Vocab download failed: \(error)")
            return false
        }
    }

    /// Migrate models from app bundle to Application Support (for existing users)
    private func migrateFromBundleIfNeeded() async {
        let fm = FileManager.default

        // Check if already migrated
        let migrationMarker = modelsDirectory.appendingPathComponent(".migrated")
        if fm.fileExists(atPath: migrationMarker.path) {
            return
        }

        // Check if models exist in bundle
        guard let bundleFillerURL = Bundle.main.url(forResource: fillerModelName, withExtension: "mlmodelc"),
              let bundleRepetitionURL = Bundle.main.url(forResource: repetitionModelName, withExtension: "mlmodelc") else {
            // No bundle models - might be new install with lightweight app
            return
        }

        print("[CleanupModelManager] Migrating models from bundle to Application Support...")

        do {
            // Copy filler model
            let destFiller = modelsDirectory.appendingPathComponent("\(fillerModelName).mlmodelc")
            if !fm.fileExists(atPath: destFiller.path) {
                try fm.copyItem(at: bundleFillerURL, to: destFiller)
            }

            // Copy repetition model
            let destRepetition = modelsDirectory.appendingPathComponent("\(repetitionModelName).mlmodelc")
            if !fm.fileExists(atPath: destRepetition.path) {
                try fm.copyItem(at: bundleRepetitionURL, to: destRepetition)
            }

            // Mark as migrated
            fm.createFile(atPath: migrationMarker.path, contents: nil)
            print("[CleanupModelManager] Migration complete")
        } catch {
            print("[CleanupModelManager] Migration failed: \(error)")
        }
    }
}
