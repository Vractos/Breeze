import Foundation

/// `airConJobMode.currentJobMode`. Not a closed enum: models differ, so any profile value is
/// representable and the allowed set always comes from the profile.
public struct ACMode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let cool = ACMode(rawValue: "COOL")
    public static let airDry = ACMode(rawValue: "AIR_DRY")
    public static let fan = ACMode(rawValue: "FAN")
    public static let heat = ACMode(rawValue: "HEAT")
    public static let auto = ACMode(rawValue: "AUTO")
    public static let airClean = ACMode(rawValue: "AIR_CLEAN")
    public static let energySaving = ACMode(rawValue: "ENERGY_SAVING")
    public static let aroma = ACMode(rawValue: "AROMA")

    public var displayName: LocalizedStringResource {
        switch rawValue {
        case "COOL": "Cool"
        case "AIR_DRY": "Dry"
        case "FAN": "Fan"
        case "HEAT": "Heat"
        case "AUTO": "Auto"
        case "AIR_CLEAN": "Air Clean"
        case "ENERGY_SAVING": "Energy Saving"
        case "AROMA": "Aroma"
        default: LocalizedStringResource(String.LocalizationValue(rawValue.enumConstantDisplayName))
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch rawValue {
        case "COOL": "snowflake"
        case "AIR_DRY": "drop"
        case "FAN": "wind"
        case "HEAT": "flame"
        case "AUTO": "a.circle"
        case "ENERGY_SAVING": "leaf"
        case "AIR_CLEAN": "sparkles"
        default: "circle.dashed"
        }
    }

    public var description: String { rawValue }
}
