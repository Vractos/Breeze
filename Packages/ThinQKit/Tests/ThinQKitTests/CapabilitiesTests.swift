import Foundation
import Testing
@testable import ThinQKit

@Suite("Air-conditioner capabilities")
struct CapabilitiesTests {
    @Test func shapeA() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())

        #expect(caps.powerOptions == [.off, .on])
        #expect(caps.modes == [.airDry, .cool, .airClean])
        #expect(caps.fanSpeeds == [.high, .low, .mid])
        #expect(caps.fanSpeedKey == "windStrength")
        #expect(caps.hasPowerSave)
        #expect(!caps.hasVerticalSwing)
        #expect(!caps.hasHorizontalSwing)
        let range = PropertySpec.NumericRange(min: 18, max: 30, step: 1)
        #expect(caps.temperature == TemperatureCapability(
            unit: .celsius,
            currentReadable: true,
            shape: .flat,
            writableTargets: ["targetTemperature": range, "coolTargetTemperature": range]
        ))
        #expect(caps.temperature.writeKey(for: nil)?.range == range)
    }

    @Test func shapeBPrefersCelsiusAndDetailedFanKey() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())

        #expect(caps.modes == [.cool, .airDry, .fan, .auto, .heat])
        #expect(caps.fanSpeedKey == "windStrengthDetail")
        #expect(caps.fanSpeeds == [.slow, .low, .mid, .high, .power, .auto, .nature])
        #expect(!caps.hasPowerSave)
        #expect(caps.hasVerticalSwing)
        #expect(!caps.hasHorizontalSwing, "read-only swing is not a capability")
        #expect(caps.temperature.shape == .inUnits)
        #expect(caps.temperature.unit == .celsius)
        #expect(caps.temperature.unitCode == "C")
        #expect(caps.temperature.currentReadable)
        #expect(caps.temperature.writeKey(for: nil)?.key == "targetTemperature")
        #expect(caps.temperature.writeKey(for: nil)?.range == PropertySpec.NumericRange(min: 16, max: 30, step: 0.5, except: [29.5]))
    }

    @Test func shapeBWithOnlyFahrenheitUsesFirstEntry() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileFahrenheitOnly())
        #expect(caps.temperature.unit == .fahrenheit)
        #expect(caps.temperature.unitCode == "F")
        #expect(caps.temperature.writeKey(for: nil)?.range.max == 86)
        #expect(!caps.temperature.currentReadable)
    }

    @Test func readOnlyTargetFallsBackToCoolTarget() throws {
        let profile = try DeviceProfile(json: [
            "property": [
                "operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON"]]]],
                "airConJobMode": ["currentJobMode": ["type": "enum", "mode": ["r"], "value": ["r": ["COOL"]]]],
                "temperature": [
                    "targetTemperature": ["type": "range", "mode": ["r"], "value": ["r": ["min": 18, "max": 30, "step": 1]]],
                    "coolTargetTemperature": ["type": "range", "mode": ["w"], "value": ["w": ["min": 18, "max": 30, "step": 1]]],
                ],
            ],
        ])
        let caps = try AirConditionerCapabilities(profile: profile)
        #expect(caps.temperature.writeKey(for: nil)?.key == "coolTargetTemperature")
        #expect(caps.temperature.writeKey(for: .cool)?.key == "coolTargetTemperature")
        #expect(caps.temperature.writeKey(for: .heat) == nil, "HEAT never falls back to the cool setpoint")
        #expect(caps.temperature.writeKey(for: .auto) == nil)
        #expect(caps.temperature.writeKey(for: nil)?.range.min == 18)
        #expect(caps.modes.isEmpty, "read-only mode yields no writable modes")
        #expect(caps.fanSpeeds.isEmpty)
    }

    @Test func everyModeSpecificSetpointIsRecorded() throws {
        let profile = try DeviceProfile(json: [
            "property": [
                "operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON"]]]],
                "airConJobMode": ["currentJobMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["COOL", "HEAT", "AUTO"]]]],
                "temperature": [
                    "targetTemperature": ["type": "range", "mode": ["r"], "value": ["r": ["min": 18, "max": 30]]],
                    "heatTargetTemperature": ["type": "range", "mode": ["r", "w"], "value": ["w": ["min": 16, "max": 30, "step": 1]]],
                    "autoTargetTemperature": ["type": "range", "mode": ["w"], "value": ["w": ["min": 18, "max": 26, "step": 1]]],
                ],
            ],
        ])
        let temperature = try AirConditionerCapabilities(profile: profile).temperature
        #expect(temperature.writableTargets.keys.sorted() == ["autoTargetTemperature", "heatTargetTemperature"])
        #expect(temperature.writeKey(for: .heat)?.key == "heatTargetTemperature")
        #expect(temperature.writeKey(for: .heat)?.range.min == 16)
        #expect(temperature.writeKey(for: .auto)?.key == "autoTargetTemperature")
        #expect(temperature.writeKey(for: .cool) == nil)
        #expect(temperature.writeKey(for: nil) == nil, "no mode-agnostic setpoint")
    }

    @Test func profileWithoutTemperatureHasNoSetpoint() throws {
        let profile = try DeviceProfile(json: [
            "property": [
                "operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON", "POWER_OFF"]]]],
                "airConJobMode": ["currentJobMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["COOL"]]]],
            ],
        ])
        let caps = try AirConditionerCapabilities(profile: profile)
        #expect(caps.temperature == TemperatureCapability(unit: .celsius, currentReadable: false, shape: .flat, writableTargets: [:]))
        #expect(throws: ACModelError.notWritable("temperature.targetTemperature")) {
            try ACCommand.targetTemperature(22).payload(for: caps, currentMode: nil)
        }
    }

    @Test func noWritableTargetMeansNil() throws {
        let profile = try DeviceProfile(json: [
            "property": [
                "operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON", "POWER_OFF"]]]],
                "airConJobMode": ["currentJobMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["COOL"]]]],
                "temperature": [
                    "currentTemperature": ["type": "number", "mode": ["r"]],
                    "targetTemperature": ["type": "range", "mode": ["r"], "value": ["r": ["min": 18, "max": 30]]],
                ],
            ],
        ])
        let caps = try AirConditionerCapabilities(profile: profile)
        #expect(caps.temperature.writeKey(for: nil) == nil)
        #expect(caps.temperature.currentReadable)
    }

    @Test func nonACProfileThrows() throws {
        let profile = try DeviceProfile(json: ["property": ["washerOperation": [:]]])
        #expect(throws: ACModelError.missingProperty("operation.airConOperationMode")) {
            try AirConditionerCapabilities(profile: profile)
        }
        let noMode = try DeviceProfile(json: [
            "property": ["operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON"]]]]],
        ])
        #expect(throws: ACModelError.missingProperty("airConJobMode.currentJobMode")) {
            try AirConditionerCapabilities(profile: noMode)
        }
    }

    @Test func displayNamesAndSymbols() {
        #expect(String(localized: ACMode.cool.displayName) == "Cool")
        #expect(String(localized: ACMode.airDry.displayName) == "Dry")
        #expect(String(localized: ACMode.energySaving.displayName) == "Energy Saving")
        #expect(String(localized: ACMode(rawValue: "SUPER_TURBO").displayName) == "Super Turbo")
        #expect(ACMode.cool.symbolName == "snowflake")
        #expect(ACMode.airDry.symbolName == "drop")
        #expect(ACMode.fan.symbolName == "wind")
        #expect(ACMode.heat.symbolName == "flame")
        #expect(ACMode.auto.symbolName == "a.circle")
        #expect(ACMode.energySaving.symbolName == "leaf")
        #expect(ACMode.airClean.symbolName == "sparkles")
        #expect(String(localized: ACFanSpeed.mid.displayName) == "Medium")
        #expect(String(localized: ACFanSpeed(rawValue: "TURBO_WIND").displayName) == "Turbo Wind")
        #expect(ACFanSpeed.auto.symbolName == "fan.badge.automatic")
    }
}
