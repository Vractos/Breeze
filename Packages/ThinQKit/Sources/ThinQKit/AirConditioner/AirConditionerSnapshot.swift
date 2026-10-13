import Foundation

/// The AC's state in UI terms, derived from a `DeviceState` and the model's capabilities.
public struct AirConditionerSnapshot: Sendable, Equatable {
    public var power: ACPower
    public var mode: ACMode?
    public var fanSpeed: ACFanSpeed?
    public var currentTemperature: Measurement<UnitTemperature>?
    public var targetTemperature: Measurement<UnitTemperature>?
    public var powerSave: Bool?

    public init(
        power: ACPower,
        mode: ACMode? = nil,
        fanSpeed: ACFanSpeed? = nil,
        currentTemperature: Measurement<UnitTemperature>? = nil,
        targetTemperature: Measurement<UnitTemperature>? = nil,
        powerSave: Bool? = nil
    ) {
        self.power = power
        self.mode = mode
        self.fanSpeed = fanSpeed
        self.currentTemperature = currentTemperature
        self.targetTemperature = targetTemperature
        self.powerSave = powerSave
    }

    /// Missing or unrecognised power reads as `.off`; every other missing value is `nil`.
    public init(state: DeviceState, capabilities: AirConditionerCapabilities) {
        let power = state["operation", "airConOperationMode"]?.stringValue.flatMap(ACPower.init(rawValue:))
        let mode = state["airConJobMode", "currentJobMode"]?.stringValue.map(ACMode.init(rawValue:))
        let fan = (state["airFlow", capabilities.fanSpeedKey] ?? state["airFlow", "windStrength"])?
            .stringValue
            .map(ACFanSpeed.init(rawValue:))

        let temperature = capabilities.temperature
        let entry = Self.temperatureEntry(in: state, capability: temperature)
        let unit = entry?["unit"]?.stringValue.map(TemperatureCapability.unit(forCode:)) ?? temperature.unit
        let current = entry?["currentTemperature"]?.doubleValue
        let target = TemperatureCapability.targetKeyCandidates(for: mode)
            .lazy
            .compactMap { entry?[$0]?.doubleValue }
            .first

        self.init(
            power: power ?? .off,
            mode: mode,
            fanSpeed: fan,
            currentTemperature: current.map { Measurement(value: $0, unit: unit) },
            targetTemperature: target.map { Measurement(value: $0, unit: unit) },
            powerSave: state["powerSave", "powerSaveEnabled"]?.boolValue
        )
    }

    /// The object holding current/target temperature, looking in the capability's shape first
    /// and falling back to the other one (state and profile shapes could disagree).
    private static func temperatureEntry(in state: DeviceState, capability: TemperatureCapability) -> JSONValue? {
        let fromUnits: JSONValue? = state.values["temperatureInUnits"]?.arrayValue.flatMap { list in
            list.first { $0["unit"]?.stringValue == capability.unitCode } ?? list.first
        }
        let fromFlat = state.values["temperature"].flatMap { $0.objectValue != nil ? $0 : nil }
        return capability.shape.preferring(flat: fromFlat, inUnits: fromUnits)
    }
}
