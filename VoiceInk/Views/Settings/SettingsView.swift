import SwiftUI
import Cocoa
import KeyboardShortcuts
import LaunchAtLogin
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var whisperState: WhisperState
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @StateObject private var deviceManager = AudioDeviceManager.shared
    @ObservedObject private var mediaController = MediaController.shared
    @ObservedObject private var playbackController = PlaybackController.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true
    @AppStorage("NotchAlwaysVisible") private var notchAlwaysVisible = true
    @State private var showResetOnboardingAlert = false
    @State private var currentShortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)
    @State private var isDataSectionExpanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Transcription Model - Simple dropdown (moved from Voice Engine)
                TranscriptionModelSection()

                // Shortcuts - Main hotkey + quick actions
                ShortcutsSection()

                // AI Polish - Dedicated exciting section with provider selection
                FormatWithAISection()

                // Command Mode - Voice-activated navigation
                CommandModeSection()

                // Recording Feedback - Sounds and audio behavior
                RecordingFeedbackSection()

                // Live Preview - How transcription is displayed while recording
                LivePreviewSection()

                // Auto Formatting - Text cleanup and formatting
                AutoFormattingSection()

                // Experimental - Beta features
                ExperimentalFeaturesSection()

                // Claude Code - Developer tools
                ClaudeCodeSection()

                // Visual - Appearance settings
                VisualSection(
                    notchAlwaysVisible: $notchAlwaysVisible,
                    menuBarManager: menuBarManager
                )

                // General - Startup and updates
                GeneralSection(
                    autoUpdateCheck: $autoUpdateCheck,
                    showResetOnboardingAlert: $showResetOnboardingAlert,
                    updaterViewModel: updaterViewModel
                )

                // Debug Logs - Help us fix issues
                SendDebugLogsSection()

                // Data & Privacy - Collapsible at bottom
                DataPrivacySection(
                    isExpanded: $isDataSectionExpanded,
                    enhancementService: enhancementService,
                    whisperState: whisperState,
                    hotkeyManager: hotkeyManager,
                    menuBarManager: menuBarManager
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboarding = false
                }
            }
        } message: {
            Text("Are you sure you want to reset the onboarding? You'll see the introduction screens again the next time you launch the app.")
        }
    }
}

// MARK: - Recording Feedback Section

struct RecordingFeedbackSection: View {
    @ObservedObject private var mediaController = MediaController.shared

