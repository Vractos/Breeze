import SwiftUI
import ThinQKit

/// −, slider, + for the setpoint, with the range's limits underneath. Every change goes through
/// `onChange` (the panel's debounced editor), never straight to the store; the slider also
/// reports when a drag starts and ends, so a drag commits once, at the end.
struct TemperatureControl: View {
    let setpoint: TemperatureSetpoint
    let onChange: (Double) -> Void
    let onSliderEditingChanged: (Bool) -> Void

    private var range: PropertySpec.NumericRange { setpoint.range }

    var body: some View {
        if range.isAdjustable {
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    stepButton(up: false)
                    slider
                    stepButton(up: true)
                }
                limits
            }
        } else {
            // A one-value range cannot drive a Slider.
            Text(setpoint.measurement, format: .acTemperature)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var slider: some View {
        Slider(
            value: Binding(get: { setpoint.value }, set: { onChange($0) }),
            in: range.min...range.max,
            step: range.effectiveStep,
            onEditingChanged: onSliderEditingChanged
        )
        .accessibilityLabel(Text("Target temperature"))
        .accessibilityValue(Text(setpoint.measurement, format: .acTemperature))
    }

    private var limits: some View {
        HStack {
            Text(setpoint.measurement(range.min), format: .acTemperature)
            Spacer()
            Text(setpoint.measurement(range.max), format: .acTemperature)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        // Line the labels up with the slider's ends, between the two round buttons.
        .padding(.horizontal, 40)
        .accessibilityHidden(true)
    }

    private func stepButton(up: Bool) -> some View {
        Button {
            onChange(range.value(steppingFrom: setpoint.value, up: up))
        } label: {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(up ? setpoint.value >= range.max : setpoint.value <= range.min)
        .accessibilityLabel(up ? Text("Increase temperature") : Text("Decrease temperature"))
    }
}
