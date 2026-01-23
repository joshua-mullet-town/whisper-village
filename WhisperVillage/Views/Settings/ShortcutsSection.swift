import SwiftUI
import KeyboardShortcuts

/// Unified shortcuts section with main hotkey as the star
struct ShortcutsSection: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            contentView
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.3), Color.red.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: "command")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcuts")
                    .font(.system(size: 16, weight: .bold))

                Text("Control Whisper Village with keyboard shortcuts")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.08),
                    Color.red.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            mainHotkeySection
            Divider()
            quickActionsSection
        }
        .padding(16)
    }

    // MARK: - Main Hotkey

    private var mainHotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            mainHotkeyLabel
            mainHotkeyPicker
            usageHintsRow
        }
        .padding(16)
        .background(mainHotkeyBackground)
    }

    private var mainHotkeyLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text("Main Hotkey")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
    }

    private var mainHotkeyPicker: some View {
        HStack(spacing: 16) {
            Picker("", selection: $hotkeyManager.selectedHotkey1) {
                ForEach(HotkeyManager.HotkeyOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            if hotkeyManager.selectedHotkey1 == .custom {
                KeyboardShortcuts.Recorder(for: .toggleMiniRecorder)
                    .controlSize(.regular)
            }

            Spacer()
        }
    }

    private var mainHotkeyBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.orange.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
    }

    private var usageHintsRow: some View {
        HStack(spacing: 16) {
            usageHint(icon: "hand.tap", text: "Tap to start/stop")
            usageHint(icon: "hand.point.down", text: "Hold for push-to-talk")
        }
        .padding(.top, 4)
    }

    private func usageHint(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.orange.opacity(0.8))
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Actions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            ShortcutRow(
                name: "Paste Last",
                description: "Re-paste most recent transcription",
                shortcut: .pasteLastTranscription,
                icon: "doc.on.clipboard"
            )

            ShortcutRow(
                name: "Pause/Resume",
                description: "Pause recording, resume when pressed again",
                shortcut: .pauseResumeRecording,
                icon: "pause.circle"
            )

            ShortcutRow(
                name: "Peek",
                description: "Preview without stopping recording",
                shortcut: .peekTranscription,
                icon: "eye"
            )

            ShortcutRow(
                name: "Cancel",
                description: "Discard recording (default: double-tap Escape)",
                shortcut: .cancelRecorder,
                icon: "xmark.circle"
            )
        }
    }
}

// MARK: - Shortcut Row

private struct ShortcutRow: View {
    let name: String
    let description: String
    let shortcut: KeyboardShortcuts.Name
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            KeyboardShortcuts.Recorder(for: shortcut)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
