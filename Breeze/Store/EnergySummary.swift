import Foundation
import ThinQKit

/// The selected AC's energy use for Settings › Energy, built from two
/// requests: MONTHLY for the last 12 months and DAILY for the last 30 days. "This month",
/// "today" and "last month" are read from those lists, so they cost no extra request.
///
/// LG's dates are calendar days/months in the user's local time, so every
/// derivation here uses the user's time zone, never UTC.
nonisolated struct EnergySummary: Equatable, Sendable {
    static let monthCount = 12
    static let dayCount = 30

    /// The calendar for energy dates: Gregorian (LG's dates and ThinQKit's `EnergyPeriod` are
    /// Gregorian) in the user's time zone and locale, which by default follow the system
    /// settings as they change. Gotcha: never `Calendar.current`, which may be Japanese or
    /// Buddhist and would send year 8 or 2569.
    static func calendar(timeZone: TimeZone = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    /// The inclusive `from`…`to` of one usage request.
    struct UsageRange: Equatable, Sendable {
        let from: DateComponents
        let to: DateComponents
    }

    /// Up to the last 12 months, oldest first, this month last. LG may leave months out.
    let months: [EnergyUsageEntry]
    /// Up to the last 30 days, oldest first, today last. LG reports quiet days as 0 Wh.
    let days: [EnergyUsageEntry]
    /// `nil` when LG has no entry for that period.
    let thisMonth: Measurement<UnitEnergy>?
    let today: Measurement<UnitEnergy>?
    let lastMonth: Measurement<UnitEnergy>?
    /// When the requests were made (the "Updated … ago" line and the 1 h refresh gate).
    let fetchedAt: Date

    /// Keeps only the entries inside the requested ranges, oldest first, and derives the three
    /// totals.
    init(months: [EnergyUsageEntry], days: [EnergyUsageEntry], fetchedAt: Date, calendar: Calendar) {
        let monthKeys = Self.periods(.month, count: Self.monthCount, endingAt: fetchedAt, calendar: calendar)
        let dayKeys = Self.periods(.day, count: Self.dayCount, endingAt: fetchedAt, calendar: calendar)
        let monthsByKey = Self.lastEntryByPeriod(months)
        let daysByKey = Self.lastEntryByPeriod(days)
        self.months = monthKeys.compactMap { monthsByKey[$0] }
        self.days = dayKeys.compactMap { daysByKey[$0] }
        self.fetchedAt = fetchedAt

        thisMonth = monthKeys.last.flatMap { monthsByKey[$0] }?.energy
        lastMonth = monthKeys.dropLast().last.flatMap { monthsByKey[$0] }?.energy
        today = dayKeys.last.flatMap { daysByKey[$0] }?.energy
    }

    // MARK: - Requests

    /// MONTHLY: the 11 months before `now`'s month, through `now`'s month.
    static func monthRange(endingAt now: Date, calendar: Calendar) -> UsageRange {
        UsageRange(
            from: period(.month, back: monthCount - 1, from: now, calendar: calendar),
            to: period(.month, back: 0, from: now, calendar: calendar)
        )
    }

    /// DAILY: the 29 days before today, through today.
    static func dayRange(endingAt now: Date, calendar: Calendar) -> UsageRange {
        UsageRange(
            from: period(.day, back: dayCount - 1, from: now, calendar: calendar),
            to: period(.day, back: 0, from: now, calendar: calendar)
        )
    }

    /// The property to request: `energyUsage` (what ACs report), else the first
    /// one LG lists; `nil` when the list is empty (the AC reports no energy).
    static func usageProperty(from properties: [String]) -> String? {
        properties.contains(defaultProperty) ? defaultProperty : properties.first
    }

    private static let defaultProperty = "energyUsage"

    // MARK: - Periods

    /// The last `count` months or days, oldest first, keyed like `lastEntryByPeriod`.
    private static func periods(_ unit: Calendar.Component, count: Int, endingAt now: Date, calendar: Calendar) -> [DateComponents] {
        (0..<count).reversed().map { period(unit, back: $0, from: now, calendar: calendar) }
    }

    /// Year and month (plus the day for `.day`) of the month or day `back` steps before `now`, in
    /// the user's calendar. Gotcha: stepping from noon keeps a DST change at midnight from
    /// skipping or repeating a day.
    private static func period(_ unit: Calendar.Component, back: Int, from now: Date, calendar: Calendar) -> DateComponents {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let date = calendar.date(byAdding: unit, value: -back, to: noon) ?? noon
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DateComponents(year: components.year, month: components.month, day: unit == .day ? components.day : nil)
    }

    /// Entries by their year, month and day (`nil` for a monthly entry), so a daily entry never
    /// matches a month and vice versa. The last one LG sent for a period wins.
    private static func lastEntryByPeriod(_ entries: [EnergyUsageEntry]) -> [DateComponents: EnergyUsageEntry] {
        Dictionary(
            entries.map { (DateComponents(year: $0.date.year, month: $0.date.month, day: $0.date.day), $0) },
            uniquingKeysWith: { _, last in last }
        )
    }
}
