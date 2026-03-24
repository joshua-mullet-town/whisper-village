import SwiftUI
import SwiftData
import KeyboardShortcuts

struct ContentView: View {
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var hotkeyManager: HotkeyManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats bar
                DashboardStatsView()

                // Model selection
                ModelPickerSection()
                    .environmentObject(whisperState)

                // Hotkey configuration
                HotkeySection()
                    .environmentObject(hotkeyManager)

                // History
                HistorySection()
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Stats

struct DashboardStatsView: View {
    @Query private var transcriptions: [Transcription]

    private var todayCount: Int {
        let calendar = Calendar.current
        return transcriptions.filter { calendar.isDateInToday($0.timestamp) }.count
    }

    var body: some View {
        HStack(spacing: 16) {
            StatCard(title: "Today", value: "\(todayCount)", icon: "waveform")
            StatCard(title: "Total", value: "\(transcriptions.count)", icon: "clock.arrow.circlepath")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Model Picker

struct ModelPickerSection: View {
    @EnvironmentObject var whisperState: WhisperState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transcription Model", systemImage: "cpu")
                .font(.headline)

            Picker("", selection: Binding(
                get: { whisperState.currentTranscriptionModel?.id },
                set: { newId in
                    if let newId, let model = whisperState.allAvailableModels.first(where: { $0.id == newId }) {
                        Task { await whisperState.setDefaultTranscriptionModel(model) }
                    }
                }
            )) {
                Text("None").tag(nil as UUID?)
                ForEach(whisperState.allAvailableModels, id: \.id) { model in
                    Text("\(model.displayName) (\(model.provider.rawValue))").tag(model.id as UUID?)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Hotkey

struct HotkeySection: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hotkeys", systemImage: "keyboard")
                .font(.headline)

            // Main recording hotkey
            HStack {
                Text("Record / Stop")
                Spacer()
                Text(hotkeyManager.selectedHotkey1.displayName)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }

            Picker("Change hotkey:", selection: $hotkeyManager.selectedHotkey1) {
                ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)

            Divider()

            // Paste last transcription
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste Last")
                    Text("Re-paste most recent transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                KeyboardShortcuts.Recorder(for: .pasteLastTranscription)
            }

            // Send It (paste + Enter)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send It")
                    Text("Paste + press Enter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                KeyboardShortcuts.Recorder(for: .sendIt)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - History

struct HistorySection: View {
    @Query(sort: \Transcription.timestamp, order: .reverse) private var transcriptions: [Transcription]
    @State private var expandedId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(transcriptions.count) transcriptions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if transcriptions.isEmpty {
                Text("No transcriptions yet. Press \(Image(systemName: "command")) Right Command to record.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(transcriptions.prefix(100)) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatDate(t.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let model = t.transcriptionModelName {
                                    Text(model)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(t.text, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Copy")
                            }

                            Text(t.text)
                                .font(.system(size: 13))
                                .lineLimit(expandedId == t.id ? nil : 2)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        expandedId = expandedId == t.id ? nil : t.id
                                    }
                                }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(expandedId == t.id ? Color.primary.opacity(0.03) : Color.clear)

                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: date)
    }
}
