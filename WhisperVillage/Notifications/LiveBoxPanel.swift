import SwiftUI
import AppKit

/// Custom NSPanel for the Live Box that properly handles mouse events
/// Follows the same pattern as MiniRecorderPanel which has working buttons
class LiveBoxPanel: NSPanel {
    // Allow clicking without stealing focus from other apps
    override var canBecomeKey: Bool { true }  // Allow key to enable button clicks
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    private func configurePanel() {
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }
}
