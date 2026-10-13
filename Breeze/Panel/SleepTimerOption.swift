import Foundation
import ThinQKit

/// A choice in the Sleep menu: no timer, or one of the durations LG accepts (30 min or whole
/// hours up to 12). The menu skips 5, 7, 9 and 11 h to stay short.
nonisolated enum SleepTimerOption: Hashable, Sendable {
    case off
    case minutes(Int)

    /// Menu order.
    static let all: [SleepTimerOption] = [.off] + [30, 60, 120, 180, 240, 360, 480, 600, 720].map { .minutes($0) }

    /// The menu's selection for the reported timer: `.off` when none runs, else `nil`. LG reports
    /// the remaining time, not the option picked, so nothing is checked while a timer runs, and
    /// any option, the one running included, can be picked again to restart the timer.
    static func selection(for state: SleepTimerState?) -> SleepTimerOption? {
        state == .off ? .off : nil
    }

    var command: ACCommand {
        switch self {
        case .off: .sleepTimer(minutes: nil)
        case .minutes(let minutes): .sleepTimer(minutes: minutes)
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .off:
            "Off"
        case .minutes(let minutes):
            "\(Self.format(.seconds(minutes * 60), width: .abbreviated))"  // "30 min", "1 hr", "12 hr"
        }
    }

    var symbolName: String {
        switch self {
        case .off: "moon"
        case .minutes: "moon.zzz"
        }
    }

    /// The Sleep card's value while a timer runs: the time left, "1h 20m" (with "left" the
    /// half-width card truncates it). `nil` otherwise, so the card shows the selection's name
    /// ("Off") or "Unknown".
    static func cardValue(for state: SleepTimerState?) -> LocalizedStringResource? {
        guard case .set(let remaining)? = state else { return nil }
        guard let remaining else { return "On" }
        return "\(format(remaining, width: .narrow))"
    }

    /// VoiceOver's version of `cardValue(for:)`: "1 hour, 20 minutes left".
    static func accessibilityValue(for state: SleepTimerState?) -> LocalizedStringResource? {
        guard case .set(let remaining)? = state else { return nil }
        guard let remaining else { return "On" }
        return "\(format(remaining, width: .wide)) left"
    }

    /// Plural-aware and localized by Foundation.
    private static func format(_ duration: Duration, width: Duration.UnitsFormatStyle.UnitWidth) -> String {
        duration.formatted(.units(allowed: [.hours, .minutes], width: width))
    }
}
