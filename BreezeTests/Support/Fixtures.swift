import Foundation
@testable import Breeze
import ThinQKit

/// LG's official API examples, from BreezeTests/Fixtures.
enum Fixtures {
    struct MissingFixture: Error {
        let name: String
    }

    static func json(_ name: String) throws -> JSONValue {
        let bundle = Bundle(for: FixtureBundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw MissingFixture(name: name)
        }
        return try JSONValue(jsonData: Data(contentsOf: url))
    }

    /// Shape A profile: modes AIR_DRY/COOL/AIR_CLEAN, fan HIGH/LOW/MID, target 18–30 step 1.
    static func profile() throws -> DeviceProfile {
        try DeviceProfile(json: json("air_conditioner-profile-example"))
    }

    /// A profile whose only setpoints are `coolTargetTemperature` (18–30) and
    /// `heatTargetTemperature` (16–30): the key to write depends on the mode. Modes COOL/HEAT.
    static func coolHeatProfile() throws -> DeviceProfile {
        let readWrite: JSONValue = ["r", "w"]
        return try DeviceProfile(json: [
            "property": [
                "airConJobMode": [
                    "currentJobMode": ["mode": readWrite, "type": "enum", "value": ["r": ["COOL", "HEAT"], "w": ["COOL", "HEAT"]]],
                ],
                "operation": [
                    "airConOperationMode": [
                        "mode": readWrite,
                        "type": "enum",
                        "value": ["r": ["POWER_OFF", "POWER_ON"], "w": ["POWER_OFF", "POWER_ON"]],
                    ],
                ],
                "temperature": [
                    "currentTemperature": ["mode": ["r"], "type": "number"],
                    "coolTargetTemperature": ["mode": ["w"], "type": "range", "value": ["w": ["max": 30, "min": 18, "step": 1]]],
                    "heatTargetTemperature": ["mode": ["w"], "type": "range", "value": ["w": ["max": 30, "min": 16, "step": 1]]],
                ],
            ],
        ])
    }

    /// Power OFF, mode FAN, fan HIGH, current 27, target 24.5.
    static func offState() throws -> DeviceState {
        try DeviceState(json: json("air_conditioner-object-example"))
    }

    /// The fixture state, switched on in COOL with target 24.
    static func onState(target: Double = 24) throws -> DeviceState {
        try offState().merging(delta: [
            "operation": ["airConOperationMode": "POWER_ON"],
            "airConJobMode": ["currentJobMode": "COOL"],
            "temperature": ["targetTemperature": .number(target)],
        ])
    }

    static let livingRoomAC = DeviceSummary(
        id: "ac-living-room",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "S4-W12JA3AA",
        alias: "Living room"
    )

    static let bedroomAC = DeviceSummary(
        id: "ac-bedroom",
        deviceType: DeviceSummary.airConditionerType,
        modelName: "S4-W12JA3AA",
        alias: "Bedroom"
    )

    static let washer = DeviceSummary(
        id: "washer-1",
        deviceType: "DEVICE_WASHER",
        modelName: "WM",
        alias: "Washer"
    )
}
