import SwiftUI

/// Device name and room temperature on the left, the power button on the right. With more than
/// one AC on the account the name is a menu that switches between them (`PanelDeviceSwitcher`).
struct PanelHeader: View {
    let device: DeviceLabel?
    /// Every AC on the account; the switch menu appears only with two or more.
    let devices: [DeviceLabel]
    let roomTemperature: Measurement<UnitTemperature>?
    let isOn: Bool
    /// False while offline / token-invalid. Switching devices stays possible then.
    let canTogglePower: Bool
    let selectDevice: (String) -> Void
    let togglePower: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let device {
                    PanelDeviceSwitcher(device: device, devices: devices, selectDevice: selectDevice)
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
                .disabled(!canTogglePower)
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
