import Foundation

/// A JSON object: resource → value, key → value.
public typealias JSONObject = [String: JSONValue]

/// A lossless, `Sendable` JSON tree. Used for everything ThinQKit does not model explicitly, so
/// unknown resources in profiles and states never break decoding.
public enum JSONValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object(JSONObject)
}

// MARK: - Accessors

extension JSONValue {
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: JSONObject? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Object member lookup; `nil` when `self` is not an object or the key is absent.
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - Literals

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(JSONObject(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Order matters: Bool must be tried before Double so `true` never becomes 1.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode(JSONObject.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            // LG wants integers when the step is integral; emitting integral doubles as Int64
            // also avoids "22.0" on the wire. Non-finite numbers are not valid JSON → null.
            if !value.isFinite {
                try container.encodeNil()
            } else if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Data conversion

extension JSONValue {
    /// Parses UTF-8 JSON data.
    public init(jsonData: Data) throws(ThinQError) {
        do {
            self = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        } catch {
            throw ThinQError.decoding(path: "$", underlying: error)
        }
    }

    /// Serialises the value. `pretty` also sorts keys, which keeps CLI dumps and fixtures stable.
    public func jsonData(pretty: Bool = false) throws(ThinQError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(self)
        } catch {
            throw ThinQError.encoding(underlying: error)
        }
    }

    /// Compact JSON text, for diagnostics. Falls back to `"<unencodable>"` (cannot happen in
    /// practice because `encode(to:)` maps non-finite numbers to null).
    public var compactDescription: String {
        guard let data = try? jsonData(), let text = String(data: data, encoding: .utf8) else {
            return "<unencodable>"
        }
        return text
    }
}
