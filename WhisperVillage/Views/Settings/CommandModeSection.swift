import SwiftUI
import KeyboardShortcuts

/// Settings section for Command Mode - voice-activated system navigation
struct CommandModeSection: View {
    @AppStorage("CommandModeEnabled") private var isCommandModeEnabled = false
    @StateObject private var ollamaStatus = OllamaStatusChecker()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with gradient
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
                    HStack(spacing: 8) {
                        Text("Command Mode")
                            .font(.system(size: 16, weight: .bold))

                        if isCommandModeEnabled && ollamaStatus.isRunning {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Ready")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(10)
                        } else if isCommandModeEnabled && !ollamaStatus.isRunning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text("Ollama Required")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(10)
                        }
                    }

                    Text("Voice-activated app switching and navigation")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isCommandModeEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
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

            if isCommandModeEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 20) {
                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How it works")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack(alignment: .top, spacing: 16) {
                            stepView(number: "1", title: "Trigger", description: "Press shortcut")
                            stepView(number: "2", title: "Speak", description: "Say app or tab name")
                            stepView(number: "3", title: "Navigate", description: "System switches focus")
                        }
                    }

                    Divider()

                    // Shortcut
                    HStack(spacing: 12) {
                        Image(systemName: "command")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        Text("Shortcut")
                            .font(.system(size: 13, weight: .medium))

                        KeyboardShortcuts.Recorder(for: .commandMode)
                            .controlSize(.small)

                        Spacer()
                    }

                    Divider()

                    // Ollama Status
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            Text("Local AI (Ollama)")
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(ollamaStatus.isRunning ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(ollamaStatus.isRunning ? "Running" : "Not Running")
                                    .font(.system(size: 11))
                                    .foregroundColor(ollamaStatus.isRunning ? .green : .red)
                            }
                        }

                        if !ollamaStatus.isRunning {
                            HStack(spacing: 10) {
                                Button(action: {
                                    ollamaStatus.startOllama()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10))
                                        Text("Start Ollama")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)

                                Text("Required for command interpretation")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                Text("Model: \(ollamaStatus.modelName)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)

                    // Examples
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Examples")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            exampleRow(command: "\"Terminal\"", action: "Opens iTerm2")
                            exampleRow(command: "\"Chrome\"", action: "Opens Google Chrome")
                            exampleRow(command: "\"Second terminal tab\"", action: "Switches to tab 2")
                            exampleRow(command: "\"Slack\"", action: "Opens Slack")
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
            }
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
        .onAppear {
            ollamaStatus.checkStatus()
        }
    }

    private func stepView(number: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.orange)
                    .cornerRadius(9)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exampleRow(command: String, action: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.orange)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Text(action)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.8))

            Spacer()
        }
    }
}

// MARK: - Ollama Status Checker

class OllamaStatusChecker: ObservableObject {
    @Published var isRunning = false
    @Published var modelName = "llama3.2:3b"

    private let ollamaClient = OllamaClient.shared

    func checkStatus() {
        Task {
            let running = await ollamaClient.healthCheck()
            await MainActor.run {
                self.isRunning = running
            }
        }
    }

    func startOllama() {
        // Try to start Ollama via CLI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            StreamingLogger.shared.log("🦙 Started Ollama server")

            // Check status after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.checkStatus()
            }
        } catch {
            StreamingLogger.shared.log("🦙 Failed to start Ollama: \(error)")
        }
    }
}

#Preview {
    CommandModeSection()
        .padding()
        .frame(width: 500)
}
