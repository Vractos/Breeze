import Foundation
import Testing
@testable import ThinQKit

/// Loads JSON fixtures copied into the test bundle (`resources: [.copy("Fixtures")]`).
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    static func json(_ name: String) throws -> JSONValue {
        try JSONValue(jsonData: data(name))
    }

    static func profileShapeA() throws -> DeviceProfile {
        try DeviceProfile(json: json("air_conditioner-profile-example"))
    }

    static func profileShapeB() throws -> DeviceProfile {
        try DeviceProfile(json: json("air_conditioner-profile-shape-b"))
    }

    static func stateShapeA() throws -> DeviceState {
        try DeviceState(json: json("air_conditioner-object-example"))
    }

    static func stateShapeB() throws -> DeviceState {
        try DeviceState(json: json("air_conditioner-state-shape-b"))
    }
}

extension Fixture {
    /// Shape B with a single Fahrenheit entry (no Celsius to prefer).
    static func profileFahrenheitOnly() throws -> DeviceProfile {
        try DeviceProfile(json: [
            "property": [
                "operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON", "POWER_OFF"]]]],
                "airConJobMode": ["currentJobMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["COOL"]]]],
                "temperatureInUnits": [
                    ["unit": "F", "targetTemperature": ["type": "range", "mode": ["r", "w"], "value": ["w": ["min": 60, "max": 86, "step": 1]]]],
                ],
            ],
        ])
    }
}
