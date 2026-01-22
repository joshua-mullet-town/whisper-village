import SwiftUI
import AppKit

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class NotchRecorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var notchMetrics: (width: CGFloat, height: CGFloat) {
        if let screen = NSScreen.main {
            let safeAreaInsets = screen.safeAreaInsets
            
            // Simplified height calculation - matching calculateWindowMetrics
            let notchHeight: CGFloat
            if safeAreaInsets.top > 0 {
                // We're definitely on a notched MacBook
                // Extend slightly below the notch to fill the full header
                notchHeight = safeAreaInsets.top + 4
            } else {
                // For external displays or non-notched MacBooks, use system menu bar height
                notchHeight = NSStatusBar.system.thickness
            }
            
            // Get actual notch width from safe area insets
            let baseNotchWidth: CGFloat = safeAreaInsets.left > 0 ? safeAreaInsets.left * 2 : 200
            
            // Calculate total width including side sections
            // Must match sectionWidth (130px when active) in NotchRecorderView for each side
            let sectionWidth: CGFloat = 130  // Increased to match NotchRecorderView
            let totalWidth = baseNotchWidth + sectionWidth * 2
            
            return (totalWidth, notchHeight)
        }
        return (280, 24)  // Increased fallback width
    }
    
    init(contentRect: NSRect) {
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        
        super.init(
            contentRect: metrics.frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        
        // Higher z-index for dev build so it appears above production
        let isDevBuild = Bundle.main.bundleIdentifier?.hasSuffix(".debug") ?? false
        self.level = isDevBuild ? .statusBar + 5 : .statusBar + 3
        
        self.backgroundColor = .clear
        self.isOpaque = false
        self.alphaValue = 1.0
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        
        self.appearance = NSAppearance(named: .darkAqua)
        self.styleMask.remove(.titled)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        
        // Keep escape key functionality
        self.standardWindowButton(.closeButton)?.isHidden = true
        
        // CRITICAL: Do NOT set ignoresMouseEvents!
        // Click-through is handled by hitTest(_:) in ClickThroughHostingView
        // which returns nil for areas outside clickable regions.
        self.isMovable = false
        
        print("NotchRecorderPanel initialized")
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    /// Height of the area below the notch (ticker + session dots + summary panel)
    /// Height-aware - expands to fit summary content (legacy summaries can be long)
    static let tickerHeight: CGFloat = 200

    static func calculateWindowMetrics() -> (frame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat) {
        guard let screen = NSScreen.main else {
            return (NSRect(x: 0, y: 0, width: 280, height: 24 + tickerHeight), 280, 24)
        }

        let safeAreaInsets = screen.safeAreaInsets

        // Simplified height calculation
        let notchHeight: CGFloat
        if safeAreaInsets.top > 0 {
            // We're definitely on a notched MacBook
            // Extend slightly below the notch to fill the full header
            notchHeight = safeAreaInsets.top + 4
        } else {
            // For external displays or non-notched MacBooks, use system menu bar height
            notchHeight = NSStatusBar.system.thickness
        }

        // Calculate exact notch width
        let baseNotchWidth: CGFloat = safeAreaInsets.left > 0 ? safeAreaInsets.left * 2 : 200

        // Calculate total width including side sections
        // Must match sectionWidth logic in NotchRecorderView for each side
        let sectionWidth: CGFloat = 130  // Max width when active (increased from 100)
        let totalWidth = baseNotchWidth + sectionWidth * 2

        // Total height includes notch + ticker area below
        let totalHeight = notchHeight + tickerHeight

        // Position exactly at the center, accounting for extra height below
        let xPosition = screen.frame.midX - (totalWidth / 2)
        let yPosition = screen.frame.maxY - totalHeight

        let frame = NSRect(
            x: xPosition,
            y: yPosition,
            width: totalWidth,
            height: totalHeight
        )

        return (frame, baseNotchWidth, notchHeight)
    }
    
    func show() {
        guard let screen = NSScreen.main else { return }
        let metrics = NotchRecorderPanel.calculateWindowMetrics()
        setFrame(metrics.frame, display: true)
        orderFrontRegardless()
    }
    
    func hide(completion: @escaping () -> Void) {
        completion()
    }
    
    @objc private func handleScreenParametersChange() {
        // Add a small delay to ensure we get the correct screen metrics
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            let metrics = NotchRecorderPanel.calculateWindowMetrics()
            self.setFrame(metrics.frame, display: true)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// NotchRecorderHostingController uses ClickThroughHostingView for transparent click-through
class NotchRecorderHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        // Use our custom click-through hosting view (defined in ClickThroughHostingView.swift)
        let hostingView = ClickThroughHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        self.view = hostingView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
} 

