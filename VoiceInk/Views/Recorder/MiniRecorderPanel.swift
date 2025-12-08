import SwiftUI
import AppKit

class MiniRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Save the capsule's bottom position (distance from screen bottom)
    private static let savedCapsuleBottomKey = "MiniRecorderCapsuleBottom"
    private static let savedXKey = "MiniRecorderWindowX"

    // Layout constants
    private static let windowWidth: CGFloat = 450
    private static let capsuleHeight: CGFloat = 36
    private static let spacing: CGFloat = 16
    private static let bottomPadding: CGFloat = 8
    private static let defaultCapsuleBottom: CGFloat = 32 // Default distance from screen bottom

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    /// Static method for initial window creation (MiniWindowManager uses this)
    static func calculateWindowMetrics() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: windowWidth, height: 340)
        }

        let visibleFrame = screen.visibleFrame
        let xPosition = visibleFrame.midX - (windowWidth / 2)
        let yPosition = visibleFrame.minY + defaultCapsuleBottom - bottomPadding

        return NSRect(x: xPosition, y: yPosition, width: windowWidth, height: 340)
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
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
    }

    /// Get the current preview box height from UserDefaults
    private func getPreviewHeight() -> CGFloat {
        let height = UserDefaults.standard.double(forKey: "StreamingPreviewHeight")
        return height > 0 ? CGFloat(height) : 210 // Default 210
    }

    /// Check if streaming mode is enabled
    private func isStreamingEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "StreamingModeEnabled")
    }

    /// Calculate window height based on content
    private func calculateWindowHeight() -> CGFloat {
        if isStreamingEnabled() {
            // Preview box + spacing + capsule + bottom padding + some top margin
            return getPreviewHeight() + MiniRecorderPanel.spacing + MiniRecorderPanel.capsuleHeight + MiniRecorderPanel.bottomPadding + 20
        } else {
            // Just capsule + padding
            return MiniRecorderPanel.capsuleHeight + MiniRecorderPanel.bottomPadding + 20
        }
    }

    /// Calculate window frame to position capsule at saved location
    private func getWindowFrame() -> NSRect {
        let defaults = UserDefaults.standard
        let width = MiniRecorderPanel.windowWidth
        let height = calculateWindowHeight()

        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }

        let visibleFrame = screen.visibleFrame

        // Get saved capsule bottom position, or use default
        let capsuleBottom: CGFloat
        if defaults.object(forKey: MiniRecorderPanel.savedCapsuleBottomKey) != nil {
            capsuleBottom = CGFloat(defaults.double(forKey: MiniRecorderPanel.savedCapsuleBottomKey))
        } else {
            capsuleBottom = MiniRecorderPanel.defaultCapsuleBottom
        }

        // Get saved X, or center horizontally
        let xPosition: CGFloat
        if defaults.object(forKey: MiniRecorderPanel.savedXKey) != nil {
            xPosition = CGFloat(defaults.double(forKey: MiniRecorderPanel.savedXKey))
        } else {
            xPosition = visibleFrame.midX - (width / 2)
        }

        // Window Y: capsule bottom is at (window.y + bottomPadding)
        // So window.y = screenBottom + capsuleBottom - bottomPadding
        let yPosition = visibleFrame.minY + capsuleBottom - MiniRecorderPanel.bottomPadding

        return NSRect(x: xPosition, y: yPosition, width: width, height: height)
    }

    /// Save capsule's bottom position relative to screen
    func savePosition() {
        guard let screen = NSScreen.main else { return }
        let defaults = UserDefaults.standard
        let visibleFrame = screen.visibleFrame

        // Capsule bottom is at window.y + bottomPadding
        let capsuleBottom = frame.origin.y + MiniRecorderPanel.bottomPadding - visibleFrame.minY

        defaults.set(Double(capsuleBottom), forKey: MiniRecorderPanel.savedCapsuleBottomKey)
        defaults.set(Double(frame.origin.x), forKey: MiniRecorderPanel.savedXKey)
    }

    func show() {
        let metrics = getWindowFrame()
        setFrame(metrics, display: true)
        orderFrontRegardless()
    }

    func hide(completion: @escaping () -> Void) {
        // Save position before hiding
        savePosition()
        completion()
    }
}
