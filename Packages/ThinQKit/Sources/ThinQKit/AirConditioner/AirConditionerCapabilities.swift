/// What this AC model can do, derived once from its `DeviceProfile`.
public struct AirConditionerCapabilities: Sendable, Equatable {
    /// Writable power values (normally both).
    public var powerOptions: [ACPower]
    /// Writable modes, in profile order.
    public var modes: [ACMode]
    public var fan: FanCapability
    public var temperature: TemperatureCapability
    public var hasPowerSave: Bool
    /// `windDirection.rotateUpDown` is writable (swing on/off; the API has no vane angles).
    public var hasVerticalSwing: Bool
    /// `windDirection.rotateLeftRight` is writable.
    public var hasHorizontalSwing: Bool
    /// `display.light` is writable with both ON and OFF (models with `LEVEL_n` values get no toggle).
    public var hasDisplayLight: Bool
    /// `sleepTimer.relativeHourToStop` is writable.
    public var hasSleepTimer: Bool

    static let powerProperty = (resource: "operation", key: "airConOperationMode")
    static let modeProperty = (resource: "airConJobMode", key: "currentJobMode")
    static let powerSaveProperty = (resource: "powerSave", key: "powerSaveEnabled")
    static let verticalSwingProperty = (resource: "windDirection", key: "rotateUpDown")
    static let horizontalSwingProperty = (resource: "windDirection", key: "rotateLeftRight")
    static let displayLightProperty = (resource: "display", key: "light")

    public init(
        powerOptions: [ACPower],
        modes: [ACMode],
        fan: FanCapability,
        temperature: TemperatureCapability,
        hasPowerSave: Bool,
        hasVerticalSwing: Bool,
        hasHorizontalSwing: Bool,
        hasDisplayLight: Bool,
        hasSleepTimer: Bool
    ) {
        self.powerOptions = powerOptions
        self.modes = modes
        self.fan = fan
        self.temperature = temperature
        self.hasPowerSave = hasPowerSave
        self.hasVerticalSwing = hasVerticalSwing
        self.hasHorizontalSwing = hasHorizontalSwing
        self.hasDisplayLight = hasDisplayLight
        self.hasSleepTimer = hasSleepTimer
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
        let light = profile[Self.displayLightProperty.resource, Self.displayLightProperty.key]?.writableValues ?? []

        self.init(
            powerOptions: power.writableValues.compactMap(ACPower.init(rawValue:)),
            modes: mode.writableValues.map(ACMode.init(rawValue:)),
            fan: FanCapability(airFlow: profile.resources[FanCapability.resource] ?? [:]),
            temperature: TemperatureCapability(profile: profile),
            hasPowerSave: Self.isWritable(Self.powerSaveProperty, in: profile),
            hasVerticalSwing: Self.isWritable(Self.verticalSwingProperty, in: profile),
            hasHorizontalSwing: Self.isWritable(Self.horizontalSwingProperty, in: profile),
            hasDisplayLight: light.contains("ON") && light.contains("OFF"),
            hasSleepTimer: Self.isWritable((ACCommand.sleepTimerResource, ACCommand.sleepHourKey), in: profile)
        )
    }

    private static func isWritable(_ property: (resource: String, key: String), in profile: DeviceProfile) -> Bool {
        profile[property.resource, property.key]?.isWritable ?? false
    }
}
