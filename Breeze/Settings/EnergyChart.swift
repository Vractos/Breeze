import Charts
import SwiftUI

/// The Energy tab's bar chart: the last 12 months or 30 days in kWh, the month or day in progress
/// highlighted. Each bar reads to VoiceOver as its date and kWh, plus the estimated cost when a
/// price per kWh is set.
struct EnergyChart: View {
    let summary: EnergySummary
    let range: EnergyChartRange
    let pricePerKWh: Decimal?

    /// The store's calendar, so bars land on the dates LG reported.
    private let calendar = EnergySummary.calendar()

    var body: some View {
        let bars = EnergyBar.bars(for: summary, range: range, calendar: calendar)
        Chart(bars) { bar in
            BarMark(
                x: .value("Date", bar.date, unit: range == .months ? .month : .day),
                y: .value("Energy (kWh)", bar.kilowattHours)
            )
            .foregroundStyle(bar.isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.4)))
            .accessibilityLabel(dateText(bar.date))
            .accessibilityValue(EnergyTile.spokenValue(bar.energy, pricePerKWh: pricePerKWh))
        }
        .chartXAxis {
            switch range {
            case .months:
                AxisMarks(values: .stride(by: .month, count: 2)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            case .days:
                AxisMarks(values: .stride(by: .day, count: 7)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kilowattHours = value.as(Double.self) {
                        Text(kilowattHours, format: .number.precision(.fractionLength(0...1)))
                    }
                }
            }
        }
        .chartYAxisLabel {
            Text(verbatim: "kWh")
        }
        .frame(height: 140)
        .overlay {
            if bars.isEmpty {
                Text("No energy data for this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dateText(_ date: Date) -> Text {
        switch range {
        case .months: Text(date, format: .dateTime.month(.wide).year())
        case .days: Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
        }
    }
}
