import Foundation

/// Time as the store sees it: wall-clock "now" (for `lastSync`, rate-limit deadlines and command
/// spacing) and cancellable sleeping. Injected so tests can drive time by hand and run instantly.
nonisolated protocol StoreClock: Sendable {
    var now: Date { get }
    /// Suspends for `duration`; throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}
