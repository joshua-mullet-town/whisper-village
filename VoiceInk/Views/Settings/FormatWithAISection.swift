import SwiftUI
import KeyboardShortcuts

/// Dedicated settings section for Format with AI feature
struct FormatWithAISection: View {
    @State private var openAIAPIKey: String = UserDefaults.standard.string(forKey: "OpenAIAPIKey") ?? ""
    @State private var isKeyVisible: Bool = false
    @State private var selectedModel: GPT5Model = LLMFormattingService.shared.selectedModel
    @ObservedObject private var costTracker = FormattingCostTracker.shared

    private var hasAPIKey: Bool {
        !openAIAPIKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with gradient
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("AI Polish")
                            .font(.system(size: 16, weight: .bold))

                        if hasAPIKey {
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
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text("Setup Required")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(10)
                        }
                    }

                    Text("Format, rewrite, or translate your voice into any style")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.08),
                        Color.blue.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                // How it works
                VStack(alignment: .leading, spacing: 12) {
                    Text("How it works")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack(alignment: .top, spacing: 16) {
                        stepView(number: "1", title: "Record", description: "Speak your content normally")
                        stepView(number: "2", title: "Transform", description: "Press shortcut, say what to do")
                        stepView(number: "3", title: "Done", description: "AI transforms and pastes it")
                    }
                }

                Divider()

                // Model Selection
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        Text("Model")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()
                    }

                    Picker("", selection: $selectedModel) {
                        ForEach(GPT5Model.allCases) { model in
                            Text("\(model.displayName) \(model.costIndicator)")
                                .tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedModel) { _, newValue in
                        LLMFormattingService.shared.selectedModel = newValue
                    }

                    // Model details
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedModel.description)
                                .font(.system(size: 11))
                                .foregroundColor(.primary.opacity(0.8))
                            Text(selectedModel.formattedPricing)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
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

                    KeyboardShortcuts.Recorder(for: .formatWithLLM)
                        .controlSize(.small)

                    Spacer()
                }

                Divider()

                // API Key
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        Text("OpenAI API Key")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        if hasAPIKey {
                            Button(action: { isKeyVisible.toggle() }) {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Group {
                            if isKeyVisible {
                                TextField("sk-...", text: $openAIAPIKey)
                            } else {
                                SecureField("sk-...", text: $openAIAPIKey)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: openAIAPIKey) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "OpenAIAPIKey")
                        }

                        if hasAPIKey {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.green)
                        }
                    }

                    if !hasAPIKey {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                            Text("Get your API key from")
                                .font(.system(size: 11))
                            Link("platform.openai.com", destination: URL(string: "https://platform.openai.com/api-keys")!)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                }

                // Cost Tracking (only show if there's usage)
                if hasAPIKey {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 20)

                            Text("Formatting Costs")
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            if costTracker.requestCountAllTime > 0 {
                                Text("\(costTracker.requestCountAllTime) requests")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if costTracker.requestCountAllTime == 0 {
                            Text("No usage yet")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 6) {
                                costRow(label: "Last hour", cost: costTracker.costLastHour)
                                costRow(label: "Last 24 hours", cost: costTracker.costLastDay)
                                costRow(label: "Last 7 days", cost: costTracker.costLastWeek)
                                costRow(label: "Last 30 days", cost: costTracker.costLastMonth)
                                Divider()
                                costRow(label: "All time", cost: costTracker.costAllTime, bold: true)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                }

                // Examples
                if hasAPIKey {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Examples")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            exampleRow(icon: "text.quote", instruction: "\"Make this a professional email\"")
                            exampleRow(icon: "globe", instruction: "\"Translate to Japanese\"")
                            exampleRow(icon: "list.bullet", instruction: "\"Turn this into bullet points\"")
                            exampleRow(icon: "textformat", instruction: "\"Fix grammar and punctuation\"")
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func stepView(number: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.purple)
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

    private func costRow(label: String, cost: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: bold ? .semibold : .regular))
                .foregroundColor(bold ? .primary : .secondary)

            Spacer()

            Text(formatCost(cost))
                .font(.system(size: 11, weight: bold ? .semibold : .medium))
                .foregroundColor(bold ? .primary : .primary.opacity(0.8))
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else if cost < 1.0 {
            return String(format: "$%.3f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    private func exampleRow(icon: String, instruction: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.purple)
                .frame(width: 16)

            Text(instruction)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.8))
        }
    }
}

#Preview {
    FormatWithAISection()
        .padding()
        .frame(width: 500)
}
