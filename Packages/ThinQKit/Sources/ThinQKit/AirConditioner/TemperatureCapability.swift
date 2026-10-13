import Foundation

/// The AC's temperature support, normalised across both profile shapes.
public struct TemperatureCapability: Sendable, Equatable {
    public var unit: UnitTemperature
    public var currentReadable: Bool
    public var shape: TemperatureShape
    /// Write constraints of every writable setpoint property, keyed by property name
    /// (`targetTemperature`, `coolTargetTemperature`, `heatTargetTemperature`,
    /// `autoTargetTemperature`). Empty ⇒ the setpoint is not writable on this model.
    public var writableTargets: [String: PropertySpec.NumericRange]

    public init(
        unit: UnitTemperature,
        currentReadable: Bool,
        shape: TemperatureShape,
        writableTargets: [String: PropertySpec.NumericRange]
    ) {
        self.unit = unit
        self.currentReadable = currentReadable
        self.shape = shape
        self.writableTargets = writableTargets
    }

    public static let defaultTargetKey = "targetTemperature"
    static let coolTargetKey = "coolTargetTemperature"
    static let heatTargetKey = "heatTargetTemperature"
    static let autoTargetKey = "autoTargetTemperature"
    static let setpointKeys = [defaultTargetKey, coolTargetKey, heatTargetKey, autoTargetKey]

    /// The setpoint property to write in `mode`, with its range; `nil` when none is writable.
    public func writeKey(for mode: ACMode?) -> (key: String, range: PropertySpec.NumericRange)? {
        for key in Self.targetKeyCandidates(for: mode) {
            if let range = writableTargets[key] {
                return (key, range)
            }
        }
        return nil
    }

    /// Setpoint keys for `mode`, in preference order. VERIFY on the real device.
    ///
    /// The generic `targetTemperature` always comes first (the official fixture writes it).
    /// The fallback follows Home Assistant (pythinqconnect `get_target_temp_control_holder`):
    /// COOL → cool, HEAT → heat, AUTO → auto, any other or unknown mode → cool. HEAT and AUTO
    /// never fall back to the cool setpoint: LG accepts it, but it moves the wrong target.
    static func targetKeyCandidates(for mode: ACMode?) -> [String] {
        [defaultTargetKey, modeTargetKey(for: mode)]
    }

    /// The key named in `.notWritable` when `writeKey(for:)` finds nothing: the mode's own
    /// setpoint in HEAT/AUTO (where the cool fallback is excluded), else the generic key.
    static func unwritableKey(for mode: ACMode?) -> String {
        mode == .heat || mode == .auto ? modeTargetKey(for: mode) : defaultTargetKey
    }

    private static func modeTargetKey(for mode: ACMode?) -> String {
        switch mode {
        case ACMode.heat?: heatTargetKey
        case ACMode.auto?: autoTargetKey
        default: coolTargetKey
        }
    }

    /// Extraction order: `temperatureInUnits[unit == C]` → `temperatureInUnits[0]` →
    /// flat `temperature`. With neither, the capability reports nothing readable or writable.
    public init(profile: DeviceProfile) {
        if let entries = profile.temperatureInUnits,
           let entry = entries.first(where: { $0.unit == "C" }) ?? entries.first {
            self.init(specs: entry.properties, unitCode: entry.unit, shape: .inUnits)
        } else if let flat = profile.resources["temperature"] {
            let units = flat["unit"]?.readableValues ?? []
            let unitCode = units.contains("C") ? "C" : (units.first ?? "C")
            self.init(specs: flat, unitCode: unitCode, shape: .flat)
        } else {
            self.init(unit: .celsius, currentReadable: false, shape: .flat, writableTargets: [:])
        }
    }

    private init(specs: [String: PropertySpec], unitCode: String, shape: TemperatureShape) {
        var targets: [String: PropertySpec.NumericRange] = [:]
        for key in Self.setpointKeys {
            if let spec = specs[key], spec.isWritable, let range = spec.writableRange {
                targets[key] = range
            }
        }
        self.init(
            unit: Self.unit(forCode: unitCode),
            currentReadable: specs["currentTemperature"]?.isReadable ?? false,
            shape: shape,
            writableTargets: targets
        )
    }

    /// `"C"` or `"F"`, as LG spells it in payloads.
    public var unitCode: String {
        unit == .fahrenheit ? "F" : "C"
    }

    static func unit(forCode code: String) -> UnitTemperature {
        code.uppercased() == "F" ? .fahrenheit : .celsius
    }
}
