import SwiftUI

/// Toast view specifically for showing transcription peek results
/// Features: Full text display (scrollable), hover-to-pause countdown, auto-dismiss
struct PeekToastView: View {
    let text: String
    let duration: TimeInterval
    let onClose: () -> Void

    @State private var progress: Double = 1.0
    @State private var timer: Timer?
    @State private var isHovering: Bool = false
    @State private var textHeight: CGFloat = 60

    private let maxTextHeight: CGFloat = 350
    private let toastWidth: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with icon and close button
            HStack {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)

                Text("Transcription Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Hover indicator
                if isHovering {
                    Text("Paused")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                }

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

            // Dynamic height text content - measures text and adjusts height
            ZStack(alignment: .topLeading) {
                // Hidden text to measure actual height needed
                Text(text)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: toastWidth - 28, alignment: .leading) // Account for padding
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TextHeightKey.self, value: geo.size.height + 24) // +24 for padding
                        }
                    )
                    .hidden()

                // Actual scrollable content
                ScrollView {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .frame(height: min(textHeight, maxTextHeight))
            }
            .onPreferenceChange(TextHeightKey.self) { height in
                textHeight = max(60, height) // Minimum 60px
            }

            // Progress bar at bottom
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: geometry.size.width * max(0, progress), height: 3)
                    .animation(.linear(duration: 0.1), value: progress)
            }
            .frame(height: 3)
        }
        .frame(width: toastWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
                .background(
                    ZStack {
                        Color.black.opacity(0.95)
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.98),
                                Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .opacity(0.08)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                // Pause timer
                timer?.invalidate()
                timer = nil
            } else {
                // Resume timer
                startProgressTimer()
            }
        }
        .onAppear {
            startProgressTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startProgressTimer() {
        let updateInterval: TimeInterval = 0.1
        let remainingDuration = duration * progress // Continue from current progress
        let totalSteps = remainingDuration / updateInterval
        guard totalSteps > 0 else {
            onClose()
            return
        }
        let stepDecrement = progress / totalSteps

        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { _ in
            if progress > 0 {
                progress = max(0, progress - stepDecrement)
            } else {
                timer?.invalidate()
                timer = nil
                onClose()
            }
        }
    }
}

// MARK: - Preference Key for measuring text height

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 60
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
