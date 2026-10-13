import Foundation

/// The real clock: `Date.now` and `Task.sleep` (continuous clock, so it keeps counting through
/// system sleep and a poll is due right after wake).
nonisolated struct SystemStoreClock: StoreClock {
    var now: Date { Date.now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: .continuous)
    }
}
