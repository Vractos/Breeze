#if DEBUG
import Foundation
import ThinQKit

/// A plausible split AC for previews: shape-A temperature 18–30 °C in whole degrees, five modes,
/// Eco mode, and a real unit's fan (Auto plus five levels), up/down swing, display light and
/// sleep timer. Built in code so no JSON ships in the app bundle.
nonisolated enum PreviewFixtures {
    /// Shaped like a real account: two ACs share the alias "Ar-condicionado" (they
    /// live in different LG homes, which the API doesn't expose) and a third is "Ar Quarto". The
    /// first is the one the previews control.
    static let device = DeviceSummary(
        id: "preview-7c41e09b2d5fa3f2",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "RAC_0B0001_WW",
        alias: "Ar-condicionado"
    )

    static let sameAliasDevice = DeviceSummary(
        id: "preview-e13d88a06c47b19e",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "RAC_056905_WW",
        alias: "Ar-condicionado"
    )

    static let bedroom = DeviceSummary(
        id: "preview-52af0c97d3e81c06",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "RAC_056905_WW",
        alias: "Ar Quarto"
    )

    static let devices = [device, sameAliasDevice, bedroom]

    /// What the ACs the previews don't control report (Settings › Device's live preview).
    static let otherDeviceStates: [String: DeviceState] = [
        sameAliasDevice.id: state(power: .off, current: 29),
        bedroom.id: state(power: .on, target: 22, current: 23),
    ]

    static var profile: DeviceProfile {
        DeviceProfile(
            resources: [
                "operation": ["airConOperationMode": enumSpec(["POWER_ON", "POWER_OFF"])],
                "airConJobMode": ["currentJobMode": enumSpec(["COOL", "AIR_DRY", "FAN", "HEAT", "AUTO"])],
                "airFlow": [
                    "windStrength": enumSpec(["LOW", "MID", "HIGH", "AUTO"]),
                    "windStrengthDetail": enumSpec(["NATURE"] + fanDetailLevels),
                    "windStep": PropertySpec(
                        kind: .range(readable: .init(min: 1, max: 5, step: 1), writable: .init(min: 1, max: 5, step: 1)),
                        isReadable: true,
                        isWritable: true
                    ),
                ],
                "windDirection": [
                    "rotateUpDown": PropertySpec(kind: .boolean(writable: true), isReadable: true, isWritable: true),
                ],
                "display": ["light": enumSpec(["ON", "OFF"])],
                "sleepTimer": [
                    "relativeHourToStop": PropertySpec(kind: .number, isReadable: true, isWritable: true),
                    "relativeMinuteToStop": PropertySpec(kind: .number, isReadable: true, isWritable: true),
                    "relativeStopTimer": PropertySpec(
                        kind: .enum(readable: ["SET", "UNSET"], writable: ["UNSET"]),
                        isReadable: true,
                        isWritable: true
                    ),
                ],
                "temperature": [
                    "currentTemperature": PropertySpec(
                        kind: .range(readable: .init(min: -20, max: 60), writable: nil),
                        isReadable: true,
                        isWritable: false
                    ),
                    "targetTemperature": PropertySpec(
                        kind: .range(readable: .init(min: 18, max: 30, step: 1), writable: .init(min: 18, max: 30, step: 1)),
                        isReadable: true,
                        isWritable: true
                    ),
                    "unit": PropertySpec(kind: .enum(readable: ["C"], writable: []), isReadable: true, isWritable: false),
                ],
                "powerSave": [
                    "powerSaveEnabled": PropertySpec(kind: .boolean(writable: true), isReadable: true, isWritable: true),
                ],
            ],
            temperatureInUnits: nil,
            raw: .null
        )
    }

    /// `sleepMinutes`: the time left on a running sleep timer, `nil` for none.
    static func state(
        power: ACPower,
        mode: ACMode = .cool,
        fan: ACFanSetting = .auto,
        target: Double = 23,
        current: Double = 26,
        powerSave: Bool = false,
        swing: Bool = true,
        light: Bool = true,
        sleepMinutes: Int? = nil
    ) -> DeviceState {
        DeviceState(values: [
            "operation": ["airConOperationMode": .string(power.rawValue)],
            "airConJobMode": ["currentJobMode": .string(mode.rawValue)],
            "airFlow": airFlow(for: fan),
            "temperature": [
                "currentTemperature": .number(current),
                "targetTemperature": .number(target),
                "unit": "C",
            ],
            "powerSave": ["powerSaveEnabled": .bool(powerSave)],
            "windDirection": ["rotateUpDown": .bool(swing)],
            "display": ["light": light ? "ON" : "OFF"],
            "sleepTimer": sleepTimer(minutes: sleepMinutes),
        ])
    }

    /// The profile's levels 1…5, as `FanCapability` orders them.
    private static let fanDetailLevels = ["LOW", "LOW_MID", "MID", "MID_HIGH", "HIGH"]
    /// The coarse `windStrength` the real unit reports with each level.
    private static let fanCoarseLevels = ["LOW", "MID", "MID", "HIGH", "HIGH"]

    /// What the real unit reports: Auto as `AUTO` + `NATURE` without `windStep`; a level in all
    /// three keys.
    private static func airFlow(for fan: ACFanSetting) -> JSONValue {
        guard case .level(let level) = fan, fanDetailLevels.indices.contains(level - 1) else {
            return ["windStrength": "AUTO", "windStrengthDetail": "NATURE"]
        }
        return [
            "windStrength": .string(fanCoarseLevels[level - 1]),
            "windStrengthDetail": .string(fanDetailLevels[level - 1]),
            "windStep": .number(Double(level)),
        ]
    }

    /// While SET the state reports the time left.
    private static func sleepTimer(minutes: Int?) -> JSONValue {
        guard let minutes else { return ["relativeStopTimer": "UNSET"] }
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        return [
            "relativeStopTimer": "SET",
            "relativeHourToStop": .number(Double(hours)),
            "relativeMinuteToStop": .number(Double(rest)),
        ]
    }

    private static func enumSpec(_ values: [String]) -> PropertySpec {
        PropertySpec(kind: .enum(readable: values, writable: values), isReadable: true, isWritable: true)
    }
}
#endif
