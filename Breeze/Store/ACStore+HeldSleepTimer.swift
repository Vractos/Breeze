import Foundation
import ThinQKit

extension ACStore {
    /// A sleep-timer write LG accepted. The state reflects sleep writes only ~1–2 min later
    /// (observed on a real unit), so the store keeps this applied on top of fetched states until one
    /// agrees or `stateLag` passes; otherwise the post-command refresh would show the
    /// old timer again.
    nonisolated struct HeldSleepTimer: Sendable, Equatable {
        /// The duration written; `nil` for a cancel.
        let minutes: Int?
        let postedAt: Date

        /// Longer than the ~1–2 min lag seen on a real unit; after it the fetched state wins
        /// again (e.g. the timer was changed in the LG app meanwhile).
        static let stateLag: Duration = .seconds(180)

        /// LG rounds the remaining time to whole minutes, and the write lands a moment after the
        /// POST returns, so a reported value may sit a little either side of the countdown.
        private static let countdownSlackMinutes = 2.0

        var command: ACCommand { .sleepTimer(minutes: minutes) }

        func hasExpired(at now: Date) -> Bool {
            now.timeIntervalSince(postedAt) >= Self.stateLag.timeInterval
        }

        /// Whether `reported` already shows this write: `.off` for a cancel; for a new timer,
        /// running with a remaining time that fits a countdown from `minutes` started at
        /// `postedAt`. Gotcha: a timer set earlier that happens to be at the same point of its
        /// countdown also agrees; the panel then shows the same value either way.
        func isReflected(by reported: SleepTimerState?, at now: Date) -> Bool {
            guard let minutes else { return reported == .off }
            guard case .set(let remaining)? = reported else { return false }
            guard let remaining else { return true }
            let reportedMinutes = remaining.timeInterval / 60
            let elapsedMinutes = now.timeIntervalSince(postedAt) / 60
            let lowest = Double(minutes) - elapsedMinutes - Self.countdownSlackMinutes
            return reportedMinutes >= lowest && reportedMinutes <= Double(minutes)
        }
    }
}
