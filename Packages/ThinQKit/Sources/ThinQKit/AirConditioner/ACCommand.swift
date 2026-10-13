import Foundation

/// A user intent for the AC, turned into a `POST devices/{id}/control` body.
public enum ACCommand: Sendable, Equatable {
    case power(ACPower)
    case mode(ACMode)
    case fan(ACFanSetting)
    case targetTemperature(Double)
    case powerSave(Bool)
    case verticalSwing(Bool)
    case horizontalSwing(Bool)
    case displayLight(Bool)
    /// 30 min or whole hours 1–12 (`ACModelError.invalidSleepTimer` otherwise); `nil` cancels.
    case sleepTimer(minutes: Int?)

    /// Validates the command against the profile-derived capabilities and builds the body for
    /// `ThinQClient.control(deviceID:body:)`.
    ///
    /// - Parameter currentMode: the AC's current job mode (e.g. the snapshot's `mode`), or `nil`
    ///   when unknown. Only `.targetTemperature` uses it, to pick the setpoint key for the mode
    ///   (`TemperatureCapability.writeKey(for:)`).
    public func payload(for caps: AirConditionerCapabilities, currentMode: ACMode?) throws(ACModelError) -> JSONObject {
        switch self {
        case .targetTemperature(let value):
            let setpoint = try Self.validatedSetpoint(value, caps: caps, mode: currentMode)
            return Self.temperaturePayload(setpoint, caps: caps)
        case .fan(let setting):
            return try caps.fan.payload(for: setting)
        case .sleepTimer(let minutes):
            try Self.validateSleepTimer(minutes: minutes, caps: caps)
            return Self.sleepTimerPayload(minutes: minutes)
        case .power(let power):
            try Self.check(
                power,
                allowed: caps.powerOptions,
                property: AirConditionerCapabilities.powerProperty,
                unsupported: .unsupportedPower(power)
            )
        case .mode(let mode):
            try Self.check(
                mode,
                allowed: caps.modes,
                property: AirConditionerCapabilities.modeProperty,
                unsupported: .unsupportedMode(mode)
            )
        case .powerSave:
            try Self.requireWritable(caps.hasPowerSave, AirConditionerCapabilities.powerSaveProperty)
        case .verticalSwing:
            try Self.requireWritable(caps.hasVerticalSwing, AirConditionerCapabilities.verticalSwingProperty)
        case .horizontalSwing:
            try Self.requireWritable(caps.hasHorizontalSwing, AirConditionerCapabilities.horizontalSwingProperty)
        case .displayLight:
            try Self.requireWritable(caps.hasDisplayLight, AirConditionerCapabilities.displayLightProperty)
        }
        return simpleDelta
    }

    /// Optimistically merges the command's effect into a local state (no validation; the next
    /// fetched state wins anyway). The setpoint key follows the mode recorded in `state`.
    public func apply(to state: inout DeviceState, caps: AirConditionerCapabilities) {
        switch self {
        case .targetTemperature(let value):
            let modeProperty = AirConditionerCapabilities.modeProperty
            let mode = state[modeProperty.resource, modeProperty.key]?.stringValue.map(ACMode.init(rawValue:))
            let setpoint = Self.effectiveSetpoint(value, caps: caps, mode: mode)
            state.merge(delta: Self.temperatureStateDelta(setpoint, caps: caps, current: state))
        case .fan(let setting):
            state.merge(delta: caps.fan.stateDelta(for: setting))
        case .sleepTimer(let minutes):
            state.merge(delta: Self.sleepTimerStateDelta(minutes: minutes))
        case .power, .mode, .powerSave, .verticalSwing, .horizontalSwing, .displayLight:
            state.merge(delta: simpleDelta)
        }
    }

    /// Whether `error` only says this command was already in effect: `2302` for POWER_ON while
    /// on, `2304` for POWER_OFF while off. For any other command `2304` means
    /// "turn the AC on first", so it is a real failure.
    public func isRedundant(_ error: ThinQError) -> Bool {
        switch (self, error.apiCode) {
        case (.power(.on), .commandNotSupportedInState?): true
        case (.power(.off), .commandNotSupportedInPowerOff?): true
        default: false
        }
    }

    // MARK: - Validation

    /// An empty `allowed` list means the property is not writable on this model at all.
    private static func check<Value: Equatable>(
        _ value: Value,
        allowed: [Value],
        property: (resource: String, key: String),
        unsupported: ACModelError
    ) throws(ACModelError) {
        guard !allowed.isEmpty else { throw .notWritable(path(property)) }
        guard allowed.contains(value) else { throw unsupported }
    }

    private static func requireWritable(_ isWritable: Bool, _ property: (resource: String, key: String)) throws(ACModelError) {
        guard isWritable else { throw .notWritable(path(property)) }
    }

    /// A setpoint resolved for the current mode: the property to write and the exact value.
    private struct Setpoint {
        var key: String
        var value: Double
    }

    private static func validatedSetpoint(
        _ value: Double,
        caps: AirConditionerCapabilities,
        mode: ACMode?
    ) throws(ACModelError) -> Setpoint {
        guard let target = caps.temperature.writeKey(for: mode) else {
            throw .notWritable("\(temperatureResource(caps)).\(TemperatureCapability.unwritableKey(for: mode))")
        }
        guard target.range.contains(value) else {
            throw .invalidTargetTemperature(value, allowed: target.range)
        }
        return Setpoint(key: target.key, value: target.range.snapped(value))
    }

