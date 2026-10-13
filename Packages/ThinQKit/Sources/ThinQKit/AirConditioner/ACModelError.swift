/// Errors from interpreting a profile as an air conditioner or validating a command against it.
public enum ACModelError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The profile lacks a property every AC must have (`resource.key`).
    case missingProperty(String)
    /// The property exists but this model does not allow writing it (`resource.key`).
    case notWritable(String)
    case unsupportedPower(ACPower)
    case unsupportedMode(ACMode)
    case unsupportedFanSpeed(ACFanSpeed)
    /// Out of range, not on a step, or in the `except` list.
    case invalidTargetTemperature(Double, allowed: PropertySpec.NumericRange)

    public var description: String {
        switch self {
        case .missingProperty(let path):
            "Profile has no \(path); is this an air conditioner?"
        case .notWritable(let path):
            "\(path) is not writable on this model"
        case .unsupportedPower(let power):
            "Power \(power.rawValue) is not allowed by the profile"
        case .unsupportedMode(let mode):
            "Mode \(mode.rawValue) is not supported by this model"
        case .unsupportedFanSpeed(let speed):
            "Fan speed \(speed.rawValue) is not supported by this model"
        case .invalidTargetTemperature(let value, let allowed):
            "Target \(value.formatted()) is not allowed (min \(allowed.min.formatted()), max \(allowed.max.formatted())"
                + (allowed.step.map { ", step \($0.formatted())" } ?? "")
                + (allowed.except.isEmpty ? "" : ", except \(allowed.except.map { $0.formatted() })")
                + ")"
        }
    }
}
