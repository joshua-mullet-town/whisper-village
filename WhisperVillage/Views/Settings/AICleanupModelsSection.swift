import SwiftUI

/// Settings section for AI Cleanup Models (filler/repetition removal)
struct AICleanupModelsSection: View {
    @StateObject private var modelManager = CleanupModelManager.shared

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
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: "brain")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Cleanup Models")
                    .font(.system(size: 16, weight: .bold))

                Text("Remove filler words and repetitions from transcriptions")
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
                    Color.indigo.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Model status rows
            modelStatusRow(
                name: "Filler Remover",
                description: "Removes \"um\", \"uh\", \"like\", etc.",
                status: modelManager.fillerModelStatus
            )

            modelStatusRow(
                name: "Repetition Remover",
                description: "Removes repeated words and phrases",
                status: modelManager.repetitionModelStatus
            )

            // Download progress
            if modelManager.downloadProgress > 0 && modelManager.downloadProgress < 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: modelManager.downloadProgress)
                        .progressViewStyle(.linear)

                    Text("Downloading models...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action button
            if !modelManager.modelsReady {
                Button(action: {
                    Task {
                        await modelManager.downloadModels()
                        CoreMLCleanupService.shared.reloadModels()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Download Models (\(modelManager.downloadSizeDescription))")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelManager.fillerModelStatus == .downloading ||
                         modelManager.repetitionModelStatus == .downloading)
            }
        }
        .padding(16)
    }

    // MARK: - Model Status Row

    private func modelStatusRow(
        name: String,
        description: String,
        status: CleanupModelManager.ModelStatus
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusBadge(for: status)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func statusBadge(for status: CleanupModelManager.ModelStatus) -> some View {
        switch status {
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

        case .notDownloaded:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Not Downloaded")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

        case .downloading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }

        case .downloaded:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(.green)
            }

        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}
