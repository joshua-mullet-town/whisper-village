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
        let container = try! ModelContainer(for: Transcription.self)
        self.modelContainer = container

        let whisperState = WhisperState(modelContext: container.mainContext)
        _whisperState = StateObject(wrappedValue: whisperState)

        let hotkeyManager = HotkeyManager(whisperState: whisperState)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)

        let menuBarManager = MenuBarManager(whisperState: whisperState, hotkeyManager: hotkeyManager)
        _menuBarManager = StateObject(wrappedValue: menuBarManager)

        // Start presenter claim server (port 8179)
        PresenterClaimServer.shared.start(whisperState: whisperState)

        Task {
            await whisperState.resetOnLaunch()
        }
    }

    var body: some Scene {
        // No main window — app is notch-bar + menu bar only
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
