import Foundation
import os

/// Migration service for Whisper Village data paths
/// Handles legacy VoiceInk path migration (com.prakashjoshipax.VoiceInk → town.mullet.WhisperVillage)
class DataPathMigrationService {
    static let shared = DataPathMigrationService()

    private let logger = Logger(subsystem: "town.mullet.WhisperVillage", category: "DataMigration")

    private let oldBundleId = "com.prakashjoshipax.VoiceInk"
    private let newBundleId = "town.mullet.WhisperVillage"
    private let migrationKey = "WhisperVillageDataPathMigrationComplete"

    private init() {}

    /// Run migration on app launch (safe to call multiple times)
    func migrateIfNeeded() {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let oldPath = appSupport.appendingPathComponent(oldBundleId)
        let newPath = appSupport.appendingPathComponent(newBundleId)

        // No old data to migrate?
        guard fm.fileExists(atPath: oldPath.path) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.notice("No legacy VoiceInk data found, skipping migration")
            return
        }

        logger.notice("Found legacy data at \(oldPath.path), migrating...")

        do {
            // Create new directory if needed
            if !fm.fileExists(atPath: newPath.path) {
                try fm.createDirectory(at: newPath, withIntermediateDirectories: true)
            }

            // Move contents
            let contents = try fm.contentsOfDirectory(atPath: oldPath.path)
            for item in contents {
                let oldItem = oldPath.appendingPathComponent(item)
                let newItem = newPath.appendingPathComponent(item)

                // Skip if already exists
                if fm.fileExists(atPath: newItem.path) {
                    continue
                }

                try fm.moveItem(at: oldItem, to: newItem)
                logger.notice("Moved \(item)")
            }

            // Remove old directory if empty
            let remaining = try fm.contentsOfDirectory(atPath: oldPath.path)
            if remaining.isEmpty {
                try fm.removeItem(at: oldPath)
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.notice("Migration complete")

        } catch {
            logger.error("Migration error: \(error.localizedDescription)")
        }
    }
}
