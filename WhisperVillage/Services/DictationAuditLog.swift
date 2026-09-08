import Foundation
import AppKit
import ApplicationServices

/// Persistent, crash-surviving audit trail for every dictation attempt.
///
/// Why this exists: dictation was failing silently. The app's only logging went to the
/// unified system log, where most values were redacted as `<private>` and older entries
/// aged out. When a transcription came back empty the app took a branch that pasted
/// nothing and logged nothing, so a failure was indistinguishable from "never recorded".
///
/// This writes a durable, human-readable line per attempt to a file Josh (and whoever is
/// debugging) can read afterwards without having had a console open at the time.
final class DictationAuditLog {
    static let shared = DictationAuditLog()

    /// ~/Library/Application Support/town.mullet.WhisperVillage/dictation-audit.log
    private let fileURL: URL
    /// Serial queue so concurrent attempts can't interleave a half-written line.
    private let queue = DispatchQueue(label: "town.mullet.WhisperVillage.audit")
    private let maxBytes = 5 * 1024 * 1024

    private lazy var timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("town.mullet.WhisperVillage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dictation-audit.log")
    }

    /// Where the log lives — surfaced in the UI so Josh can find it without asking.
    var path: String { fileURL.path }

    // MARK: - Writing

    func log(_ event: String, _ details: [String: Any] = [:]) {
        // Snapshot anything that must be read on the calling thread before hopping queues.
        let stamp = timestampFormatter.string(from: Date())
        let rendered = details.keys.sorted().map { "\($0)=\(describe(details[$0]!))" }.joined(separator: " ")
        let line = rendered.isEmpty ? "\(stamp) \(event)\n" : "\(stamp) \(event) \(rendered)\n"

        queue.async { [self] in
            append(line)
        }
    }

    /// Records a paste attempt with everything needed to tell the failure modes apart:
    /// whether the app was still trusted for keystrokes at that instant, which app was
    /// focused, which key path was used, and whether the transcript survived on the
    /// clipboard long enough to land.
    func logPasteAttempt(textLength: Int, method: String, axTrusted: Bool, frontmostBundleID: String) {
        log("PASTE_ATTEMPT", [
            "chars": textLength,
            "method": method,
            "axTrusted": axTrusted,
            "frontApp": frontmostBundleID,
        ])
    }

    private func append(_ line: String) {
        rotateIfNeeded()
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // First write, or the file was removed out from under us.
            try? data.write(to: fileURL)
        }
    }

    /// Keeps the file bounded. Josh's disk is near full, so this must never grow without limit.
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }

        let previous = fileURL.deletingLastPathComponent()
            .appendingPathComponent("dictation-audit.previous.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
    }

    private func describe(_ value: Any) -> String {
        if let s = value as? String {
            // Quote anything with spaces so the line stays machine-greppable.
            return s.contains(" ") || s.isEmpty ? "\"\(s)\"" : s
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let d = value as? Double { return String(format: "%.2f", d) }
        return "\(value)"
    }

    // MARK: - Ambient facts worth capturing at failure time

    /// Bundle id of whatever app would receive the keystrokes.
    static var frontmostBundleID: String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }

    /// The runtime accessibility answer, which can disagree with the stored TCC grant
    /// after a re-sign or restart. Captured at the moment of the attempt, not assumed.
    static var axTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Free space matters here: a full disk would break the recording writes.
    static var freeDiskMB: Int {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        guard let bytes = values?.volumeAvailableCapacity else { return -1 }
        return bytes / (1024 * 1024)
    }
}
