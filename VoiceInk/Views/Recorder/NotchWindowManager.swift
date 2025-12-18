import SwiftUI
import AppKit

class NotchWindowManager: ObservableObject {
    @Published var isVisible = false
    private var windowController: NSWindowController?
     var notchPanel: NotchRecorderPanel?
    private let whisperState: WhisperState
    private let recorder: Recorder

    /// Whether the notch should stay visible at all times
    private var isAlwaysVisible: Bool {
        UserDefaults.standard.bool(forKey: "NotchAlwaysVisible")
    }

    init(whisperState: WhisperState, recorder: Recorder) {
        self.whisperState = whisperState
        self.recorder = recorder

        StreamingLogger.shared.log("🔧 NotchWindowManager INIT")
        StreamingLogger.shared.log("  NotchAlwaysVisible: \(UserDefaults.standard.bool(forKey: "NotchAlwaysVisible"))")
        StreamingLogger.shared.log("  RecorderType: '\(UserDefaults.standard.string(forKey: "RecorderType") ?? "nil")'")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideNotification),
            name: NSNotification.Name("HideNotchRecorder"),
            object: nil
        )

        // Show immediately if always visible is enabled
        if UserDefaults.standard.bool(forKey: "NotchAlwaysVisible") {
            StreamingLogger.shared.log("  ⚠️ NotchAlwaysVisible=true, WILL CALL showAlwaysVisible() in async")
            DispatchQueue.main.async { [weak self] in
                self?.showAlwaysVisible()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleHideNotification() {
        hide()
    }

    /// Show the notch for always-visible mode (idle state on app launch)
    func showAlwaysVisible() {
        guard isAlwaysVisible else { return }
        if isVisible { return }

        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        initializeWindow(screen: activeScreen)
        self.isVisible = true
        notchPanel?.show()
    }

    func show() {
        StreamingLogger.shared.log("📱 NotchWindowManager.show() called")
        StreamingLogger.shared.log("  isVisible BEFORE: \(isVisible)")
        if isVisible {
            StreamingLogger.shared.log("  EARLY RETURN: already visible")
            return
        }

        // Get the active screen from the key window or fallback to main screen
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]

        initializeWindow(screen: activeScreen)
        self.isVisible = true
        notchPanel?.show()
        StreamingLogger.shared.log("  isVisible AFTER: \(isVisible)")
    }

    func hide() {
        guard isVisible else { return }

        // If always visible is enabled, don't actually hide - just stay visible in idle state
        if isAlwaysVisible {
            // Window stays visible, view will handle visual state based on recordingState
            return
        }

        // Remove animation for instant state change
        self.isVisible = false

        // Don't wait for animation, clean up immediately
        self.notchPanel?.hide { [weak self] in
            guard let self = self else { return }
            self.deinitializeWindow()
        }
    }
    
    private func initializeWindow(screen: NSScreen) {
        deinitializeWindow()
        
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        let panel = NotchRecorderPanel(contentRect: metrics.frame)
        
        let notchRecorderView = NotchRecorderView(
            whisperState: whisperState,
            recorder: recorder,
            streamingRecorder: whisperState.streamingRecorder
        )
            .environmentObject(self)
            .environmentObject(whisperState.enhancementService!)
        
        let hostingController = NotchRecorderHostingController(rootView: notchRecorderView)
        panel.contentView = hostingController.view
        
        self.notchPanel = panel
        self.windowController = NSWindowController(window: panel)
        
        panel.orderFrontRegardless()
    }
    
    private func deinitializeWindow() {
        windowController?.close()
        windowController = nil
        notchPanel = nil
    }
    
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
} 
