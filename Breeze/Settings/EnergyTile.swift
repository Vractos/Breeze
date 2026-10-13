import SwiftUI

/// One of the Energy tab's totals: "This month · 13.8 kWh", plus "Est. R$ 11,76" when a price per
/// kWh is set. "—" when LG has no entry for the period.
struct EnergyTile: View {
    let title: LocalizedStringResource
    let energy: Measurement<UnitEnergy>?
    let pricePerKWh: Decimal?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if let energy {
                    Text(energy.converted(to: .kilowattHours), format: .kilowattHours)
                } else {
                    Text(verbatim: "—")
                }
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            if let cost {
                Text("Est. \(cost, format: .currency(code: EnergyCost.currencyCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(accessibilityValue)
    }

    private var cost: Decimal? {
        guard let energy, let pricePerKWh else { return nil }
        return EnergyCost.estimate(for: energy, pricePerKWh: pricePerKWh)
    }

    private var accessibilityValue: Text {
        energy.map { Self.spokenValue($0, pricePerKWh: pricePerKWh) } ?? Text("No data")
    }

    /// VoiceOver's "13.8 kilowatt-hours", plus the estimated cost when a price is set (also used
    /// by the chart's bars).
    static func spokenValue(_ energy: Measurement<UnitEnergy>, pricePerKWh: Decimal?) -> Text {
        let wide = energy.converted(to: .kilowattHours).formatted(.kilowattHoursWide)
        guard let pricePerKWh else { return Text(wide) }
        let cost = EnergyCost.estimate(for: energy, pricePerKWh: pricePerKWh)
        return Text("\(wide), estimated cost \(cost, format: .currency(code: EnergyCost.currencyCode))")
    }
}
