import Foundation

/// A one-shot "tell me when the recorder starts" hook that lives OUTSIDE
/// WhisperState.
///
/// Why it isn't just a property on WhisperState: that class is @MainActor, so
/// registering a callback on it from the HTTP server means touching main-actor
/// state from off-actor, and clearing it means a main-actor write from inside
/// recordingState's didSet mid-transition. That combination deadlocks the main
/// actor while the recorder is starting — verified by bisect: registering a
/// callback with a COMPLETELY EMPTY body was enough to wedge every request.
///
/// So this box is deliberately plain and actor-free. The didSet just calls
/// `fire`, which does nothing but read and clear a lock-protected closure.
final class RecordingStateWatch: @unchecked Sendable {
    static let shared = RecordingStateWatch()

    private let lock = NSLock()
    private var pending: (() -> Void)?

    private init() {}

    /// Run `body` once, the next time recording actually starts.
    func onNextRecordingStart(_ body: @escaping () -> Void) {
        lock.lock()
        pending = body
        lock.unlock()
    }

    /// Cancel a pending watch (e.g. the recorder never came up).
    func cancel() {
        lock.lock()
        pending = nil
        lock.unlock()
    }

    /// Called from recordingState's didSet. Must stay cheap: it runs on the
    /// main actor during a state transition.
    func fire(_ state: RecordingState) {
        guard state == .recording else { return }
        lock.lock()
        let body = pending
        pending = nil
        lock.unlock()
        body?()
    }
}
