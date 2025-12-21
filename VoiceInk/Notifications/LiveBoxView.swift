import SwiftUI

/// Observable model for live box text - allows updating without replacing the view
class LiveBoxModel: ObservableObject {
    @Published var text: String = ""
}

/// Live transcription preview box that stays visible during recording
/// Features: Draggable (via LiveBoxPanel), adjustable height, adjustable opacity
struct LiveBoxView: View {
    @ObservedObject var model: LiveBoxModel
    let onClose: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @AppStorage("LiveBoxHeight") private var savedHeight: Double = 120
    @AppStorage("LiveBoxOpacity") private var boxOpacity: Double = 0.95

    @State private var currentHeight: CGFloat = 120

    private let minHeight: CGFloat = 60
    private let maxHeight: CGFloat = 400
    private let heightStep: CGFloat = 40
    private let boxWidth: CGFloat = 420
    private let minOpacity: Double = 0.3
    private let maxOpacity: Double = 1.0
    private let opacityStep: Double = 0.15

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with drag handle, height controls, and close button
            // Dragging is handled by LiveBoxPanel (isMovableByWindowBackground)
            HStack {
                // Drag handle indicator
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20)

                Image(systemName: "waveform")
                    .font(.system(size: 12))
                    .foregroundColor(.green)

                Text("Live Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Height adjustment buttons
                HStack(spacing: 4) {
                    Button(action: decreaseHeight) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(currentHeight <= minHeight ? .white.opacity(0.2) : .white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(currentHeight <= minHeight)

                    Button(action: increaseHeight) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(currentHeight >= maxHeight ? .white.opacity(0.2) : .white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(currentHeight >= maxHeight)
                }
                .padding(.trailing, 4)

                // Opacity controls (moved here from footer)
                HStack(spacing: 4) {
                    Button(action: decreaseOpacity) {
                        Image(systemName: "sun.min.fill")
                            .font(.system(size: 12))
                            .foregroundColor(boxOpacity <= minOpacity ? .white.opacity(0.2) : .white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: increaseOpacity) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 12))
                            .foregroundColor(boxOpacity >= maxOpacity ? .white.opacity(0.2) : .white.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.trailing, 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .background(Color.white.opacity(0.1))

            // Scrollable text content
            ScrollViewReader { proxy in
                ScrollView {
                    Text(model.text.isEmpty ? "Listening..." : model.text)
                        .font(.system(size: 14))
                        .foregroundColor(model.text.isEmpty ? .white.opacity(0.4) : .white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .id("textContent")
                }
                .frame(height: currentHeight)
                .onChange(of: model.text) { _, _ in
                    // Auto-scroll to bottom when text updates
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("textContent", anchor: .bottom)
                    }
                }
            }

            // Recording indicator bar at bottom (simplified - opacity controls moved to header)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .fill(Color.orange.opacity(0.4))
                            .frame(width: 12, height: 12)
                    )

                Text("Listening...")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Image(systemName: "hand.draw")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
        }
        .frame(width: boxWidth)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .background(
                    ZStack {
                        // Softer, warmer dark background
                        Color(red: 0.12, green: 0.11, blue: 0.13).opacity(0.92)
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.14, blue: 0.17).opacity(0.95),
                                Color(red: 0.10, green: 0.09, blue: 0.11).opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .opacity(0.15)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.green.opacity(0.4), Color.purple.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            // Load saved height from UserDefaults and resize window to match
            currentHeight = CGFloat(savedHeight)
            onHeightChange(currentHeight)
        }
    }

    private func increaseHeight() {
        let newHeight = min(currentHeight + heightStep, maxHeight)
        currentHeight = newHeight
        savedHeight = Double(newHeight)  // Persist to UserDefaults
        onHeightChange(newHeight)
    }

    private func decreaseHeight() {
        let newHeight = max(currentHeight - heightStep, minHeight)
        currentHeight = newHeight
        savedHeight = Double(newHeight)  // Persist to UserDefaults
        onHeightChange(newHeight)
    }

    private func increaseOpacity() {
        let newOpacity = min(boxOpacity + opacityStep, maxOpacity)
        StreamingLogger.shared.log("🔆 INCREASE OPACITY: \(boxOpacity) -> \(newOpacity)")
        boxOpacity = newOpacity
        NotificationManager.shared.setLiveBoxOpacity(newOpacity)
    }

    private func decreaseOpacity() {
        let newOpacity = max(boxOpacity - opacityStep, minOpacity)
        StreamingLogger.shared.log("🔅 DECREASE OPACITY: \(boxOpacity) -> \(newOpacity)")
        boxOpacity = newOpacity
        NotificationManager.shared.setLiveBoxOpacity(newOpacity)
    }
}
