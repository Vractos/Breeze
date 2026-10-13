/// A device's capabilities as a generic tree (`GET devices/{id}/profile`). AC semantics live in
/// `AirConditionerCapabilities`.
public struct DeviceProfile: Sendable, Equatable {
    /// resource → key → spec, e.g. `"airConJobMode"` → `"currentJobMode"` → spec.
    public var resources: [String: [String: PropertySpec]]
    /// Shape-B temperature list, when the profile has one.
    public var temperatureInUnits: [TemperatureUnitProfile]?
    /// The full `response` payload, for the CLI dump and debugging.
    public var raw: JSONValue

    public init(
        resources: [String: [String: PropertySpec]],
        temperatureInUnits: [TemperatureUnitProfile]?,
        raw: JSONValue
    ) {
        self.resources = resources
        self.temperatureInUnits = temperatureInUnits
        self.raw = raw
    }

    /// Parses `{"notification": …, "property": {<resource>: {<key>: <spec>}}}`. Resources whose
    /// value is not an object (other than `temperatureInUnits`) are kept only in `raw`.
    public init(json: JSONValue) throws(ThinQError) {
        guard let property = json["property"]?.objectValue else {
            throw ThinQError.decoding(path: "profile.property", underlying: JSONShapeError("missing property object"))
        }

        var resources: [String: [String: PropertySpec]] = [:]
        var temperatureInUnits: [TemperatureUnitProfile]?
        for (resource, value) in property {
            if resource == "temperatureInUnits", let entries = value.arrayValue {
                temperatureInUnits = entries.compactMap(TemperatureUnitProfile.init(json:))
                continue
            }
            guard let keys = value.objectValue else { continue }
            resources[resource] = PropertySpec.specs(in: keys)
        }
        self.init(resources: resources, temperatureInUnits: temperatureInUnits, raw: json)
    }

    public subscript(resource: String, key: String) -> PropertySpec? {
        resources[resource]?[key]
    }
}