    var body: some View {
        SettingsSection(
            icon: "speaker.wave.2.bubble.left.fill",
            title: "Recording Feedback",
            subtitle: "Sounds and audio behavior"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: .init(
                    get: { SoundManager.shared.isEnabled },
                    set: { SoundManager.shared.isEnabled = $0 }
                )) {
                    Text("Sound feedback")
                }
                .toggleStyle(.switch)

                if SoundManager.shared.isEnabled {
                    SoundThemePicker()
                }

                Toggle(isOn: $mediaController.isSystemMuteEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mute system audio during recording")
                        Text("Automatically mute and restore when done")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
}

// MARK: - Live Preview Section

struct LivePreviewSection: View {
    @AppStorage("LivePreviewEnabled") private var isLivePreviewEnabled = true
    @AppStorage("LivePreviewStyle") private var livePreviewStyle = "box"

    var body: some View {
        SettingsSection(
            icon: "text.bubble.fill",
            title: "Live Preview",
            subtitle: "See your transcription as you speak"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isLivePreviewEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Live Preview")
                        Text(isLivePreviewEnabled
                            ? "Transcription updates in real-time as you speak"
                            : "Transcription only appears when you stop recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if isLivePreviewEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview Style")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $livePreviewStyle) {
                            Text("Ticker").tag("ticker")
                            Text("Box").tag("box")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 180)

                        if livePreviewStyle == "ticker" {
                            HStack(spacing: 6) {
                                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                    .foregroundColor(.secondary)
                                Text("Horizontal scrolling text below the recorder")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.on.rectangle")
                                    .foregroundColor(.secondary)
                                Text("Draggable floating box with adjustable size")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Auto Formatting Section

struct AutoFormattingSection: View {
    @AppStorage("SmartCapitalizationEnabled") private var isSmartCapitalizationEnabled = true
    @AppStorage("AutoEndPunctuationEnabled") private var isAutoEndPunctuationEnabled = true
    @AppStorage("IsMLCleanupEnabled") private var isMLCleanupEnabled = false
    @AppStorage("MLCleanupFillerEnabled") private var isFillerEnabled = true
    @AppStorage("MLCleanupRepetitionEnabled") private var isRepetitionEnabled = true

    var body: some View {
        SettingsSection(
            icon: "textformat.abc",
            title: "Auto Formatting",
            subtitle: "Automatic text cleanup and formatting"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $isSmartCapitalizationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Capitalization")
                        Text("Lowercase first word when pasting mid-sentence")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $isAutoEndPunctuationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto End Punctuation")
                        Text("Add period if transcription has no ending punctuation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                // ML Cleanup
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $isMLCleanupEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("ML Cleanup")
                                Text("Beta")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                            Text("Use local ML models to clean up transcriptions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if isMLCleanupEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: $isFillerEnabled) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Remove Fillers")
                                        .font(.subheadline)
                                    Text("uh, um, er, like → removed")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)

                            Toggle(isOn: $isRepetitionEnabled) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Remove Repetitions")
                                        .font(.subheadline)
                                    Text("I I I think → I think")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Visual Section

struct VisualSection: View {
    @Binding var notchAlwaysVisible: Bool
    @ObservedObject var menuBarManager: MenuBarManager

    var body: some View {
        SettingsSection(
            icon: "sparkles.rectangle.stack.fill",
            title: "Visual",
            subtitle: "Appearance and display options"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $notchAlwaysVisible) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Always Show Recorder")
                        Text("Keep the notch recorder visible even when not recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $menuBarManager.isMenuBarOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide Dock Icon")
                        Text("Run as a menu bar only app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
}

// MARK: - General Section

struct GeneralSection: View {
    @Binding var autoUpdateCheck: Bool
    @Binding var showResetOnboardingAlert: Bool
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        SettingsSection(
            icon: "gearshape.fill",
            title: "General",
            subtitle: "Startup and updates"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LaunchAtLogin.Toggle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("Start Whisper Village when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $autoUpdateCheck) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Updates")
                        Text("Check for updates in the background")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: autoUpdateCheck) { _, newValue in
                    updaterViewModel.toggleAutoUpdates(newValue)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(action: {
                        updaterViewModel.checkForUpdates()
                    }) {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!updaterViewModel.canCheckForUpdates)

                    Button(action: {
                        showResetOnboardingAlert = true
                    }) {
                        Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }
}

// MARK: - Data & Privacy Section (Collapsible)

struct DataPrivacySection: View {
    @Binding var isExpanded: Bool
    @ObservedObject var enhancementService: AIEnhancementService
    @ObservedObject var whisperState: WhisperState
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var menuBarManager: MenuBarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible, clickable to expand
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data & Privacy")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("History, storage, import/export")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    // Audio Cleanup Settings
                    AudioCleanupSettingsView()

                    Divider()

                    // Import/Export
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data Management")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("Export your custom prompts, power modes, word replacements, keyboard shortcuts, and app preferences. API keys are not included.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                ImportExportService.shared.importSettings(
                                    enhancementService: enhancementService,
                                    whisperPrompt: whisperState.whisperPrompt,
                                    hotkeyManager: hotkeyManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: MediaController.shared,
                                    playbackController: PlaybackController.shared,
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Import...", systemImage: "arrow.down.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.regular)

                            Button {
                                ImportExportService.shared.exportSettings(
                                    enhancementService: enhancementService,
                                    whisperPrompt: whisperState.whisperPrompt,
                                    hotkeyManager: hotkeyManager,
                                    menuBarManager: menuBarManager,
                                    mediaController: MediaController.shared,
                                    playbackController: PlaybackController.shared,
                                    soundManager: SoundManager.shared,
                                    whisperState: whisperState
                                )
                            } label: {
                                Label("Export...", systemImage: "arrow.up.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .controlSize(.regular)
                        }
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: false, useAccentGradientWhenSelected: true))
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
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

                if showWarning {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .help("Permission required for Whisper Village to function properly")
                }
            }

            Divider()
                .padding(.vertical, 4)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(isSelected: showWarning, useAccentGradientWhenSelected: true))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(showWarning ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Sound Pickers

struct SoundThemePicker: View {
    @ObservedObject private var soundManager = SoundManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoundEventPicker(
                label: "Start recording",
                icon: "record.circle",
                options: SoundOption.forStart,
                selection: Binding(
                    get: { soundManager.startSoundOption },
                    set: { soundManager.startSoundOption = $0 }
                )
            )

            SoundEventPicker(
                label: "Stop recording",
                icon: "stop.circle",
                options: SoundOption.forStop,
                selection: Binding(
                    get: { soundManager.stopSoundOption },
                    set: { soundManager.stopSoundOption = $0 }
                )
            )

            SoundEventPicker(
                label: "Cancel / Escape",
                icon: "xmark.circle",
                options: SoundOption.forCancel,
                selection: Binding(
                    get: { soundManager.cancelSoundOption },
                    set: { soundManager.cancelSoundOption = $0 }
                )
            )

            SoundEventPicker(
                label: "Send (paste + enter)",
                icon: "paperplane.circle",
                options: SoundOption.forSend,
                selection: Binding(
                    get: { soundManager.sendSoundOption },
                    set: { soundManager.sendSoundOption = $0 }
                )
            )
        }
        .padding(.top, 4)
    }
}

struct SoundEventPicker: View {
    let label: String
    let icon: String
    let options: [SoundOption]
    @Binding var selection: SoundOption

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
            }
            .frame(width: 120, alignment: .leading)

            Picker("", selection: $selection) {
                ForEach(options) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .onChange(of: selection) { _, newValue in
                SoundManager.shared.preview(newValue)
            }

            Button(action: {
                SoundManager.shared.preview(selection)
            }) {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(selection == .none)
            .opacity(selection == .none ? 0.3 : 1)
            .help("Preview sound")
        }
    }
}

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
