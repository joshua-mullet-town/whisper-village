import SwiftUI

// Minimal ContentView — app is primarily notch-bar + menu bar
// This only exists in case a settings window is opened
struct ContentView: View {
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager

    var body: some View {
        SettingsView()
            .environmentObject(whisperState)
            .frame(minWidth: 500, minHeight: 400)
    }
}
