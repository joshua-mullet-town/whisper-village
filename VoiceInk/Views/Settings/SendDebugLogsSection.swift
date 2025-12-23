import SwiftUI

/// A friendly section for users to send debug logs when they have issues
struct SendDebugLogsSection: View {
    @State private var userName: String = ""
    @State private var isSending: Bool = false
    @State private var showSuccess: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        SettingsSection(
            icon: "ladybug.fill",
            title: "Having Issues?",
            subtitle: "Send debug info to help us fix it"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Explanation
                Text("If something isn't working right, tap the button below to send your debug logs directly to Joshua. This helps us understand what's happening on your machine.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // What gets sent
                VStack(alignment: .leading, spacing: 4) {
                    Text("What gets sent:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Label("App settings", systemImage: "gearshape")
                        Label("Recent logs", systemImage: "doc.text")
                        Label("System info", systemImage: "desktopcomputer")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }

                Divider()

                // Name field (optional)
                HStack(spacing: 12) {
                    Text("Your name (optional)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    TextField("Anonymous", text: $userName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: 150)
                }

                // Send button
                HStack {
                    Button(action: sendLogs) {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isSending ? "Sending..." : "Send Debug Logs to Joshua")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSending ? Color.gray : Color.accentColor)
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isSending)

                    // Copy to clipboard as fallback
                    Button(action: copyToClipboard) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.2))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Copy debug info to clipboard")
                }

                // Success message
                if showSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Sent! Thanks for helping us improve.")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Error message
                if showError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func sendLogs() {
        isSending = true
        showSuccess = false
        showError = false

        DebugLogCollector.shared.sendToSlack(userName: userName.isEmpty ? nil : userName) { result in
            DispatchQueue.main.async {
                isSending = false

                switch result {
                case .success:
                    withAnimation {
                        showSuccess = true
                    }
                    // Auto-hide after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showSuccess = false
                        }
                    }
                case .failure(let error):
                    withAnimation {
                        showError = true
                        errorMessage = "Couldn't send. Try copying to clipboard instead."
                    }
                    print("Debug log send failed: \(error)")
                    // Auto-hide after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showError = false
                        }
                    }
                }
            }
        }
    }

    private func copyToClipboard() {
        DebugLogCollector.shared.copyToClipboard()

        // Show brief feedback
        withAnimation {
            showSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSuccess = false
            }
        }
    }
}
