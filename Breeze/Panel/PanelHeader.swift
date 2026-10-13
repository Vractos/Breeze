import SwiftUI

/// Device name and room temperature on the left, the power button on the right.
struct PanelHeader: View {
    let deviceName: String?
    let roomTemperature: Measurement<UnitTemperature>?
    let isOn: Bool
    let togglePower: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let deviceName, !deviceName.isEmpty {
                    Text(deviceName)
                        .font(.headline)
                        .lineLimit(1)
                }
                if let roomTemperature {
                    Label {
                        Text("Room \(roomTemperature, format: .acTemperature)")
                    } icon: {
                        Image(systemName: "thermometer.medium")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 8)
            powerButton
        }
    }

    private var powerButton: some View {
        Button(action: togglePower) {
            Image(systemName: "power")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .symbolEffect(.bounce, value: isOn)
                .frame(width: 40, height: 40)
                // Gotcha: neither `.buttonStyle(.glass(.regular.tint(…)))` nor a tinted
                // `glassEffect` showed any tint in the macOS 27 preview, so the "on" colour is a
                // fill behind the glass. One view in both states keeps the bounce working
                // (switching between two button styles would recreate the symbol).
                .background(isOn ? Color.accentColor : Color.clear, in: .circle)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(isOn ? Text("Turn off") : Text("Turn on"))
        .accessibilityLabel(Text("Power"))
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityHint(isOn ? Text("Turns the air conditioner off.") : Text("Turns the air conditioner on."))
    }
}
