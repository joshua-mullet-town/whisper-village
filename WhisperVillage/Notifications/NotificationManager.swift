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
        StreamingLogger.shared.log("Notification [\(type)]: \(title)")
        DictationAuditLog.shared.log("NOTIFY", ["type": "\(type)", "title": title])

        // Errors must be SEEN, not just logged. This used to be log-only, which is
        // why a dictation could fail with no sound and nothing on screen — the user
        // had no way to tell a failure from the app never hearing them. Reuse the
        // existing on-screen toast so a failure is impossible to miss.
        if type == .error || type == .warning {
            SoundManager.shared.playEscSound()
            showPeekToast(text: title, duration: duration)
        }
    }

    @MainActor
    func dismissNotification() {
        // No-op — notifications are now log-only
    }

    // MARK: - Peek Toast (for transcription previews)

    private var peekWindow: NSPanel?
    private var peekCloseObserver: NSObjectProtocol?

    /// True while the peek toast is on screen. Read by GET /status so the
    /// Homestead presenter can VERIFY the peek's state rather than guess at it.
    @MainActor
    var isPeekVisible: Bool { peekWindow != nil }

    /// Tell the Homestead presenter whether a peek is on screen RIGHT NOW.
    ///
    /// The presenter floats above full-screen apps so it can cover full-screen
    /// Chrome; that also puts it above this panel, which is why Josh could not
    /// see his Option+P preview. It drops out of the way while a peek is up,
    /// but only if we tell it — it cannot infer the peek's lifetime, because
    /// hover-pause keeps the toast up with no upper bound.
    ///
    /// Deliberately LEVEL-triggered, not an open/close edge. During a
    /// peek-replaces-peek the old window's close fires while the replacement is
    /// still being built, so an edge could say "closed" with a peek going up.
    /// Sending the current state makes that harmless: whichever message lands
    /// last describes reality.
    ///
    /// Fire-and-forget. The presenter is often not running, and per the caution
    /// in PresenterClaimServer (a synchronous NotificationCenter.post once
    /// pinned the main actor) this must never block — dataTask().resume()
    /// returns immediately and does its work off-actor.
    @MainActor
    private func notifyPresenterPeekState() {
        let visible = (peekWindow != nil)
        guard let url = URL(string: "http://127.0.0.1:3847/wv-peek") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{\"visible\":\(visible)}".data(using: .utf8)
        req.timeoutInterval = 1
        URLSession.shared.dataTask(with: req).resume()
    }

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

        // Observe THIS panel's own close. willCloseNotification covers every
        // close path — dismissPeekToast's fade completion handler, the X
        // button, the countdown, and the direct `existingWindow.close()`
        // replace above, which never routes through dismissPeekToast at all.
        // Instrumenting call sites cannot cover that last one.
        //
        // `object: panel` scopes it to this instance so a superseded window's
        // close cannot speak for a live one. The panel is released when closed
        // (isReleasedWhenClosed defaults true), so the observer must not
        // outlive it — we remove the token inside the handler.
        if let old = peekCloseObserver {
            NotificationCenter.default.removeObserver(old)
            peekCloseObserver = nil
        }
        weak var thisPanel = panel
        peekCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Ignore a close belonging to a panel that has already been
            // superseded: during a replace this fires for the OLD window while
            // peekWindow may already point at the NEW one.
            guard self.peekWindow == nil || self.peekWindow === thisPanel else { return }
            if self.peekWindow === thisPanel { self.peekWindow = nil }
            if let tok = self.peekCloseObserver {
                NotificationCenter.default.removeObserver(tok)
                self.peekCloseObserver = nil
            }
            self.notifyPresenterPeekState()
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        })

        // peekWindow is set, so this sends visible:true. If the replace above
        // emitted a false for the superseded window, this immediately corrects
        // it — and because the notify is level-triggered, the last word is
        // always the truth.
        notifyPresenterPeekState()
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