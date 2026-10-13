import SwiftUI
import ThinQKit

/// The Liquid Glass card with the target temperature in a large rounded numeral.
struct TemperatureHero: View {
    let target: Measurement<UnitTemperature>?
    let mode: ACMode?
    let isOn: Bool
    /// False while the panel is closed: the AC symbol's animation stops.
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                numeral
                modeLine
            }
            Spacer(minLength: 0)
            Image(systemName: "air.conditioner.horizontal")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(symbolStyle)
                .symbolEffect(.variableColor.iterative, isActive: isConditioning && isAnimating && !reduceMotion)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Target temperature"))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var numeral: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let target {
                Text(target.value, format: .number.precision(.fractionLength(0...1)))
                    .font(.system(size: 56, weight: .medium, design: .rounded))
                    .contentTransition(reduceMotion ? .identity : .numericText(value: target.value))
                    .animation(reduceMotion ? nil : .snappy, value: target.value)
                // The unit's own symbol ("°C" / "°F"), not a hardcoded suffix.
                Text(target.unit.symbol)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "--")
                    .font(.system(size: 56, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    @ViewBuilder
    private var modeLine: some View {
        if isOn, let mode {
            Label {
                Text(mode.displayName)
            } icon: {
                Image(systemName: mode.symbolName)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
        } else {
            Text(isOn ? "On" : "Off")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// Animate only while the AC is actually conditioning the air.
    private var isConditioning: Bool {
        isOn && (mode == .cool || mode == .heat)
    }

    private var symbolStyle: AnyShapeStyle {
        guard isOn else { return AnyShapeStyle(.secondary) }
        switch mode {
        case ACMode.heat?: return AnyShapeStyle(Color.orange)
        case ACMode.cool?: return AnyShapeStyle(Color.cyan)
        default: return AnyShapeStyle(.tint)
        }
    }

    private var accessibilityValue: Text {
        guard let target else { return Text("Unknown") }
        let temperature = Text(target, format: .acTemperature)
        guard isOn else { return Text("\(temperature), off") }
        guard let mode else { return temperature }
        return Text("\(temperature), \(Text(mode.displayName))")
    }
}
