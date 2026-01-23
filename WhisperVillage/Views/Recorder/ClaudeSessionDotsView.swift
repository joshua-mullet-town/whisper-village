import SwiftUI

/// Shows a row of session cards below the notch representing Claude Code sessions
/// Designed to visually connect to the notch above it
struct ClaudeSessionDotsView: View {
    @ObservedObject var sessionManager: ClaudeSessionManager
    var isRecording: Bool = false  // Passed from parent to match notch state
    @Binding var isSummaryHidden: Bool  // Toggle summary visibility
    @State private var hoveredTab: Int?

    var body: some View {
        // TimelineView provides smooth, non-blocking time updates
        // Updates every second without manual timer management
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            HStack(spacing: 6) {
                ForEach(sessionManager.iTermTabs) { tab in
                    SessionCard(
                        status: sessionManager.statusForTab(tab.index),
                        isHovered: hoveredTab == tab.index,
                        isActive: sessionManager.activeTabIndex == tab.index,
                        projectName: tab.projectName,
                        updatedAt: sessionManager.updatedAtForTab(tab.index),
                        now: timeline.date
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredTab = hovering ? tab.index : nil
                        }
                    }
                    .onTapGesture {
                        if sessionManager.activeTabIndex == tab.index {
                            // Already on this tab - toggle summary visibility
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSummaryHidden.toggle()
                            }
                        } else {
                            // Different tab - switch to it and show summary
                            isSummaryHidden = false
                            switchToTab(tab.index)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(SessionBarBackground(isActive: isRecording))
        .contentShape(Rectangle())  // Entire session bar is clickable
    }

    private func switchToTab(_ index: Int) {
        // Simple and working: switch tab and activate iTerm2
        let script = """
        tell application "iTerm2"
            tell first window
                select tab \(index)
            end tell
            activate
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
        }
    }
}

/// Shape with flared top corners that match the original NotchShape "ear" style
/// The top corners curve outward like the original VoiceInk notch recorder
struct NotchHugShape: Shape {
    let topCornerRadius: CGFloat  // Size of the flared ear curves at top
    let bottomCornerRadius: CGFloat // Corner radius at bottom corners

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // This mirrors the original NotchShape from v1.9.1 which had "ears" that
        // flared outward at the top corners to match the MacBook notch aesthetic
        //
        // The shape starts at the top-left corner (0,0), curves inward/down,
        // then the left edge is inset by topCornerRadius

        // Start from the top left corner (at the very edge)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top left ear curve - curves outward then down
        // Control point pulls the curve toward the top edge, creating outward flare
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Left edge going down (inset from the outer edge by topCornerRadius)
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Bottom left corner (standard rounded)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom right corner (standard rounded)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right edge going up (inset from the outer edge by topCornerRadius)
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: topCornerRadius))

        // Top right ear curve - curves up then outward
        // Control point pulls the curve toward the top edge, creating outward flare
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

/// Background that matches the notch's state - orange when recording, dark when idle
struct SessionBarBackground: View {
    var isActive: Bool  // true = recording (orange), false = idle (dark)

    // Match the original notch shape proportions
    private let topRadius: CGFloat = 8
    private let bottomRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if isActive {
                // Recording state: orange gradient matching the notch
                NotchHugShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.4, blue: 0.1).opacity(0.85),
                                Color(red: 0.8, green: 0.2, blue: 0.1).opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                // Idle state: dark and subtle but visible
                NotchHugShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
                    .fill(Color.black.opacity(0.85))
            }
        }
        // No border/stroke - seamless connection with notch above
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

/// A single session card: project name on top, dot + time below
struct SessionCard: View {
    let status: ClaudeSessionStatus
    let isHovered: Bool
    let isActive: Bool  // Currently selected tab in iTerm
    let projectName: String
    let updatedAt: Date?
    let now: Date

    private var dotColor: Color {
        switch status {
        case .working:
            return .yellow
        case .waiting:
            return .green
        case .idle:
            return .gray.opacity(0.5)
        }
    }

    private var glowColor: Color {
        switch status {
        case .working:
            return .yellow
        case .waiting:
            return .green
        case .idle:
            return .clear
        }
    }

    private var bgColor: Color {
        if isHovered {
            return Color.white.opacity(0.2)
        }
        if isActive {
            return Color.white.opacity(0.12)
        }
        return Color.clear
    }

    /// Border color for active indicator
    private var borderColor: Color {
        if isActive {
            return Color.white.opacity(0.4)
        }
        return Color.clear
    }

    var body: some View {
        VStack(spacing: 2) {
            // Project name on top
            Text(abbreviatedName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)

            // Dot + time below
            HStack(spacing: 3) {
                // Status dot with glow
                ZStack {
                    if status != .idle {
                        Circle()
                            .fill(glowColor.opacity(0.5))
                            .frame(width: 12, height: 12)
                            .blur(radius: 3)
                    }
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                }

                // Time - always show
                Text(timeLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(timeColor)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(bgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    /// Abbreviated project name
    private var abbreviatedName: String {
        if projectName.count <= 12 {
            return projectName
        }
        // Show the end of the name (more likely to be unique/distinguishing)
        return "…" + String(projectName.suffix(10))
    }

    private var timeColor: Color {
        switch status {
        case .working:
            return .yellow.opacity(0.9)
        case .waiting:
            return .green.opacity(0.8)
        case .idle:
            return .white.opacity(0.4)
        }
    }

    private var timeLabel: String {
        guard let updatedAt = updatedAt else { return "—" }
        let elapsed = now.timeIntervalSince(updatedAt)

        if elapsed < 0 { return "—" }

        let seconds = Int(elapsed)
        let minutes = seconds / 60
        let hours = minutes / 60

        if hours > 0 {
            return String(format: "%dh%02dm", hours, minutes % 60)
        } else if minutes > 0 {
            return String(format: "%dm%02ds", minutes, seconds % 60)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

/// A "mini TV" panel that shows the current session's summary
/// Displays below the session dots, context-aware based on active tab
struct SummaryTVView: View {
    @ObservedObject var sessionManager: ClaudeSessionManager
    var isRecording: Bool = false

    /// The session for the currently active tab
    private var activeSession: ClaudeSession? {
        guard let activeIndex = sessionManager.activeTabIndex else { return nil }
        return sessionManager.sessionForTabIndex(activeIndex)
    }

    /// Parse structured summary from raw JSON string (fallback for older session files)
    private func parseSummaryFromJSON(_ summary: String) -> (user: String?, agent: String?)? {
        var cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences if present
        if cleanSummary.hasPrefix("```") {
            let lines = cleanSummary.components(separatedBy: "\n")
            var cleaned = lines
            if cleaned.first?.hasPrefix("```") == true {
                cleaned.removeFirst()
            }
            if cleaned.last?.trimmingCharacters(in: .whitespaces) == "```" {
                cleaned.removeLast()
            }
            cleanSummary = cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleanSummary.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return (
            user: json["user_summary"] as? String,
            agent: json["agent_summary"] as? String
        )
    }

    /// The active tab's project name
    private var activeProjectName: String? {
        guard let activeIndex = sessionManager.activeTabIndex,
              activeIndex > 0,
              activeIndex <= sessionManager.iTermTabs.count else { return nil }
        return sessionManager.iTermTabs[activeIndex - 1].projectName
    }

    var body: some View {
        VStack(spacing: 0) {
            if let session = activeSession {
                VStack(alignment: .leading, spacing: 4) {
                    // Header with project name
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))

                        Text(activeProjectName ?? "Session")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))

                        Spacer()

                        // Status indicator
                        Circle()
                            .fill(statusColor(for: session.status))
                            .frame(width: 6, height: 6)
                    }

                    // Summary content - expands to fit
                    if session.hasStructuredSummary {
                        StructuredSummaryContent(
                            userSummary: session.userSummary,
                            agentSummary: session.agentSummary
                        )
                    } else if let summary = session.summary, !summary.isEmpty {
                        if let parsed = parseSummaryFromJSON(summary) {
                            StructuredSummaryContent(
                                userSummary: parsed.user,
                                agentSummary: parsed.agent
                            )
                        } else {
                            LegacySummaryContent(summary: summary)
                        }
                    } else {
                        Text("Awaiting summary...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .italic()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            } else {
                // No active session
                HStack(spacing: 6) {
                    Image(systemName: "tv")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Text("No active session")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .background(SummaryTVBackground(isActive: isRecording))
    }

    private func statusColor(for status: ClaudeSessionStatus) -> Color {
        switch status {
        case .working: return .yellow
        case .waiting: return .green
        case .idle: return .gray.opacity(0.5)
        }
    }
}

/// Displays structured summary with USER and AGENT labels stacked on top
private struct StructuredSummaryContent: View {
    let userSummary: String?
    let agentSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let userSummary = userSummary, !userSummary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("USER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text(userSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let agentSummary = agentSummary, !agentSummary.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AGENT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Text(agentSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Displays legacy plain-text summary, parsing USER/AGENT lines if present
private struct LegacySummaryContent: View {
    let summary: String

    private var parsedLines: [(label: String?, text: String)] {
        var results: [(label: String?, text: String)] = []
        let lines = summary.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("USER asked") || trimmed.hasPrefix("USER:") {
                let text = trimmed
                    .replacingOccurrences(of: "USER asked:", with: "")
                    .replacingOccurrences(of: "USER asked", with: "")
                    .replacingOccurrences(of: "USER:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                results.append((label: "USER", text: text))
            } else if trimmed.hasPrefix("AGENT") {
                let text = trimmed
                    .replacingOccurrences(of: "AGENT:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                results.append((label: "AGENT", text: text))
            } else {
                results.append((label: nil, text: trimmed))
            }
        }

        return results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, item in
                if let label = item.label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(label == "USER" ? .cyan : .green)
                        Text(item.text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(item.text)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Background for the summary TV that matches the session bar style
struct SummaryTVBackground: View {
    var isActive: Bool
    private let cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.35, blue: 0.1).opacity(0.8),
                                Color(red: 0.75, green: 0.15, blue: 0.1).opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.8))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Active state (recording)
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange)
                .frame(width: 200, height: 30)

            HStack(spacing: 8) {
                SessionCard(status: .waiting, isHovered: false, isActive: true, projectName: "whisper-village",
                            updatedAt: Date().addingTimeInterval(-120), now: Date())
                SessionCard(status: .working, isHovered: true, isActive: false, projectName: "GiveGrove",
                            updatedAt: Date().addingTimeInterval(-45), now: Date())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SessionBarBackground(isActive: true))
        }

        // Idle state
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 30)

            HStack(spacing: 8) {
                SessionCard(status: .idle, isHovered: false, isActive: false, projectName: "whisper-village",
                            updatedAt: nil, now: Date())
                SessionCard(status: .waiting, isHovered: false, isActive: true, projectName: "GiveGrove",
                            updatedAt: Date().addingTimeInterval(-300), now: Date())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(SessionBarBackground(isActive: false))
        }
    }
    .padding()
    .background(Color.black)
}
