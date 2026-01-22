import SwiftUI
import AppKit

/// Shared store for clickable regions that SwiftUI views can update
class ClickableRegionsStore: ObservableObject {
    static let shared = ClickableRegionsStore()

    /// Clickable regions in window coordinates (origin at bottom-left in AppKit)
    /// Key is an identifier, value is the rect in window coordinates
    @Published var regions: [String: CGRect] = [:]

    func setRegion(_ id: String, rect: CGRect) {
        DispatchQueue.main.async {
            let isNew = self.regions[id] == nil
            self.regions[id] = rect
            if isNew {
                print("📍 Registered clickable region '\(id)': \(rect)")
            }
        }
    }

    func removeRegion(_ id: String) {
        DispatchQueue.main.async {
            self.regions.removeValue(forKey: id)
        }
    }

    /// Check if a point (in window coordinates) is within any clickable region
    func containsPoint(_ windowPoint: CGPoint) -> Bool {
        for (_, region) in regions {
            if region.contains(windowPoint) {
                return true
            }
        }
        return false
    }
}

/// Custom NSHostingView that enables click-through for transparent areas.
///
/// The key insight: hitTest(_:) is THE mechanism macOS uses to determine which view
/// receives mouse events. By returning nil for areas outside our clickable regions,
/// we tell macOS "nothing here, check windows below."
///
/// CRITICAL: Do NOT use ignoresMouseEvents - that's a global on/off switch.
/// hitTest gives us per-pixel control.
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // First check if the point is even in our bounds
        guard bounds.contains(point) else {
            return nil
        }

        // Convert to window coordinates for comparison with registered regions
        let windowPoint = convert(point, to: nil)

        // Check if point is in any clickable region
        if ClickableRegionsStore.shared.containsPoint(windowPoint) {
            // Point is in a clickable region - let the normal hit testing proceed
            return super.hitTest(point)
        }

        // Point is outside all clickable regions - return nil to pass through
        // This tells macOS "no view here, check windows below"
        return nil
    }
}

/// SwiftUI view modifier that registers a view's frame as a clickable region
struct ClickableRegion: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            updateFrame(geometry)
                        }
                        .onChange(of: geometry.frame(in: .global)) { _, _ in
                            updateFrame(geometry)
                        }
                }
            )
            .onDisappear {
                ClickableRegionsStore.shared.removeRegion(id)
            }
    }

    private func updateFrame(_ geometry: GeometryProxy) {
        // Get frame in global (screen) coordinates from SwiftUI
        let globalFrame = geometry.frame(in: .global)

        // We need to convert SwiftUI global coords to AppKit window coords
        // SwiftUI global: origin at top-left of screen, Y increases downward
        // AppKit window coords: origin at bottom-left of window, Y increases upward
        //
        // The window is positioned at the top of the screen.
        // We need to know where this view is WITHIN the window.

        guard let screen = NSScreen.main else { return }

        // Get the window metrics to know where the window is
        let windowMetrics = NotchRecorderPanel.calculateWindowMetrics()
        let windowFrame = windowMetrics.frame

        // SwiftUI globalFrame.minY is distance from top of screen
        // Window's top is at screen.frame.maxY - windowFrame.maxY (but window maxY is in AppKit coords from bottom)
        // Actually, windowFrame.origin.y is the bottom of the window in screen coords

        // The view's position in window coordinates:
        // Window top in screen coords = windowFrame.maxY
        // SwiftUI reports from screen top, so globalFrame.minY = distance from screen top
        //
        // In window coords (origin at bottom-left of window):
        // viewBottom = windowHeight - (globalFrame.maxY - windowTop_in_SwiftUI_coords)

        // Window top in SwiftUI coords (from screen top) = screen.frame.height - windowFrame.maxY
        let windowTopInSwiftUI = screen.frame.height - windowFrame.maxY

        // View's position relative to window top (in SwiftUI's downward Y)
        let viewTopRelativeToWindowTop = globalFrame.minY - windowTopInSwiftUI

        // In AppKit window coords, Y=0 is at bottom of window
        // So if view is at top of window, its Y should be near windowFrame.height
        let windowHeight = windowFrame.height
        let viewBottomInWindow = windowHeight - viewTopRelativeToWindowTop - globalFrame.height

        let windowRect = NSRect(
            x: globalFrame.minX - windowFrame.minX,
            y: viewBottomInWindow,
            width: globalFrame.width,
            height: globalFrame.height
        )

        ClickableRegionsStore.shared.setRegion(id, rect: windowRect)
    }
}

extension View {
    /// Mark this view as a clickable region for click-through windows
    func clickableRegion(id: String) -> some View {
        self.modifier(ClickableRegion(id: id))
    }
}

/// NSHostingController that uses ClickThroughHostingView instead of standard NSHostingView
class ClickThroughHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        let hostingView = ClickThroughHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        self.view = hostingView
    }
}
