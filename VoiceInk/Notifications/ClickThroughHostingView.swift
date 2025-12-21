import SwiftUI
import AppKit

/// Custom NSHostingView that enables click-through for all SwiftUI buttons
/// This fixes the issue where PlainButtonStyle buttons don't respond in floating panels
/// Reference: https://christiantietze.de/posts/2024/04/enable-swiftui-button-click-through-inactive-windows/
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// NSHostingController that uses ClickThroughHostingView instead of standard NSHostingView
class ClickThroughHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        let hostingView = ClickThroughHostingView(rootView: rootView)
        self.view = hostingView
    }
}