    /// Like `validatedSetpoint` but never fails: falls back to the generic key and the raw value.
    private static func effectiveSetpoint(_ value: Double, caps: AirConditionerCapabilities, mode: ACMode?) -> Setpoint {
        guard let target = caps.temperature.writeKey(for: mode) else {
            return Setpoint(key: TemperatureCapability.defaultTargetKey, value: value)
        }
        return Setpoint(key: target.key, value: target.range.snapped(value))
    }

    // MARK: - Bodies

    private static func temperaturePayload(_ setpoint: Setpoint, caps: AirConditionerCapabilities) -> JSONObject {
        let temperature = caps.temperature
        switch temperature.shape {
        case .flat:
            // {"temperature": {"targetTemperature": 22}} — official example (VERIFY).
            return ["temperature": [setpoint.key: .number(setpoint.value)]]
        case .inUnits:
            // {"temperatureInUnits": {"targetTemperature": 22, "unit": "C"}} — SDK device layer (VERIFY).
            return [
                "temperatureInUnits": [
                    setpoint.key: .number(setpoint.value),
                    "unit": .string(temperature.unitCode),
                ],
            ]
        }
    }

    /// Writes the setpoint where the state already keeps its temperatures (same shape, same unit
    /// entry), so the merge updates that object. Writing the capability's shape instead would
    /// create a sibling without `currentTemperature`, which the snapshot then prefers, and the
    /// room temperature would vanish until the next fetch. The capability's shape is only used
    /// when the state has no temperature yet.
    private static func temperatureStateDelta(
        _ setpoint: Setpoint,
        caps: AirConditionerCapabilities,
        current: DeviceState
    ) -> JSONObject {
        let capUnit = caps.temperature.unitCode
        let flatUnit: String? = current.values["temperature"]?.objectValue.map { object in
            object["unit"]?.stringValue ?? capUnit
        }
        let listUnit: String? = current.values["temperatureInUnits"]?.arrayValue.flatMap { entries in
            guard !entries.isEmpty else { return nil }
            let units = entries.compactMap { $0["unit"]?.stringValue }
            return units.contains(capUnit) ? capUnit : (units.first ?? capUnit)
        }
        let (shape, unitCode): (TemperatureShape, String) = caps.temperature.shape.preferring(
            flat: flatUnit.map { (TemperatureShape.flat, $0) },
            inUnits: listUnit.map { (TemperatureShape.inUnits, $0) }
        ) ?? (caps.temperature.shape, capUnit)

        var entry = stateEntry(setpoint, caps: caps, unitCode: unitCode)
        switch shape {
        case .flat:
            return ["temperature": .object(entry)]
        case .inUnits:
            entry["unit"] = .string(unitCode)
            return ["temperatureInUnits": [.object(entry)]]
        }
    }

    /// `{targetTemperature, <setpoint key>}` in `unitCode`. The command's value is in the
    /// capability's unit, so it is converted when the state keeps another unit.
    private static func stateEntry(_ setpoint: Setpoint, caps: AirConditionerCapabilities, unitCode: String) -> JSONObject {
        let targetUnit = TemperatureCapability.unit(forCode: unitCode)
        let value = targetUnit == caps.temperature.unit
            ? setpoint.value
            : Measurement(value: setpoint.value, unit: caps.temperature.unit).converted(to: targetUnit).value
        var entry: JSONObject = [TemperatureCapability.defaultTargetKey: .number(value)]
        entry[setpoint.key] = .number(value)
        return entry
    }

    /// Bodies whose payload and state delta are identical: power, mode, eco, swing, display light.
    private var simpleDelta: JSONObject {
        switch self {
        case .power(let power):
            Self.body(AirConditionerCapabilities.powerProperty, .string(power.rawValue))
        case .mode(let mode):
            Self.body(AirConditionerCapabilities.modeProperty, .string(mode.rawValue))
        case .powerSave(let enabled):
            Self.body(AirConditionerCapabilities.powerSaveProperty, .bool(enabled))
        case .verticalSwing(let enabled):
            Self.body(AirConditionerCapabilities.verticalSwingProperty, .bool(enabled))
        case .horizontalSwing(let enabled):
            Self.body(AirConditionerCapabilities.horizontalSwingProperty, .bool(enabled))
        case .displayLight(let isOn):
            Self.body(AirConditionerCapabilities.displayLightProperty, .string(isOn ? "ON" : "OFF"))
        case .targetTemperature, .fan, .sleepTimer:
            // Unreachable: `payload` and `apply` use these commands' own builders first.
            [:]
        }
    }

    private static func body(_ property: (resource: String, key: String), _ value: JSONValue) -> JSONObject {
        [property.resource: [property.key: value]]
    }

    private static func path(_ property: (resource: String, key: String)) -> String {
        "\(property.resource).\(property.key)"
    }

    private static func temperatureResource(_ caps: AirConditionerCapabilities) -> String {
        caps.temperature.shape == .flat ? "temperature" : "temperatureInUnits"
    }
}
