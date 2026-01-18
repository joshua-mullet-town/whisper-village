import SwiftUI

/// Popover for managing Space-to-iTerm Tab bindings
struct SpaceTabPopover: View {
    @ObservedObject var spaceTabManager: SpaceTabManager
    @State private var linkResult: LinkResult?

    enum LinkResult {
        case success(String)
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)

                Text("Space \u{2192} iTerm Tab")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            // Current Space indicator
            HStack {
                Text("Current Space:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(spaceTabManager.currentSpaceID)")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.medium)

                if spaceTabManager.hasBindingForCurrentSpace {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }

            Divider()

            // Link button
            Button(action: linkCurrentSpaceAndTab) {
                HStack {
                    Image(systemName: "link.badge.plus")
                    Text("Link Current Space + Tab")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!spaceTabManager.isiTermRunning())

            if !spaceTabManager.isiTermRunning() {
                Text("iTerm2 is not running")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Result message
            if let result = linkResult {
                HStack {
                    switch result {
                    case .success(let msg):
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .foregroundColor(.green)
                    case .error(let msg):
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(msg)
                            .foregroundColor(.red)
                    }
                }
                .font(.caption)
                .transition(.opacity)
            }

            // Existing bindings
            if !spaceTabManager.bindings.isEmpty {
                Divider()

                Text("Linked Spaces")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(spaceTabManager.bindings.values.sorted(by: { $0.spaceID < $1.spaceID })) { binding in
                            SpaceTabBindingRow(
                                binding: binding,
                                isCurrentSpace: binding.spaceID == spaceTabManager.currentSpaceID,
                                onDelete: {
                                    withAnimation {
                                        spaceTabManager.removeBinding(spaceID: binding.spaceID)
                                    }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)

                Divider()

                // Reset all button
                Button(action: {
                    withAnimation {
                        spaceTabManager.resetAllBindings()
                        linkResult = nil
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Reset All")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            // Enable/disable toggle
            Divider()

            Toggle(isOn: $spaceTabManager.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-switch tabs")
                        .font(.subheadline)
                    Text("Switch iTerm tab when changing spaces")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            // Refresh current space ID when popover appears
            spaceTabManager.currentSpaceID = spaceTabManager.getCurrentSpaceID()
        }
    }

    private func linkCurrentSpaceAndTab() {
        let success = spaceTabManager.linkCurrentSpaceAndTab()

        withAnimation {
            if success {
                if let binding = spaceTabManager.bindings[spaceTabManager.currentSpaceID] {
                    linkResult = .success("Linked to '\(binding.tabName)'")
                } else {
                    linkResult = .success("Linked!")
                }
            } else {
                linkResult = .error("Failed to link. Is iTerm2 open?")
            }
        }

        // Clear result after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                linkResult = nil
            }
        }
    }
}

/// Row showing a single Space-to-Tab binding
struct SpaceTabBindingRow: View {
    let binding: SpaceTabBinding
    let isCurrentSpace: Bool
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Space indicator
            HStack(spacing: 4) {
                if isCurrentSpace {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
                Text("Space \(binding.spaceID)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(isCurrentSpace ? .semibold : .regular)
            }
            .frame(width: 70, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Tab name
            Text(binding.tabName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isHovered ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrentSpace ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
