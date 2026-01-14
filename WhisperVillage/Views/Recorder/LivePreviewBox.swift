import SwiftUI

/// A draggable, resizable, vertically-scrolling live transcription preview box
struct LivePreviewBox: View {
    let text: String
    let isRecording: Bool

    // Persisted state
    @AppStorage("PreviewBoxPositionX") private var positionX: Double = 400
    @AppStorage("PreviewBoxPositionY") private var positionY: Double = 300
    @AppStorage("PreviewBoxOpacity") private var boxOpacity: Double = 0.85
    @AppStorage("PreviewBoxHeight") private var boxHeight: Double = 120

    // Drag state
    @State private var dragOffset: CGSize = .zero

    // Box dimensions
    private var boxWidth: CGFloat { 320 }
    private let minHeight: CGFloat = 60
    private let maxHeight: CGFloat = 400
    private let heightStep: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // Main content
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if text.isEmpty {
                                Text("Listening...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.horizontal, 12)
                                    .padding(.top, 28) // Space for controls
                                    .padding(.bottom, 8)
                            } else {
                                Text(text)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 28) // Space for controls
                                    .padding(.bottom, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("bottomAnchor")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: text) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("bottomAnchor", anchor: .bottom)
                        }
                    }
                }

                // Controls (top-right)
                HStack(spacing: 4) {
                    // Size controls
                    Button(action: { boxHeight = max(minHeight, boxHeight - heightStep) }) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Shrink")

                    Button(action: { boxHeight = min(maxHeight, boxHeight + heightStep) }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Grow")

                    Divider()
                        .frame(height: 10)
                        .background(Color.white.opacity(0.2))

                    // Opacity controls
                    Button(action: { boxOpacity = max(0.3, boxOpacity - 0.15) }) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Less opaque")

                    Button(action: { boxOpacity = min(1.0, boxOpacity + 0.15) }) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("More opaque")

                    Divider()
                        .frame(height: 10)
                        .background(Color.white.opacity(0.2))

                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(width: boxWidth, height: CGFloat(boxHeight))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(boxOpacity * 0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isRecording
                            ? Color.orange.opacity(0.4)
                            : Color.white.opacity(0.15),
                        lineWidth: isRecording ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .position(
                x: CGFloat(positionX) + dragOffset.width,
                y: CGFloat(positionY) + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        positionX += Double(value.translation.width)
                        positionY += Double(value.translation.height)
                        dragOffset = .zero

                        // Keep within screen bounds
                        let screenWidth = geometry.size.width
                        let screenHeight = geometry.size.height
                        let halfWidth = Double(boxWidth / 2)
                        let halfHeight = boxHeight / 2
                        positionX = max(halfWidth, min(Double(screenWidth) - halfWidth, positionX))
                        positionY = max(halfHeight, min(Double(screenHeight) - halfHeight, positionY))
                    }
            )
            .onAppear {
                // Always ensure box is visible within current geometry
                let screenWidth = Double(geometry.size.width)
                let screenHeight = Double(geometry.size.height)
                let halfWidth = Double(boxWidth) / 2
                let halfHeight = boxHeight / 2

                // If position is outside visible bounds, center it
                if positionX < halfWidth || positionX > screenWidth - halfWidth ||
                   positionY < halfHeight || positionY > screenHeight - halfHeight ||
                   screenWidth < 100 || screenHeight < 100 {
                    positionX = screenWidth / 2
                    positionY = screenHeight / 2
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                // Re-center if geometry changed significantly (window resize)
                let screenWidth = Double(newSize.width)
                let screenHeight = Double(newSize.height)
                let halfWidth = Double(boxWidth) / 2
                let halfHeight = boxHeight / 2

                // Clamp to new bounds
                positionX = max(halfWidth, min(screenWidth - halfWidth, positionX))
                positionY = max(halfHeight, min(screenHeight - halfHeight, positionY))
            }
        }
        .opacity(isRecording ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }
}
