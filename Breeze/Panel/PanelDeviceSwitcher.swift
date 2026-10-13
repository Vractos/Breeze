import SwiftUI

/// The device name; with more than one AC on the account, a menu that switches between them.
/// Used by the header, and above the message while there is no state
/// to show, so an offline AC never strands the user on it.
struct PanelDeviceSwitcher: View {
    let device: DeviceLabel
    /// Every AC on the account; the switch menu appears only with two or more.
    let devices: [DeviceLabel]
    let selectDevice: (String) -> Void

    var body: some View {
        if devices.count > 1 {
            Menu {
                Picker("Air conditioner", selection: selection) {
                    ForEach(devices) { option in
                        Text(option.fullName).tag(option.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    name
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .help(Text("Switch air conditioner"))
            .accessibilityLabel(Text("Air conditioner"))
            .accessibilityValue(Text(device.fullName))
            .accessibilityHint(Text("Switches to another air conditioner."))
        } else {
            name
                .accessibilityElement(children: .combine)
        }
    }

    /// The name, plus "…a3f2" in secondary when another AC has the same name (the menu items and
    /// Settings also show the model; the header keeps to one short line).
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(device.name)
                .font(.headline)
                .lineLimit(1)
            if device.isAmbiguous {
                Text(device.idSuffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var selection: Binding<String> {
        Binding(
            get: { device.id },
            set: { selectDevice($0) }
        )
    }
}
