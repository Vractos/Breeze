#if DEBUG
import Foundation
import ThinQKit

/// Canned Energy API answers for previews and tests, shaped like a real unit's:
/// Wh values, this month at 13 831 Wh (what `thinq energy` returned for October 2026), and daily
/// entries that include quiet days at 0 Wh.
nonisolated enum PreviewEnergy {
    static let properties = ["energyUsage"]

    /// The newest month of a MONTHLY answer (the month in progress, so lower than full months).
    static let currentMonthWattHours = 13_831.0
    /// Full months, January…December: more cooling in the Brazilian summer.
    private static let monthlyWattHours: [Double] = [
        61_020, 58_410, 54_870, 38_260, 22_940, 12_310, 9_880, 11_450, 19_730, 31_640, 44_980, 57_300,
    ]
    /// Repeats over the days of a DAILY answer, newest last; zeros are days the AC stayed off.
    private static let dailyWattHours: [Double] = [
        0, 1_240, 1_610, 0, 0, 980, 1_455, 2_030, 1_870, 0, 640, 1_120, 1_390, 0, 1_205,
    ]

    /// One entry per period in `from…to` (inclusive), oldest first, as `EnergyResponse` parses it.
    static func usage(period: EnergyPeriod, from: DateComponents, to: DateComponents) -> [EnergyUsageEntry] {
        let unit: Calendar.Component = period == .daily ? .day : .month
        guard let start = date(from, period: period), let end = date(to, period: period), start <= end else { return [] }

        var dates: [Date] = []
        var current = start
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: unit, value: 1, to: current) else { break }
            current = next
        }
        return dates.enumerated().map { index, date in
            let isNewest = index == dates.count - 1
            let wattHours: Double
            switch period {
            case .monthly:
                let month = calendar.component(.month, from: date)
                wattHours = isNewest ? currentMonthWattHours : monthlyWattHours[(month - 1) % monthlyWattHours.count]
            case .daily:
                let fromNewest = dates.count - 1 - index
                wattHours = dailyWattHours[dailyWattHours.count - 1 - fromNewest % dailyWattHours.count]
            }
            let fields: Set<Calendar.Component> = period == .daily ? [.year, .month, .day] : [.year, .month]
            return EnergyUsageEntry(
                date: calendar.dateComponents(fields, from: date),
                energy: Measurement(value: wattHours / 1000, unit: .kilowattHours)
            )
        }
    }

    private static func date(_ components: DateComponents, period: EnergyPeriod) -> Date? {
        let day = period == .daily ? components.day : 1
        return calendar.date(from: DateComponents(year: components.year, month: components.month, day: day))
    }

    /// Only steps calendar dates, so UTC avoids DST gaps.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
#endif
