import Foundation

/// The AC's state in UI terms, derived from a `DeviceState` and the model's capabilities.
public struct AirConditionerSnapshot: Sendable, Equatable {
    public var power: ACPower
    public var mode: ACMode?
    /// `nil` when the reported values match none of the capability's options.
    public var fan: ACFanSetting?
    public var currentTemperature: Measurement<UnitTemperature>?
    public var targetTemperature: Measurement<UnitTemperature>?
    public var powerSave: Bool?
    public var verticalSwing: Bool?
    public var horizontalSwing: Bool?
    /// `display.light`: ON → `true`, OFF → `false`, anything else (e.g. `LEVEL_1`) → `nil`.
    public var displayLight: Bool?
    public var sleepTimer: SleepTimerState?

    public init(
        power: ACPower,
        mode: ACMode? = nil,
        fan: ACFanSetting? = nil,
        currentTemperature: Measurement<UnitTemperature>? = nil,
        targetTemperature: Measurement<UnitTemperature>? = nil,
        powerSave: Bool? = nil,
        verticalSwing: Bool? = nil,
        horizontalSwing: Bool? = nil,
        displayLight: Bool? = nil,
        sleepTimer: SleepTimerState? = nil
    ) {
        self.power = power
        self.mode = mode
        self.fan = fan
        self.currentTemperature = currentTemperature
        self.targetTemperature = targetTemperature
        self.powerSave = powerSave
        self.verticalSwing = verticalSwing
        self.horizontalSwing = horizontalSwing
        self.displayLight = displayLight
        self.sleepTimer = sleepTimer
    }

    /// Missing or unrecognised power reads as `.off`; every other missing value is `nil`.
    public init(state: DeviceState, capabilities: AirConditionerCapabilities) {
        let power = state["operation", "airConOperationMode"]?.stringValue.flatMap(ACPower.init(rawValue:))
        let mode = state["airConJobMode", "currentJobMode"]?.stringValue.map(ACMode.init(rawValue:))

        let temperature = capabilities.temperature
        let entry = Self.temperatureEntry(in: state, capability: temperature)
        let unit = entry?["unit"]?.stringValue.map(TemperatureCapability.unit(forCode:)) ?? temperature.unit
        let current = entry?["currentTemperature"]?.doubleValue
        let target = TemperatureCapability.targetKeyCandidates(for: mode)
            .lazy
            .compactMap { entry?[$0]?.doubleValue }
            .first

        let light: Bool? = switch state["display", "light"]?.stringValue {
        case "ON"?: true
        case "OFF"?: false
        default: nil
        }

        self.init(
            power: power ?? .off,
            mode: mode,
            fan: capabilities.fan.setting(in: state),
            currentTemperature: current.map { Measurement(value: $0, unit: unit) },
            targetTemperature: target.map { Measurement(value: $0, unit: unit) },
            powerSave: state["powerSave", "powerSaveEnabled"]?.boolValue,
            verticalSwing: state["windDirection", "rotateUpDown"]?.boolValue,
            horizontalSwing: state["windDirection", "rotateLeftRight"]?.boolValue,
            displayLight: light,
            sleepTimer: ACCommand.sleepTimer(in: state)
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
