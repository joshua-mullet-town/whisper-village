import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var whisperState: WhisperState
    @AppStorage("NotchAlwaysVisible") private var notchAlwaysVisible = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Transcription Model
                TranscriptionModelSection()

                // Shortcuts
                ShortcutsSection()

                // Visual
                SettingsSection(
                    icon: "sparkles.rectangle.stack.fill",
                    title: "Visual",
                    subtitle: "Appearance and display options"
                ) {
                    Toggle(isOn: $notchAlwaysVisible) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Always Show Recorder")
                            Text("Keep the notch recorder visible even when not recording")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Settings Section Component

struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let content: Content
    var showWarning: Bool = false

    init(icon: String, title: String, subtitle: String, showWarning: Bool = false, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showWarning = showWarning
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(showWarning ? .red : .accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(showWarning ? .red : .secondary)
                }
            }

            Divider()
                .padding(.vertical, 4)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}
