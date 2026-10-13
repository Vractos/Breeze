import Foundation
import ThinQKit

/// The writable setpoint for the AC's current mode, as the temperature controls see it: the
/// allowed range (from `TemperatureCapability.writeKey(for:)`), the capability's unit, and the
/// value to show (the pending edit if any, else the snapshot's target, clamped to the range).
nonisolated struct TemperatureSetpoint: Sendable {
    let range: PropertySpec.NumericRange
    let unit: UnitTemperature
    let value: Double

    /// `nil` when the target is not writable in the current mode (e.g. some models in FAN).
    init?(snapshot: AirConditionerSnapshot, capabilities: AirConditionerCapabilities, draft: Double?) {
        guard let target = capabilities.temperature.writeKey(for: snapshot.mode) else { return nil }
        let unit = capabilities.temperature.unit
        // Commands take values in the capability's unit; the state may report another one.
        let current = draft ?? snapshot.targetTemperature?.converted(to: unit).value ?? target.range.min
        self.range = target.range
        self.unit = unit
        self.value = min(max(current, target.range.min), target.range.max)
    }

    var measurement: Measurement<UnitTemperature> {
        Measurement(value: value, unit: unit)
    }

    func measurement(_ value: Double) -> Measurement<UnitTemperature> {
        Measurement(value: value, unit: unit)
    }
}
