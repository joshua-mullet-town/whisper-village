import SwiftUI

/// A smooth scrolling ticker that shows live transcription text below the notch.
/// Shows the most recent portion of text, right-aligned so newest content is visible.
struct NotchTranscriptionTicker: View {
    let text: String
    let isRecording: Bool

    /// Maximum characters to display
    private let maxCharacters = 70

    /// Get the tail portion of text to display
    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxCharacters {
            return trimmed
        }
        // Take the last maxCharacters, but try to break at a word boundary
        let tail = String(trimmed.suffix(maxCharacters))
        // Find first space to avoid cutting mid-word
        if let spaceIndex = tail.firstIndex(of: " ") {
            return String(tail[tail.index(after: spaceIndex)...])
        }
        return tail
    }

    private var shouldShow: Bool {
        isRecording && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        // Fixed width container - matches the notch panel width
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.head) // Truncate from the beginning if too long
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 26)
        .frame(maxWidth: .infinity) // Take full available width, but don't exceed it
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.75))
        )
        .clipped() // Clip anything that overflows
        .opacity(shouldShow ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: shouldShow)
    }
}

#Preview {
    VStack(spacing: 20) {
        NotchTranscriptionTicker(
            text: "Hello this is a test of the live transcription ticker view that should show smoothly",
            isRecording: true
        )
        .frame(width: 400)

        NotchTranscriptionTicker(
            text: "Short text",
            isRecording: true
        )
        .frame(width: 400)

        NotchTranscriptionTicker(
            text: "",
            isRecording: false
        )
        .frame(width: 400)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
