import Foundation

/// The fan as the LG app shows it: Auto or a numbered level. Natural wind is not offered:
/// `windStrengthDetail: NATURE` reads back exactly like Auto, so it reads as
/// `.auto` here.
public enum ACFanSetting: Hashable, Sendable, CustomStringConvertible {
    case auto
    /// 1-based, slowest first; `FanCapability` maps it to the profile's raw value.
    case level(Int)

    public var displayName: LocalizedStringResource {
        switch self {
        case .auto: "Auto"
        case .level(let level): "\(level)"
        }
    }

    /// SF Symbol name.
    public var symbolName: String {
        switch self {
        case .auto: "fan.badge.automatic"
        case .level: "fan"
        }
    }

    public var description: String {
        switch self {
        case .auto: "AUTO"
        case .level(let level): "level \(level)"
        }
    }
}
