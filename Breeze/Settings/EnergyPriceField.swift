import SwiftUI

/// "Price per kWh" in the locale's currency. Empty means no estimated
/// cost; a negative price is rejected and the saved one kept.
struct EnergyPriceField: View {
    @Environment(AppSettings.self) private var settings

    @State private var wasRejected = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                Text(verbatim: EnergyCost.currencySymbol)
                    .foregroundStyle(.secondary)
                TextField("Price per kWh", value: priceBinding, format: .number.precision(.fractionLength(0...4)), prompt: Text("None"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("per kWh")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Price per kWh")
            if wasRejected {
                Text("The price can't be negative.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var priceBinding: Binding<Decimal?> {
        Binding(
            get: { settings.energyPricePerKWh },
            set: { wasRejected = !settings.setEnergyPricePerKWh($0) }
        )
    }
}
