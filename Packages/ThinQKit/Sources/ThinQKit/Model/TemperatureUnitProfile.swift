/// One entry of a shape-B `temperatureInUnits` profile list:
/// `{"unit": "C", "currentTemperature": spec, "targetTemperature": spec, …}`.
public struct TemperatureUnitProfile: Sendable, Equatable {
    /// `"C"` or `"F"`.
    public var unit: String
    /// Every spec in the entry, keyed by property name (`targetTemperature`, `coolTargetTemperature`, …).
    public var properties: [String: PropertySpec]

    public init(unit: String, properties: [String: PropertySpec]) {
        self.unit = unit
        self.properties = properties
    }

    /// `nil` when the entry has no recognisable unit.
    public init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        let unit: String?
        if let text = object["unit"]?.stringValue {
            unit = text
        } else {
            // Tolerate the unit being an enum spec rather than a plain string.
            unit = object["unit"].map(PropertySpec.init(json:))?.readableValues.first
        }
        guard let unit else { return nil }

        // `unit` is excluded explicitly: it may itself be an enum spec object.
        let properties = PropertySpec.specs(in: object.filter { $0.key != "unit" })
        self.init(unit: unit, properties: properties)
    }

    public subscript(key: String) -> PropertySpec? {
        properties[key]
    }
}
