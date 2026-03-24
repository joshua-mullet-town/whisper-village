import SwiftUI
import AppKit

class MenuBarManager: ObservableObject {
    @Published var isMenuBarOnly: Bool = true

    private var whisperState: WhisperState
    private var hotkeyManager: HotkeyManager

    init(whisperState: WhisperState, hotkeyManager: HotkeyManager) {
        self.whisperState = whisperState
        self.hotkeyManager = hotkeyManager
    }
}
