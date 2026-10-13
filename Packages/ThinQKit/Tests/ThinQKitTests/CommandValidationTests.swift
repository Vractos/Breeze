import Foundation
import Testing
@testable import ThinQKit

@Suite("Command validation")
struct CommandValidationTests {
    @Test func unknownModeRejected() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(throws: ACModelError.unsupportedMode(.heat)) { try ACCommand.mode(.heat).payload(for: caps, currentMode: nil) }
        #expect(throws: ACModelError.unsupportedMode(ACMode(rawValue: "cool"))) {
            try ACCommand.mode(ACMode(rawValue: "cool")).payload(for: caps, currentMode: nil)
        }
    }

    @Test func unknownFanSpeedRejected() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(throws: ACModelError.unsupportedFanSpeed(.auto)) { try ACCommand.fanSpeed(.auto).payload(for: caps, currentMode: nil) }
    }

    @Test(arguments: [17.0, 31.0, 22.5, -5.0])
    func shapeATargetOutOfRangeOrOffStepRejected(value: Double) throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let allowed = PropertySpec.NumericRange(min: 18, max: 30, step: 1)
        #expect(throws: ACModelError.invalidTargetTemperature(value, allowed: allowed)) {
            try ACCommand.targetTemperature(value).payload(for: caps, currentMode: nil)
        }
    }

    @Test(arguments: [29.5, 22.25, 15.5])
    func shapeBTargetInExceptOrOffStepRejected(value: Double) throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        #expect(throws: ACModelError.self) { try ACCommand.targetTemperature(value).payload(for: caps, currentMode: nil) }
    }

    @Test func notWritableRejected() throws {
        let shapeB = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        #expect(throws: ACModelError.notWritable("powerSave.powerSaveEnabled")) {
            try ACCommand.powerSave(true).payload(for: shapeB, currentMode: nil)
        }

        var caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        caps.temperature.writableTargets = [:]
        #expect(throws: ACModelError.notWritable("temperature.targetTemperature")) {
            try ACCommand.targetTemperature(22).payload(for: caps, currentMode: nil)
        }
        caps.modes = []
        #expect(throws: ACModelError.notWritable("airConJobMode.currentJobMode")) {
            try ACCommand.mode(.cool).payload(for: caps, currentMode: nil)
        }
        caps.fanSpeeds = []
        #expect(throws: ACModelError.notWritable("airFlow.windStrength")) {
            try ACCommand.fanSpeed(.high).payload(for: caps, currentMode: nil)
        }
        caps.powerOptions = []
        #expect(throws: ACModelError.notWritable("operation.airConOperationMode")) {
            try ACCommand.power(.on).payload(for: caps, currentMode: nil)
        }
        caps.powerOptions = [.on]
        #expect(throws: ACModelError.unsupportedPower(.off)) { try ACCommand.power(.off).payload(for: caps, currentMode: nil) }
    }
}
