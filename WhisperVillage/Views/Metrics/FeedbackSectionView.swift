import SwiftUI
import AppKit

struct FeedbackSectionView: View {
    // Debug logs state
    @State private var isSendingReport = false
    @State private var showReportSuccess = false
    @State private var showDebugPopover = false
    @State private var userEmail = ""

    // Bug report state
    @State private var isSendingBug = false
    @State private var showBugSuccess = false
    @State private var showBugPopover = false
    @State private var bugDescription = ""

    // Feature request state
    @State private var isSendingFeature = false
    @State private var showFeatureSuccess = false
    @State private var showFeaturePopover = false
    @State private var featureDescription = ""

    @State private var showCopiedMessage = false

    /// Feedback webhook URL (loaded from secrets.plist)
    private var feedbackWebhookURL: String? = {
        if let secretsPath = Bundle.main.path(forResource: "secrets", ofType: "plist"),
           let secrets = NSDictionary(contentsOfFile: secretsPath),
           let url = secrets["FeedbackWebhookURL"] as? String, !url.isEmpty {
            return url
        }
        return nil
    }()

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundColor(.secondary)
                Text("HELP US IMPROVE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Three action cards
            HStack(spacing: 12) {
                // Report a Bug
                FeedbackCard(
                    icon: "ladybug.fill",
                    title: "Report a Bug",
                    description: "Something not working?",
                    color: .red,
                    isLoading: isSendingBug,
                    showSuccess: showBugSuccess
                ) {
                    showBugPopover = true
                }
                .popover(isPresented: $showBugPopover, arrowEdge: .top) {
                    bugReportPopover
                }

                // Request a Feature
                FeedbackCard(
                    icon: "lightbulb.fill",
                    title: "Request Feature",
                    description: "Have an idea?",
                    color: .yellow,
                    isLoading: isSendingFeature,
                    showSuccess: showFeatureSuccess
                ) {
                    showFeaturePopover = true
                }
                .popover(isPresented: $showFeaturePopover, arrowEdge: .top) {
                    featureRequestPopover
                }

                // Send Debug Logs
                FeedbackCard(
                    icon: "doc.text.fill",
                    title: "Send Debug Logs",
                    description: "Help diagnose issues",
                    color: .blue,
                    isLoading: isSendingReport,
                    showSuccess: showReportSuccess
                ) {
                    showDebugPopover = true
                }
                .popover(isPresented: $showDebugPopover, arrowEdge: .top) {
                    debugLogsPopover
                }
            }

            // Email contact
            HStack(spacing: 6) {
                Text("Or email directly:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button(action: {
                    copyEmailToClipboard()
                }) {
                    Text("joshua@mullet.town")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                if showCopiedMessage {
                    Text("Copied!")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 2)
        .animation(.easeInOut(duration: 0.2), value: showCopiedMessage)
    }

    // MARK: - Popovers

    private var bugReportPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a Bug")
                .font(.headline)

            Text("Describe what's not working. Include steps to reproduce if possible.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $bugDescription)
                .font(.system(size: 12))
                .frame(width: 260, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    showBugPopover = false
                    bugDescription = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    showBugPopover = false
                    sendBugReport()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var featureRequestPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request a Feature")
                .font(.headline)

            Text("What would make Whisper Village better for you?")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $featureDescription)
                .font(.system(size: 12))
                .frame(width: 260, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    showFeaturePopover = false
                    featureDescription = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    showFeaturePopover = false
                    sendFeatureRequest()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Send")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .disabled(featureDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var debugLogsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Debug Report")
                .font(.headline)

            Text("This sends your app settings and recent logs to help diagnose the issue.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Your email (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("email@example.com", text: $userEmail)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 220)
                Text("So I can follow up if needed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Cancel") {
                    showDebugPopover = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    showDebugPopover = false
                    sendDebugReport()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Send Report")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Actions

    private func sendBugReport() {
        guard !bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSendingBug = true
        showBugSuccess = false

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let macOS = ProcessInfo.processInfo.operatingSystemVersionString

        sendFeedbackToSlack(
            type: "Bug Report",
            emoji: ":ladybug:",
            color: "#FF3B30",
            content: bugDescription,
            metadata: "App: \(appVersion) | macOS: \(macOS)"
        ) { success in
            DispatchQueue.main.async {
                isSendingBug = false
                if success {
                    bugDescription = ""
                    withAnimation { showBugSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { showBugSuccess = false }
                    }
                }
            }
        }
    }

    private func sendFeatureRequest() {
        guard !featureDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSendingFeature = true
        showFeatureSuccess = false

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        sendFeedbackToSlack(
            type: "Feature Request",
            emoji: ":bulb:",
            color: "#FFCC00",
            content: featureDescription,
            metadata: "App: \(appVersion)"
        ) { success in
            DispatchQueue.main.async {
                isSendingFeature = false
                if success {
                    featureDescription = ""
                    withAnimation { showFeatureSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { showFeatureSuccess = false }
                    }
                }
            }
        }
    }

    private func sendFeedbackToSlack(type: String, emoji: String, color: String, content: String, metadata: String, completion: @escaping (Bool) -> Void) {
        guard let webhookURL = feedbackWebhookURL, let url = URL(string: webhookURL) else {
            completion(false)
            return
        }

        let slackMessage: [String: Any] = [
            "text": "\(emoji) \(type)",
            "attachments": [
                [
                    "color": color,
                    "blocks": [
                        [
                            "type": "section",
                            "text": [
                                "type": "mrkdwn",
                                "text": content
                            ]
                        ],
                        [
                            "type": "context",
                            "elements": [
                                [
                                    "type": "mrkdwn",
                                    "text": metadata
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: slackMessage)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }

    private func sendDebugReport() {
        isSendingReport = true
        showReportSuccess = false

        let identifier = userEmail.isEmpty ? nil : userEmail

        DebugLogCollector.shared.sendToSlack(userName: identifier) { result in
            DispatchQueue.main.async {
                isSendingReport = false

                switch result {
                case .success:
                    withAnimation {
                        showReportSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showReportSuccess = false
                        }
                    }
                case .failure:
                    DebugLogCollector.shared.copyToClipboard()
                    withAnimation {
                        showCopiedMessage = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            showCopiedMessage = false
                        }
                    }
                }
            }
        }
    }

    private func copyEmailToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("joshua@mullet.town", forType: .string)

        withAnimation {
            showCopiedMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedMessage = false
            }
        }
    }
}

// MARK: - Feedback Card Component

struct FeedbackCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    var isLoading: Bool = false
    var showSuccess: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else if showSuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundColor(color)
                    }
                }
                .frame(height: 28)

                // Title
                Text(showSuccess ? "Sent!" : title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                // Description
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? color.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading || showSuccess)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
