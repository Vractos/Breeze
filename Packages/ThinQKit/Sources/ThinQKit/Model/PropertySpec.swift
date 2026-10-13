import Foundation

/// One property of a device profile:
/// `{"type": "enum"|"range"|"boolean"|"number"|"string"|"list", "mode": ["r","w"], "value": {"r": …, "w": …}}`.
public struct PropertySpec: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case `enum`(readable: [String], writable: [String])
        case range(readable: NumericRange?, writable: NumericRange?)
        case boolean(writable: Bool)
        case number
        case string
        case list
        case unknown
    }

    /// `{"min", "max", "step"?, "except"?}`.
    public struct NumericRange: Sendable, Equatable {
        public var min: Double
        public var max: Double
        public var step: Double?
        public var except: [Double]

        public init(min: Double, max: Double, step: Double? = nil, except: [Double] = []) {
            self.min = min
            self.max = max
            self.step = step
            self.except = except
        }

        /// Parses a range object; `nil` if `min`/`max` are missing.
        public init?(json: JSONValue?) {
            guard let json, let min = json["min"]?.doubleValue, let max = json["max"]?.doubleValue else {
                return nil
            }
            let step = json["step"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
            let except = json["except"]?.arrayValue?.compactMap(\.doubleValue) ?? []
            self.init(min: min, max: max, step: step, except: except)
        }

        /// `min ≤ v ≤ max`, `(v − min) % step == 0`, `v ∉ except`.
        public func contains(_ value: Double) -> Bool {
            guard value.isFinite, value >= min - Self.tolerance, value <= max + Self.tolerance else {
                return false
            }
            if let step {
                let steps = (value - min) / step
                guard abs(steps - steps.rounded()) < Self.tolerance else { return false }
            }
            return !except.contains { abs($0 - value) < Self.tolerance }
        }

        /// The exact value to send for one that `contains` accepted: moved onto the nearest step,
        /// clamped to `min…max`, and a whole number when every allowed value is one (LG
        /// wants integers when the step is integral). `contains` tolerates float noise such as
        /// `23.9999999` from slider maths or °F↔°C conversion; this keeps that noise off the wire.
        public func snapped(_ value: Double) -> Double {
            var result = value
            if let step {
                result = min + ((value - min) / step).rounded() * step
                // `min + n * step` is inexact for steps like 0.1 (22.299999999999997); dividing a
                // rounded integer by 1e6 yields the double closest to the decimal value instead.
                result = (result * Self.decimalScale).rounded() / Self.decimalScale
            }
            result = Swift.min(Swift.max(result, min), max)
            return hasIntegralStep ? result.rounded() : result
        }

        /// Whether every allowed value is a whole number: an integral step starting at an
        /// integral `min`. Without a step any value in bounds is allowed, so this is `false`.
        var hasIntegralStep: Bool {
            guard let step else { return false }
            return step.rounded() == step && min.rounded() == min
        }

        // Floating-point slack for values like 0.1-steps.
        private static let tolerance = 1e-6
        // Inverse of `tolerance`, used by `snapped` to strip step-arithmetic noise.
        private static let decimalScale = 1e6
    }

    public var kind: Kind
    public var isReadable: Bool
    public var isWritable: Bool

    public init(kind: Kind, isReadable: Bool, isWritable: Bool) {
        self.kind = kind
        self.isReadable = isReadable
        self.isWritable = isWritable
    }

    /// Lenient parser: unknown types become `.unknown`, malformed values become empty sets.
    public init(json: JSONValue) {
        let modes = json["mode"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let isReadable = modes.contains("r")
        let isWritable = modes.contains("w")
        let value = json["value"]

        let kind: Kind
        switch json["type"]?.stringValue {
        case "enum":
            kind = .enum(
                readable: Self.strings(value?["r"]),
                writable: isWritable ? Self.strings(value?["w"]) : []
            )
        case "range":
            // Some profiles put {min,max,step} directly under "value" instead of under r/w.
            let flat = NumericRange(json: value)
            kind = .range(
                readable: NumericRange(json: value?["r"]) ?? (isReadable ? flat : nil),
                writable: isWritable ? (NumericRange(json: value?["w"]) ?? flat) : nil
            )
        case "boolean":
            kind = .boolean(writable: isWritable)
        case "number":
            kind = .number
        case "string":
            kind = .string
        case "list":
            kind = .list
        default:
            kind = .unknown
        }
        self.init(kind: kind, isReadable: isReadable, isWritable: isWritable)
    }

    /// Parses every object-valued member of `object` as a spec; other members are skipped.
    static func specs(in object: JSONObject) -> [String: PropertySpec] {
        object.compactMapValues { value in
            guard value.objectValue != nil else { return nil }
            return PropertySpec(json: value)
        }
    }

    /// Allowed values to write, for enums; empty otherwise.
    public var writableValues: [String] {
        if case .enum(_, let writable) = kind { return writable }
        return []
    }

    /// Allowed values to read, for enums; empty otherwise.
    public var readableValues: [String] {
        if case .enum(let readable, _) = kind { return readable }
        return []
    }

    /// The write constraints of a range property.
    public var writableRange: NumericRange? {
        if case .range(_, let writable) = kind { return writable }
        return nil
    }

    /// The read range of a range property.
    public var readableRange: NumericRange? {
        if case .range(let readable, _) = kind { return readable }
        return nil
    }

    /// Whether `value` may be written: the property must be writable and the value must satisfy
    /// enum membership, range/step/except, or the primitive type.
    public func validate(_ value: JSONValue) -> Bool {
        guard isWritable else { return false }
        switch kind {
        case .enum(_, let writable):
            guard let text = value.stringValue else { return false }
            return writable.contains(text)
        case .range(_, let writable):
            guard let number = value.doubleValue else { return false }
            // Writable with no published range: accept any number rather than block the user.
            return writable?.contains(number) ?? true
        case .boolean:
            return value.boolValue != nil
        case .number:
            return value.doubleValue?.isFinite ?? false
        case .string:
            return value.stringValue != nil
        case .list:
            return value.arrayValue != nil
        case .unknown:
            return true
        }
    }

    private static func strings(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.compactMap(\.stringValue) ?? []
    }
}
