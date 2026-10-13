#if DEBUG
import Foundation
import ThinQKit

/// A plausible split AC for previews: shape-A temperature 18–30 °C in whole degrees, five modes,
/// four fan speeds and Eco mode. Built in code so no JSON ships in the app bundle.
nonisolated enum PreviewFixtures {
    static let device = DeviceSummary(
        id: "preview-living-room",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "S4-W12JA3AA",
        alias: "Living Room"
    )

    static let bedroom = DeviceSummary(
        id: "preview-bedroom",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "S4-W09JA3AA",
        alias: "Bedroom"
    )

    static var profile: DeviceProfile {
        DeviceProfile(
            resources: [
                "operation": ["airConOperationMode": enumSpec(["POWER_ON", "POWER_OFF"])],
                "airConJobMode": ["currentJobMode": enumSpec(["COOL", "AIR_DRY", "FAN", "HEAT", "AUTO"])],
                "airFlow": ["windStrength": enumSpec(["AUTO", "LOW", "MID", "HIGH"])],
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

    static func state(
        power: ACPower,
        mode: ACMode = .cool,
        fanSpeed: ACFanSpeed = .auto,
        target: Double = 23,
        current: Double = 26,
        powerSave: Bool = false
    ) -> DeviceState {
        DeviceState(values: [
            "operation": ["airConOperationMode": .string(power.rawValue)],
            "airConJobMode": ["currentJobMode": .string(mode.rawValue)],
            "airFlow": ["windStrength": .string(fanSpeed.rawValue)],
            "temperature": [
                "currentTemperature": .number(current),
                "targetTemperature": .number(target),
                "unit": "C",
            ],
            "powerSave": ["powerSaveEnabled": .bool(powerSave)],
        ])
    }

    private static func enumSpec(_ values: [String]) -> PropertySpec {
        PropertySpec(kind: .enum(readable: values, writable: values), isReadable: true, isWritable: true)
    }
}
#endif
