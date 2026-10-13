import Foundation
import ThinQKit

/// One bar of the Energy tab chart: a month or a day of `EnergySummary`, placed on the energy
/// calendar (`EnergySummary.calendar()`: Gregorian, in the user's time zone).
nonisolated struct EnergyBar: Identifiable, Equatable, Sendable {
    /// The start of the month or day, in the user's time zone.
    let date: Date
    let energy: Measurement<UnitEnergy>
    /// The month or day in progress, highlighted in the chart.
    let isCurrent: Bool

    var id: Date { date }

    var kilowattHours: Double {
        energy.converted(to: .kilowattHours).value
    }

    /// The bars for `range`, oldest first. "Current" is the period `summary.fetchedAt` falls in.
    static func bars(for summary: EnergySummary, range: EnergyChartRange, calendar: Calendar) -> [EnergyBar] {
        let entries = range == .months ? summary.months : summary.days
        let fields: Set<Calendar.Component> = range == .months ? [.year, .month] : [.year, .month, .day]
        let current = calendar.dateComponents(fields, from: summary.fetchedAt)
        return entries.compactMap { entry in
            let components = DateComponents(year: entry.date.year, month: entry.date.month, day: entry.date.day ?? 1)
            guard let date = calendar.date(from: components) else { return nil }
            return EnergyBar(
                date: date,
                energy: entry.energy,
                isCurrent: calendar.dateComponents(fields, from: date) == current
            )
        }
    }
}
