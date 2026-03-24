import SwiftUI
import AppKit

class NotificationManager {
    static let shared = NotificationManager()

    private var notificationWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    enum NotificationType {
        case info, success, warning, error
    }

    @MainActor
    func showNotification(
        title: String,
        type: NotificationType,
        duration: TimeInterval = 5.0,
        onTap: (() -> Void)? = nil,
        actionButton: (title: String, action: () -> Void)? = nil
    ) {
        // Minimal notification — just log it
        if type == .error {
            SoundManager.shared.playEscSound()
        }
        StreamingLogger.shared.log("Notification [\(type)]: \(title)")
    }

    @MainActor
    func dismissNotification() {
        // No-op — notifications are now log-only
    }

    // MARK: - Peek Toast (for transcription previews)

    private var peekWindow: NSPanel?

    @MainActor
    func showPeekToast(
        text: String,
        duration: TimeInterval = 8.0
    ) {
        // Close any existing peek toast
        if let existingWindow = peekWindow {
            existingWindow.close()
            peekWindow = nil
        }

        let peekView = PeekToastView(
            text: text,
            duration: duration,
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.dismissPeekToast()
                }
            }
        )
        let hostingController = NSHostingController(rootView: peekView)
        let size = hostingController.view.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingController.view
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level.mainMenu
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true  // Enable dragging

        // Position above the mini recorder (centered, near bottom)
        positionPeekWindow(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)

        self.peekWindow = panel

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })
    }

    @MainActor
    private func positionPeekWindow(_ window: NSWindow) {
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = activeScreen.visibleFrame
        let windowRect = window.frame

        // Center horizontally
        let x = screenRect.midX - (windowRect.width / 2)

        // Position above the mini recorder area (about 120px from bottom)
        let y = screenRect.minY + 120

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @MainActor
    func dismissPeekToast() {
        guard let window = peekWindow else { return }

        peekWindow = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    // MARK: - Live Box stubs (removed — kept for API compatibility)

    @MainActor func showLiveBox() {}
    @MainActor func updateLiveBox(text: String) {}
    @MainActor func dismissLiveBox() {}
    @MainActor func toggleLiveBox() {}
    @MainActor var isLiveBoxVisible: Bool { false }
    @MainActor func setLiveBoxOpacity(_ opacity: Double) {}

    // MARK: - Format Content Box stubs (removed)

    @MainActor func showFormatContentBox(content: String) {}
    @MainActor func dismissFormatContentBox() {}
    @MainActor var isFormatContentBoxVisible: Bool { false }
} 