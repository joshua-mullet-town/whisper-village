import Cocoa
import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize crash reporter FIRST (before anything else)
        CrashReporter.shared.initialize()

        updateActivationPolicy()
        cleanupLegacyUserDefaults()
        runSettingsMigrations()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Mark clean shutdown so we don't report false crashes
        CrashReporter.shared.markCleanShutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        updateActivationPolicy()
        
        if !flag {
            createMainWindowIfNeeded()
        }
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        updateActivationPolicy()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func updateActivationPolicy() {
        let isMenuBarOnly = UserDefaults.standard.bool(forKey: "IsMenuBarOnly")
        if isMenuBarOnly {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    private func createMainWindowIfNeeded() {
        if NSApp.windows.isEmpty {
            let contentView = ContentView()
            let hostingView = NSHostingView(rootView: contentView)
            let window = WindowManager.shared.createMainWindow(contentView: hostingView)
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func cleanupLegacyUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "defaultPowerModeConfigV2")
        defaults.removeObject(forKey: "isPowerModeEnabled")

        // Force notch recorder for all users (deprecating mini recorder)
        // This ensures users who had "mini" saved are migrated to "notch"
        defaults.set("notch", forKey: "RecorderType")
    }

    /// One-time settings migrations that run on app update
    private func runSettingsMigrations() {
        let defaults = UserDefaults.standard

        // v1.9.3: Enable Live Preview Box mode and auto-formatting for all users
        let migrationKey_v193 = "SettingsMigration_v1.9.3_LivePreviewBox"
        if !defaults.bool(forKey: migrationKey_v193) {
            defaults.set(true, forKey: "LivePreviewEnabled")
            defaults.set("box", forKey: "LivePreviewStyle")
            defaults.set(true, forKey: "SmartCapitalizationEnabled")
            defaults.set(true, forKey: "AutoEndPunctuationEnabled")
            defaults.set(true, forKey: migrationKey_v193)
            StreamingLogger.shared.log("✅ Settings migration v1.9.3 complete: Live Preview Box + Auto-formatting enabled")
        }

        // v1.9.4: Force StreamingModeEnabled on for all users
        // This is required for live preview to show words - no reason to have it off
        let migrationKey_v194 = "SettingsMigration_v1.9.4_StreamingMode"
        if !defaults.bool(forKey: migrationKey_v194) {
            defaults.set(true, forKey: "StreamingModeEnabled")
            defaults.set(true, forKey: migrationKey_v194)
            StreamingLogger.shared.log("✅ Settings migration v1.9.4 complete: StreamingMode force-enabled")
        }
    }
    
    // Stash URL when app cold-starts to avoid spawning a new window/tab
    var pendingOpenFileURL: URL?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { SupportedMedia.isSupported(url: $0) }) else {
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        if NSApp.windows.isEmpty {
            // Cold start: do NOT create a window here to avoid extra window/tab.
            // Defer to SwiftUI’s WindowGroup-created ContentView and let it process this later.
            pendingOpenFileURL = url
        } else {
            // Running: focus current window and route in-place to Transcribe Audio
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": url])
            }
        }
    }
}
