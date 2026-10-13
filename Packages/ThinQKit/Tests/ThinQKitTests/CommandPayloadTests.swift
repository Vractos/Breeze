import Foundation
import Testing
@testable import ThinQKit

@Suite("Command payloads")
struct CommandPayloadTests {
    @Test func shapeAPayloads() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())

        #expect(try ACCommand.power(.on).payload(for: caps, currentMode: nil) == ["operation": ["airConOperationMode": "POWER_ON"]])
        #expect(try ACCommand.power(.off).payload(for: caps, currentMode: nil) == ["operation": ["airConOperationMode": "POWER_OFF"]])
        #expect(try ACCommand.mode(.cool).payload(for: caps, currentMode: nil) == ["airConJobMode": ["currentJobMode": "COOL"]])
        #expect(try ACCommand.fanSpeed(.high).payload(for: caps, currentMode: nil) == ["airFlow": ["windStrength": "HIGH"]])
        #expect(try ACCommand.targetTemperature(22).payload(for: caps, currentMode: nil) == ["temperature": ["targetTemperature": 22]])
        #expect(try ACCommand.powerSave(true).payload(for: caps, currentMode: nil) == ["powerSave": ["powerSaveEnabled": true]])
        #expect(try ACCommand.powerSave(false).payload(for: caps, currentMode: nil) == ["powerSave": ["powerSaveEnabled": false]])
    }

    @Test func shapeBPayloads() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())

        #expect(try ACCommand.fanSpeed(.nature).payload(for: caps, currentMode: nil) == ["airFlow": ["windStrengthDetail": "NATURE"]])
        #expect(try ACCommand.targetTemperature(22.5).payload(for: caps, currentMode: nil) == [
            "temperatureInUnits": ["targetTemperature": 22.5, "unit": "C"],
        ])
        #expect(try ACCommand.mode(.heat).payload(for: caps, currentMode: nil) == ["airConJobMode": ["currentJobMode": "HEAT"]])
    }

    @Test func coolTargetFallbackKeyIsUsedInPayload() throws {
        var caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        caps.temperature.writableTargets = ["coolTargetTemperature": PropertySpec.NumericRange(min: 16, max: 30, step: 0.5)]
        #expect(try ACCommand.targetTemperature(24).payload(for: caps, currentMode: .cool) == [
            "temperatureInUnits": ["coolTargetTemperature": 24, "unit": "C"],
        ])
    }

    // MARK: - Setpoint key by mode

    private static let range = PropertySpec.NumericRange(min: 16, max: 30, step: 1)

    /// Shape-A caps whose writable setpoints are exactly `keys`.
    private func flatCaps(writable keys: [String]) throws -> AirConditionerCapabilities {
        var caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        caps.temperature.writableTargets = Dictionary(uniqueKeysWithValues: keys.map { ($0, Self.range) })
        return caps
    }

    @Test(arguments: [nil, ACMode.cool, .heat, .auto, .fan])
    func officialFixtureAlwaysWritesTargetTemperature(mode: ACMode?) throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(try ACCommand.targetTemperature(24).payload(for: caps, currentMode: mode) == [
            "temperature": ["targetTemperature": 24],
        ])
    }

    @Test(arguments: [nil, ACMode.cool, .fan, .airDry])
    func readOnlyTargetWritesCoolTargetOutsideHeatAndAuto(mode: ACMode?) throws {
        let caps = try flatCaps(writable: ["coolTargetTemperature"])
        #expect(try ACCommand.targetTemperature(24).payload(for: caps, currentMode: mode) == [
            "temperature": ["coolTargetTemperature": 24],
        ])
    }

    @Test func heatNeverFallsBackToTheCoolSetpoint() throws {
        let caps = try flatCaps(writable: ["coolTargetTemperature"])
        #expect(throws: ACModelError.notWritable("temperature.heatTargetTemperature")) {
            try ACCommand.targetTemperature(24).payload(for: caps, currentMode: .heat)
        }
        #expect(throws: ACModelError.notWritable("temperature.autoTargetTemperature")) {
            try ACCommand.targetTemperature(24).payload(for: caps, currentMode: .auto)
        }
    }

    @Test func heatAndAutoWriteTheirOwnSetpoint() throws {
        let caps = try flatCaps(writable: ["coolTargetTemperature", "heatTargetTemperature", "autoTargetTemperature"])
        #expect(try ACCommand.targetTemperature(24).payload(for: caps, currentMode: .heat) == [
            "temperature": ["heatTargetTemperature": 24],
        ])
        #expect(try ACCommand.targetTemperature(24).payload(for: caps, currentMode: .auto) == [
            "temperature": ["autoTargetTemperature": 24],
        ])
        #expect(try ACCommand.targetTemperature(24).payload(for: caps, currentMode: .cool) == [
            "temperature": ["coolTargetTemperature": 24],
        ])
    }

    @Test func valueIsValidatedAgainstTheChosenKeysRange() throws {
        var caps = try flatCaps(writable: [])
        let heat = PropertySpec.NumericRange(min: 20, max: 26, step: 1)
        caps.temperature.writableTargets = ["coolTargetTemperature": Self.range, "heatTargetTemperature": heat]
        #expect(throws: ACModelError.invalidTargetTemperature(17, allowed: heat)) {
            try ACCommand.targetTemperature(17).payload(for: caps, currentMode: .heat)
        }
        #expect(try ACCommand.targetTemperature(17).payload(for: caps, currentMode: .cool) == [
            "temperature": ["coolTargetTemperature": 17],
        ])
    }

    @Test func fahrenheitOnlyProfileTagsThePayloadWithF() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileFahrenheitOnly())
        #expect(try ACCommand.targetTemperature(72).payload(for: caps, currentMode: nil) == [
            "temperatureInUnits": ["targetTemperature": 72, "unit": "F"],
        ])
    }

    // MARK: - Snapping

    private func wireText(_ value: Double, caps: AirConditionerCapabilities) throws -> String {
        let body = try ACCommand.targetTemperature(value).payload(for: caps, currentMode: nil)
        return String(decoding: try JSONValue.object(body).jsonData(), as: UTF8.self)
    }

    @Test(arguments: [(23.9999999, 24), (24.000000000000004, 24), (30.0000005, 30), (17.9999999, 18)])
    func nearStepValuesAreSentAsTheExactInteger(value: Double, expected: Int) throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(try wireText(value, caps: caps) == #"{"temperature":{"targetTemperature":\#(expected)}}"#)
    }

    @Test func halfStepsAreSnappedButKeepTheirFraction() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        #expect(try wireText(22.4999999, caps: caps) == #"{"temperatureInUnits":{"targetTemperature":22.5,"unit":"C"}}"#)
    }

    @Test func optimisticApplyUsesTheSnappedValue() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        var state = try Fixture.stateShapeA()
        ACCommand.targetTemperature(23.9999999).apply(to: &state, caps: caps)
        #expect(state["temperature", "targetTemperature"] == 24)
    }

    @Test func integralTemperaturesGoOnTheWireAsIntegers() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(try wireText(22, caps: caps) == #"{"temperature":{"targetTemperature":22}}"#)

        let shapeB = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        #expect(try wireText(22.5, caps: shapeB) == #"{"temperatureInUnits":{"targetTemperature":22.5,"unit":"C"}}"#)
    }
}
