import SwiftUI
import ThinQKit

/// The menu bar item (always rendered, so kept to one image and at most one short text): the
/// active mode's symbol plus the target temperature ("22°") while the AC is on; just a symbol
/// when it is off or unknown.
struct StatusLabel: View {
    let snapshot: AirConditionerSnapshot?
    let showsTemperature: Bool

    var body: some View {
        let symbol = Self.symbolName(for: snapshot)
        if let target = Self.displayedTarget(for: snapshot, showsTemperature: showsTemperature) {
            Label {
                Text(Self.menuBarText(for: target))
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(Text("Breeze, target \(target, format: .acTemperature)"))
        } else {
            Image(systemName: symbol)
                .accessibilityLabel(Text("Breeze"))
        }
    }

    /// The running mode's symbol; a snowflake when off or unknown.
    nonisolated static func symbolName(for snapshot: AirConditionerSnapshot?) -> String {
        guard let snapshot, snapshot.power == .on, let mode = snapshot.mode else { return "snowflake" }
        return mode.symbolName
    }

    /// "22°" / "24,5°": the number in the AC's own unit plus a degree sign, without the unit
    /// letter, to keep the status item narrow. Foundation's narrow measurement width
    /// still writes "22°C" for Celsius, hence the localizable pattern ("%@°" in the catalog, so a
    /// translator can move the sign). VoiceOver reads the full unit from the accessibility label.
    nonisolated static func menuBarText(for target: Measurement<UnitTemperature>) -> LocalizedStringResource {
        "\(target.value, format: .number.precision(.fractionLength(0...1)))°"
    }

    /// The target to show next to the symbol, or `nil` for symbol only.
    nonisolated static func displayedTarget(
        for snapshot: AirConditionerSnapshot?,
        showsTemperature: Bool
    ) -> Measurement<UnitTemperature>? {
        guard showsTemperature, let snapshot, snapshot.power == .on else { return nil }
        return snapshot.targetTemperature
    }
}
