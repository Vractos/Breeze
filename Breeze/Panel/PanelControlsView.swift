import SwiftUI
import ThinQKit

/// The AC's controls: the header with the power button, the temperature, Eco, the display light
/// and the card grid.
/// Everything except the power button is disabled and dimmed while the AC is off; the change
/// animates with a spring.
struct PanelControlsView: View {
    let snapshot: AirConditionerSnapshot
    let capabilities: AirConditionerCapabilities
    /// The setpoint being edited (`TemperatureEditor.draft`), shown before it is sent.
    let draft: Double?
    let acceptsCommands: Bool
    let isVisible: Bool
    let onEditTarget: (Double) -> Void
    /// The slider's drag started (`true`) or ended (`false`).
    let onSliderEditingChanged: (Bool) -> Void

    @Environment(ACStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOn: Bool { snapshot.power == .on }
    /// Off, offline or token-invalid: the last state stays visible, greyed out and read-only.
    private var isAdjustable: Bool { isOn && acceptsCommands }

    var body: some View {
        VStack(spacing: 14) {
            PanelHeader(
                device: store.deviceLabel,
                devices: store.deviceLabels,
                roomTemperature: roomTemperature,
                isOn: isOn,
                canTogglePower: acceptsCommands,
                selectDevice: { id in Task { await store.selectDevice(id: id) } },
                togglePower: { store.send(.power(snapshot.power.toggled)) }
            )

            VStack(spacing: 14) {
                TemperatureHero(target: displayedTarget, mode: snapshot.mode, isOn: isOn, isAnimating: isVisible)
                if capabilities.hasPowerSave {
                    EcoToggleRow(isOn: snapshot.powerSave ?? false) { enabled in
                        store.send(.powerSave(enabled))
                    }
                }
                if capabilities.hasDisplayLight {
                    DisplayLightToggleRow(isOn: snapshot.displayLight ?? false) { isOn in
                        store.send(.displayLight(isOn))
                    }
                }
                temperatureControl
                ControlCardGrid(
                    snapshot: snapshot,
                    capabilities: capabilities,
                    isAnimating: isVisible,
                    send: { store.send($0) }
                )
            }
            .disabled(!isAdjustable)
            .opacity(isAdjustable ? 1 : 0.45)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: isAdjustable)
    }

    @ViewBuilder
    private var temperatureControl: some View {
        if let setpoint = TemperatureSetpoint(snapshot: snapshot, capabilities: capabilities, draft: draft) {
            TemperatureControl(setpoint: setpoint, onChange: onEditTarget, onSliderEditingChanged: onSliderEditingChanged)
        } else {
            Text("The target temperature can't be changed in this mode.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Hidden when the model doesn't report it.
    private var roomTemperature: Measurement<UnitTemperature>? {
        capabilities.temperature.currentReadable ? snapshot.currentTemperature : nil
    }

    /// The pending edit wins so the hero follows the slider immediately.
    private var displayedTarget: Measurement<UnitTemperature>? {
        if let draft {
            return Measurement(value: draft, unit: capabilities.temperature.unit)
        }
        return snapshot.targetTemperature
    }
}
