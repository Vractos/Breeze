import Foundation

/// The Energy tab chart's segmented picker: the last 12 months or the last 30 days.
nonisolated enum EnergyChartRange: Hashable, CaseIterable, Sendable {
    case months
    case days

    var title: LocalizedStringResource {
        switch self {
        case .months: "12 Months"
        case .days: "30 Days"
        }
    }
}
