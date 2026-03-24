import SwiftUI
import SwiftData

/// Dropdown history panel shown from the notch bar
struct TranscriptionHistoryDropdown: View {
    @Query(sort: \Transcription.timestamp, order: .reverse) private var transcriptions: [Transcription]
    @State private var expandedId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with stats
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text("\(transcriptions.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if transcriptions.isEmpty {
                Text("No transcriptions yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(transcriptions.prefix(50)) { transcription in
                            TranscriptionHistoryRow(
                                transcription: transcription,
                                isExpanded: expandedId == transcription.id
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedId = expandedId == transcription.id ? nil : transcription.id
                                }
                            }

                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

struct TranscriptionHistoryRow: View {
    let transcription: Transcription
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Timestamp
                Text(timeAgo(transcription.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                // Preview text
                Text(transcription.text)
                    .font(.system(size: 12))
                    .lineLimit(isExpanded ? nil : 1)
                    .truncationMode(.tail)

                Spacer()

                // Copy button
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(transcription.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy to clipboard")

                // Chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            if isExpanded {
                // Model info
                if let model = transcription.transcriptionModelName {
                    Text("Model: \(model)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if transcription.duration > 0 {
                    Text("Duration: \(String(format: "%.1fs", transcription.duration))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isExpanded ? Color.primary.opacity(0.04) : Color.clear)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
