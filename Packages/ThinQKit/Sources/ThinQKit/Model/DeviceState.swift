/// A device's current values (`GET devices/{id}/state`), same tree shape as the profile.
public struct DeviceState: Sendable, Equatable {
    /// resource → value (usually an object; `temperatureInUnits` is an array).
    public var values: JSONObject

    public init(values: JSONObject = [:]) {
        self.values = values
    }

    public init(json: JSONValue) throws(ThinQError) {
        guard let object = json.objectValue else {
            throw ThinQError.decoding(path: "state", underlying: JSONShapeError("state is not an object"))
        }
        self.init(values: object)
    }

    /// `values[resource][key]`, for object-valued resources.
    public subscript(resource: String, key: String) -> JSONValue? {
        values[resource]?[key]
    }

    /// Merges a partial state tree (MQTT `report`, optimistic command) into this state:
    /// objects merge key by key (recursively), unit-tagged arrays such as `temperatureInUnits`
    /// merge entry by entry matched on `unit`, anything else is replaced.
    public mutating func merge(delta: JSONObject) {
        for (resource, value) in delta {
            values[resource] = Self.merged(values[resource], value)
        }
    }

    /// Non-mutating `merge(delta:)`.
    public func merging(delta: JSONObject) -> DeviceState {
        var copy = self
        copy.merge(delta: delta)
        return copy
    }

    private static func merged(_ existing: JSONValue?, _ incoming: JSONValue) -> JSONValue {
        switch (existing, incoming) {
        case (.object(var base)?, .object(let changes)):
            for (key, value) in changes {
                base[key] = merged(base[key], value)
            }
            return .object(base)
        case (.array(let base)?, .array(let changes)):
            return .array(mergedUnitArrays(base, changes) ?? changes)
        default:
            return incoming
        }
    }

    /// `nil` unless every incoming element is an object with a string `unit`.
    private static func mergedUnitArrays(_ base: [JSONValue], _ changes: [JSONValue]) -> [JSONValue]? {
        let incomingUnits = changes.map { $0["unit"]?.stringValue }
        guard !changes.isEmpty, incomingUnits.allSatisfy({ $0 != nil }) else { return nil }

        var result = base
        for change in changes {
            let unit = change["unit"]?.stringValue
            if let index = result.firstIndex(where: { $0["unit"]?.stringValue == unit }) {
                result[index] = merged(result[index], change)
            } else {
                result.append(change)
            }
        }
        return result
    }
}
