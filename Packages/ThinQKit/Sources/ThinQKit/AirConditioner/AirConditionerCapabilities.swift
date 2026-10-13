/// What this AC model can do, derived once from its `DeviceProfile`.
public struct AirConditionerCapabilities: Sendable, Equatable {
    /// Writable power values (normally both).
    public var powerOptions: [ACPower]
    /// Writable modes, in profile order.
    public var modes: [ACMode]
    /// Writable fan speeds, in profile order.
    public var fanSpeeds: [ACFanSpeed]
    /// `"windStrengthDetail"` when the profile has it, else `"windStrength"`.
    public var fanSpeedKey: String
    public var temperature: TemperatureCapability
    public var hasPowerSave: Bool
    public var hasVerticalSwing: Bool
    public var hasHorizontalSwing: Bool

    static let powerProperty = (resource: "operation", key: "airConOperationMode")
    static let modeProperty = (resource: "airConJobMode", key: "currentJobMode")
    static let fanResource = "airFlow"
    static let powerSaveProperty = (resource: "powerSave", key: "powerSaveEnabled")

    public init(
        powerOptions: [ACPower],
        modes: [ACMode],
        fanSpeeds: [ACFanSpeed],
        fanSpeedKey: String,
        temperature: TemperatureCapability,
        hasPowerSave: Bool,
        hasVerticalSwing: Bool,
        hasHorizontalSwing: Bool
    ) {
        self.powerOptions = powerOptions
        self.modes = modes
        self.fanSpeeds = fanSpeeds
        self.fanSpeedKey = fanSpeedKey
        self.temperature = temperature
        self.hasPowerSave = hasPowerSave
        self.hasVerticalSwing = hasVerticalSwing
        self.hasHorizontalSwing = hasHorizontalSwing
    }

    /// Throws `.missingProperty` when the profile has no `operation.airConOperationMode` or
    /// `airConJobMode.currentJobMode`, i.e. it is not an AC profile.
    public init(profile: DeviceProfile) throws(ACModelError) {
        guard let power = profile[Self.powerProperty.resource, Self.powerProperty.key] else {
            throw .missingProperty("\(Self.powerProperty.resource).\(Self.powerProperty.key)")
        }
        guard let mode = profile[Self.modeProperty.resource, Self.modeProperty.key] else {
            throw .missingProperty("\(Self.modeProperty.resource).\(Self.modeProperty.key)")
        }

        // Prefer the detailed key when present, like the official SDK does.
        let airFlow = profile.resources[Self.fanResource] ?? [:]
        let fanSpeedKey = airFlow["windStrengthDetail"] != nil ? "windStrengthDetail" : "windStrength"

        self.init(
            powerOptions: power.writableValues.compactMap(ACPower.init(rawValue:)),
            modes: mode.writableValues.map(ACMode.init(rawValue:)),
            fanSpeeds: (airFlow[fanSpeedKey]?.writableValues ?? []).map(ACFanSpeed.init(rawValue:)),
            fanSpeedKey: fanSpeedKey,
            temperature: TemperatureCapability(profile: profile),
            hasPowerSave: profile[Self.powerSaveProperty.resource, Self.powerSaveProperty.key]?.isWritable ?? false,
            hasVerticalSwing: profile["windDirection", "rotateUpDown"]?.isWritable ?? false,
            hasHorizontalSwing: profile["windDirection", "rotateLeftRight"]?.isWritable ?? false
        )
    }
}
