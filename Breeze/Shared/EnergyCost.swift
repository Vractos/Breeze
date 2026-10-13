import Foundation

/// The estimated cost Settings › Energy shows when a price per kWh is set.
/// LG reports energy only; tariffs, taxes and fees aren't modelled, so this is always labelled
/// an estimate.
nonisolated enum EnergyCost {
    /// `energy` in kWh × `pricePerKWh`. The kWh value is rounded to whole Wh first (LG reports
    /// integer Wh), so binary noise from the Wh → kWh conversion never reaches the result.
    static func estimate(for energy: Measurement<UnitEnergy>, pricePerKWh: Decimal) -> Decimal {
        var kilowattHours = Decimal(energy.converted(to: .kilowattHours).value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &kilowattHours, 3, .plain)
        return rounded * pricePerKWh
    }

    /// The currency prices and costs are shown in: the user's locale's (e.g. BRL for pt_BR).
    /// Gotcha: a locale without a region (e.g. plain "en") has no currency; USD is the fallback.
    static var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// The symbol next to the price field ("R$"), matching `currencyCode`.
    static var currencySymbol: String {
        guard Locale.current.currency != nil else { return "$" }
        return Locale.current.currencySymbol ?? currencyCode
    }
}
