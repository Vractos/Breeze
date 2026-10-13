import Foundation

/// `airFlow.windStrength` / `airFlow.windStrengthDetail`. Open set, like `ACMode`.
public struct ACFanSpeed: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let auto = ACFanSpeed(rawValue: "AUTO")
    public static let slow = ACFanSpeed(rawValue: "SLOW")
    public static let low = ACFanSpeed(rawValue: "LOW")
    public static let mid = ACFanSpeed(rawValue: "MID")
    public static let high = ACFanSpeed(rawValue: "HIGH")
    public static let power = ACFanSpeed(rawValue: "POWER")
    public static let nature = ACFanSpeed(rawValue: "NATURE")

    public var displayName: LocalizedStringResource {
        switch rawValue {
        case "AUTO": "Auto"
        case "SLOW": "Slow"
        case "LOW": "Low"
        case "MID": "Medium"
        case "HIGH": "High"
        case "POWER": "Power"
        case "NATURE": "Natural"
        default: LocalizedStringResource(String.LocalizationValue(rawValue.enumConstantDisplayName))
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch rawValue {
        case "AUTO": "fan.badge.automatic"
        case "SLOW": "tortoise"
        case "LOW": "gauge.with.dots.needle.33percent"
        case "MID": "gauge.with.dots.needle.50percent"
        case "HIGH": "gauge.with.dots.needle.67percent"
        case "POWER": "gauge.with.dots.needle.100percent"
        case "NATURE": "leaf"
        default: "fan"
        }
    }

    public var description: String { rawValue }
}
