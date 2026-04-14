import SwiftUI
import SwiftData
import AppKit
import OSLog

@main
struct WhisperVillageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var whisperState: WhisperState
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var menuBarManager: MenuBarManager

    let modelContainer: ModelContainer

    init() {
        // Use the bundle-specific Application Support directory for the SwiftData store
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleId = Bundle.main.bundleIdentifier ?? "town.mullet.WhisperVillage"
        let storeDir = appSupport.appendingPathComponent(bundleId)
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("default.store")
        let config = ModelConfiguration(url: storeURL)
        let container = try! ModelContainer(for: Transcription.self, configurations: config)
        self.modelContainer = container

        let whisperState = WhisperState(modelContext: container.mainContext)
        _whisperState = StateObject(wrappedValue: whisperState)

        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)

        let menuBarManager = MenuBarManager(whisperState: whisperState, hotkeyManager: hotkeyManager)
        _menuBarManager = StateObject(wrappedValue: menuBarManager)

        // Seed cumulative stats from production data if first launch
        LastTranscriptionService.seedCumulativeStatsIfNeeded()

        // Start presenter claim server (port 8179)
        PresenterClaimServer.shared.start(whisperState: whisperState, modelContainer: container)

        Task {
            await whisperState.resetOnLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .modelContainer(modelContainer)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(whisperState)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .modelContainer(modelContainer)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 22
                $0.size.width = 22 / ratio
                return $0
            }(NSImage(named: "menuBarIcon")!)
            Image(nsImage: image)
        }
        .menuBarExtraStyle(.menu)
    }
}
