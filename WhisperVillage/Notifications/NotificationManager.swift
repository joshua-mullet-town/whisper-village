import SwiftUI
import AppKit

class NotificationManager {
    static let shared = NotificationManager()

    private var notificationWindow: NSPanel?
    private var dismissTimer: Timer?

    private init() {}

    @MainActor
    func showNotification(
        title: String,
        type: AppNotificationView.NotificationType,
        duration: TimeInterval = 5.0,
        onTap: (() -> Void)? = nil,
        actionButton: (title: String, action: () -> Void)? = nil
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if let existingWindow = notificationWindow {
            existingWindow.close()
            notificationWindow = nil
        }

        // Play esc sound for error notifications
        if type == .error {
            SoundManager.shared.playEscSound()
        }

        let notificationView = AppNotificationView(
            title: title,
            type: type,
            duration: duration,
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.dismissNotification()
                }
            },
            onTap: onTap,
            actionButton: actionButton
        )
        let hostingController = NSHostingController(rootView: notificationView)
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
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        
        positionWindow(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil as Any?)
        
        self.notificationWindow = panel
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })
        
        // Schedule a new timer to dismiss the new notification.
        dismissTimer = Timer.scheduledTimer(
            withTimeInterval: duration,
            repeats: false
        ) { [weak self] _ in
            self?.dismissNotification()
        }
    }

    @MainActor
    private func positionWindow(_ window: NSWindow) {
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let screenRect = activeScreen.visibleFrame
        let notificationRect = window.frame
        
        // Position notification centered horizontally on screen
        let notificationX = screenRect.midX - (notificationRect.width / 2)
        
        // Position notification near bottom of screen with appropriate spacing
        let bottomPadding: CGFloat = 24
        let componentHeight: CGFloat = 34
        let notificationSpacing: CGFloat = 16
        let notificationY = screenRect.minY + bottomPadding + componentHeight + notificationSpacing
        
        window.setFrameOrigin(NSPoint(x: notificationX, y: notificationY))
    }

    @MainActor
    func dismissNotification() {
        guard let window = notificationWindow else { return }

        notificationWindow = nil

        dismissTimer?.invalidate()
        dismissTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()

        })
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

    // MARK: - Live Box (for live transcription preview during recording)

    private var liveBoxWindow: LiveBoxPanel?
    private var liveBoxHostingController: ClickThroughHostingController<LiveBoxView>?
    private var liveBoxModel: LiveBoxModel?

    // Keys for persisting LiveBox position
    private let liveBoxPositionXKey = "LiveBoxPositionX"
    private let liveBoxPositionYKey = "LiveBoxPositionY"

    @MainActor
    func showLiveBox() {
        StreamingLogger.shared.log("📦 showLiveBox() ENTER")

        // Close any existing live box
        if let existingWindow = liveBoxWindow {
            StreamingLogger.shared.log("📦 Closing existing live box window")
            existingWindow.close()
            liveBoxWindow = nil
            liveBoxHostingController = nil
            liveBoxModel = nil
        }

        // Create the model that will be updated without recreating the view
        let model = LiveBoxModel()
        self.liveBoxModel = model

        let liveBoxView = LiveBoxView(
            model: model,
            onClose: { [weak self] in
                Task { @MainActor in
                    self?.dismissLiveBox()
                }
            },
            onHeightChange: { [weak self] newHeight in
                Task { @MainActor in
                    self?.adjustLiveBoxWindowHeight(newHeight)
                }
            }
        )

        let hostingController = ClickThroughHostingController(rootView: liveBoxView)
        let size = hostingController.view.fittingSize
        StreamingLogger.shared.log("📦 LiveBox fittingSize: \(size.width)x\(size.height)")

        // Use our custom LiveBoxPanel that properly handles mouse events
        let panel = LiveBoxPanel()
        panel.setContentSize(size)
        panel.contentView = hostingController.view

        // Position centered, near bottom of screen
        positionLiveBoxWindow(panel)
        let frame = panel.frame
        StreamingLogger.shared.log("📦 LiveBox positioned at: (\(Int(frame.origin.x)), \(Int(frame.origin.y))) size: \(Int(frame.width))x\(Int(frame.height))")

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        self.liveBoxWindow = panel
        self.liveBoxHostingController = hostingController

        // Get saved opacity (default 0.95)
        let savedOpacity = UserDefaults.standard.double(forKey: "LiveBoxOpacity")
        let targetOpacity = savedOpacity > 0 ? savedOpacity : 0.95
        StreamingLogger.shared.log("📦 LiveBox animating to opacity: \(targetOpacity)")

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = CGFloat(targetOpacity)
        })

        StreamingLogger.shared.log("📦 showLiveBox() EXIT - window created: \(liveBoxWindow != nil)")
    }

    @MainActor
    func updateLiveBox(text: String) {
        // Simply update the model - SwiftUI will handle the rest
        // No view recreation needed!
        liveBoxModel?.text = text
    }

    @MainActor
    func dismissLiveBox() {
        dismissLiveBoxWindow(clearModel: true)
    }

    @MainActor
    private func dismissLiveBoxWindow(clearModel: Bool) {
        guard let window = liveBoxWindow else { return }

        // Save position before closing
        saveLiveBoxPosition()

        // Save text before clearing if we might need it
        let savedText = liveBoxModel?.text ?? ""

        liveBoxWindow = nil
        liveBoxHostingController = nil
        if clearModel {
            liveBoxModel = nil
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.close()
            // If we're preserving the model, store the text for restoration
            if !clearModel {
                self?.preservedLiveBoxText = savedText
            }
        })
    }

    private var preservedLiveBoxText: String = ""

    @MainActor
    func toggleLiveBox() {
        if liveBoxWindow != nil {
            // Hide but preserve text for when we toggle back on
            dismissLiveBoxWindow(clearModel: false)
        } else {
            showLiveBox()
            // Restore the preserved text if we have any
            if !preservedLiveBoxText.isEmpty {
                liveBoxModel?.text = preservedLiveBoxText
            }
        }
    }

    @MainActor
    var isLiveBoxVisible: Bool {
        liveBoxWindow != nil
    }

    @MainActor
    func setLiveBoxOpacity(_ opacity: Double) {
        StreamingLogger.shared.log("📦 setLiveBoxOpacity: \(opacity)")
        if let window = liveBoxWindow {
            window.alphaValue = CGFloat(opacity)
        }
    }

    @MainActor
    private func positionLiveBoxWindow(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        let savedX = defaults.double(forKey: liveBoxPositionXKey)
        let savedTopY = defaults.double(forKey: liveBoxPositionYKey)  // This is the TOP edge (maxY)

        // Check if we have a saved position (both > 0 means it was saved)
        if savedX > 0 || savedTopY > 0 {
            // Convert saved top edge to origin (bottom edge)
            // origin.y = maxY - height
            let originY = savedTopY - window.frame.height
            var proposedOrigin = NSPoint(x: savedX, y: originY)

            // Bounds check: ensure window is visible on at least one screen
            proposedOrigin = clampToVisibleScreen(origin: proposedOrigin, windowSize: window.frame.size)
            window.setFrameOrigin(proposedOrigin)
        } else {
            // Default: center horizontally, 150px from bottom
            let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let screenRect = activeScreen.visibleFrame
            let windowRect = window.frame

            let x = screenRect.midX - (windowRect.width / 2)
            let y = screenRect.minY + 150

            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Clamp window origin to ensure it's visible on at least one screen
    private func clampToVisibleScreen(origin: NSPoint, windowSize: NSSize) -> NSPoint {
        // Find the screen that contains the most of this window, or the main screen
        let windowRect = NSRect(origin: origin, size: windowSize)

        // Check if window is at least partially visible on any screen
        var bestScreen: NSScreen?
        var bestOverlap: CGFloat = 0

        for screen in NSScreen.screens {
            let intersection = screen.visibleFrame.intersection(windowRect)
            if !intersection.isNull {
                let overlap = intersection.width * intersection.height
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestScreen = screen
                }
            }
        }

        // If window is visible on a screen, use saved position
        if bestOverlap > 0 {
            return origin
        }

        // Window is completely off-screen - reset to center of main screen
        StreamingLogger.shared.log("📦 LiveBox position was off-screen (\(Int(origin.x)), \(Int(origin.y))), resetting to center")

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame

        let x = screenRect.midX - (windowSize.width / 2)
        let y = screenRect.minY + 150

        // Clear the invalid saved position
        UserDefaults.standard.removeObject(forKey: liveBoxPositionXKey)
        UserDefaults.standard.removeObject(forKey: liveBoxPositionYKey)

        return NSPoint(x: x, y: y)
    }

    @MainActor
    private func saveLiveBoxPosition() {
        guard let window = liveBoxWindow else { return }
        let frame = window.frame
        // Save X origin and TOP edge (maxY) - this is stable regardless of height
        UserDefaults.standard.set(frame.origin.x, forKey: liveBoxPositionXKey)
        UserDefaults.standard.set(frame.maxY, forKey: liveBoxPositionYKey)  // Save top edge, not bottom
    }

    @MainActor
    private func adjustLiveBoxWindowHeight(_ newHeight: CGFloat) {
        guard let window = liveBoxWindow else { return }

        // Recalculate the window size based on new content height
        let currentFrame = window.frame
        let newSize = liveBoxHostingController?.view.fittingSize ?? currentFrame.size

        // Keep the same x position and top edge, adjust bottom
        let newY = currentFrame.maxY - newSize.height
        let newFrame = NSRect(
            x: currentFrame.minX,
            y: newY,
            width: newSize.width,
            height: newSize.height
        )

        window.setFrame(newFrame, display: true, animate: true)
    }

    // MARK: - Format Content Box (shows Stage 1 content during Format with AI)

    private var formatContentWindow: FormatContentPanel?
    private var formatContentHostingController: NSHostingController<FormatContentBox>?

    // Keys for persisting position
    private let formatContentPositionXKey = "FormatContentPositionX"
    private let formatContentPositionYKey = "FormatContentPositionY"

    @MainActor
    func showFormatContentBox(content: String) {
        // Close any existing format content box
        if let existingWindow = formatContentWindow {
            existingWindow.close()
            formatContentWindow = nil
            formatContentHostingController = nil
        }

        let panel = FormatContentPanel()

        let formatContentView = FormatContentBox(
            content: content,
            onDismiss: { [weak self] in
                Task { @MainActor in
                    self?.dismissFormatContentBox()
                }
            }
        )

        let hostingController = NSHostingController(rootView: formatContentView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        panel.contentView = hostingController.view

        // Position the panel - check for saved position
        if let screen = NSScreen.main {
            let savedX = UserDefaults.standard.double(forKey: formatContentPositionXKey)
            let savedY = UserDefaults.standard.double(forKey: formatContentPositionYKey)

            if savedX != 0 || savedY != 0 {
                // Use saved position
                panel.setFrameOrigin(NSPoint(x: savedX, y: savedY))
            } else {
                // Default: position on left side, vertically centered
                let screenFrame = screen.visibleFrame
                let panelSize = panel.frame.size
                let x = screenFrame.minX + 50
                let y = screenFrame.midY - (panelSize.height / 2)
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        panel.alphaValue = 0
        panel.orderFront(nil)

        self.formatContentWindow = panel
        self.formatContentHostingController = hostingController

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0.95
        })
    }

    @MainActor
    func dismissFormatContentBox() {
        guard let window = formatContentWindow else { return }

        // Save position before closing
        saveFormatContentPosition()

        formatContentWindow = nil
        formatContentHostingController = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }

    @MainActor
    private func saveFormatContentPosition() {
        guard let window = formatContentWindow else { return }
        let frame = window.frame
        UserDefaults.standard.set(frame.origin.x, forKey: formatContentPositionXKey)
        UserDefaults.standard.set(frame.origin.y, forKey: formatContentPositionYKey)
    }

    @MainActor
    var isFormatContentBoxVisible: Bool {
        formatContentWindow != nil
    }
} 