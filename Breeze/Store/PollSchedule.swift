/// The polling interval with the 1306 back-off: each rate-limit doubles the interval (starting
/// from the base) up to 15 minutes; the next successful fetch resets it.
///
/// `base` is the configured interval (`AppSettings.pollInterval`, already clamped to 60…600 s),
/// passed in on every call so a settings change applies without copying it here.
nonisolated struct PollSchedule: Equatable, Sendable {
    static let maximumBackoff: Duration = .seconds(15 * 60)

    private(set) var backoff: Duration?

    /// How long to wait before the next poll.
    func interval(base: Duration) -> Duration {
        backoff ?? base
    }

    /// Doubles the interval; returns the new one.
    mutating func recordRateLimit(base: Duration) -> Duration {
        let doubled = interval(base: base) * 2
        let next = min(doubled, Self.maximumBackoff)
        backoff = next
        return next
    }

    mutating func recordSuccess() {
        backoff = nil
    }
}
