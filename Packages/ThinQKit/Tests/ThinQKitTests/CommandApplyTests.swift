import Foundation
import Testing
@testable import ThinQKit

@Suite("Optimistic apply")
struct CommandApplyTests {
    @Test func shapeAApplyUpdatesOnlyTheTouchedKeys() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        var state = try Fixture.stateShapeA()

        ACCommand.power(.on).apply(to: &state, caps: caps)
        ACCommand.mode(.cool).apply(to: &state, caps: caps)
        ACCommand.fan(.level(1)).apply(to: &state, caps: caps)
        ACCommand.targetTemperature(22).apply(to: &state, caps: caps)
        ACCommand.powerSave(true).apply(to: &state, caps: caps)

        #expect(state["temperature", "currentTemperature"] == 27)
        #expect(state["airFlow", "windStep"] == 5)
        #expect(AirConditionerSnapshot(state: state, capabilities: caps) == AirConditionerSnapshot(
            power: .on,
            mode: .cool,
            fan: .level(1),
            currentTemperature: Measurement(value: 27, unit: .celsius),
            targetTemperature: Measurement(value: 22, unit: .celsius),
            powerSave: true,
            sleepTimer: .off
        ))
    }

    @Test func shapeBApplyMergesIntoTheMatchingUnitEntry() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        var state = try Fixture.stateShapeB()

        ACCommand.targetTemperature(20).apply(to: &state, caps: caps)
        ACCommand.fan(.level(2)).apply(to: &state, caps: caps)

        let entries = try #require(state.values["temperatureInUnits"]?.arrayValue)
        #expect(entries.count == 2)
        #expect(entries.first { $0["unit"] == "C" } == ["unit": "C", "currentTemperature": 24, "targetTemperature": 20])
        #expect(entries.first { $0["unit"] == "F" } == ["unit": "F", "currentTemperature": 75, "targetTemperature": 72])
        #expect(state["airFlow", "windStrengthDetail"] == "LOW")
        #expect(state["airFlow", "windStrength"] == "LOW", "the coarse key follows, so it can't read as Auto or another level")
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).targetTemperature == Measurement(value: 20, unit: .celsius))
    }

    // MARK: - State shape or unit differs from the capability

    /// Applies `.targetTemperature(22)` and returns the snapshots before and after.
    private func applyTwentyTwo(
        to state: DeviceState,
        caps: AirConditionerCapabilities
    ) -> (before: AirConditionerSnapshot, after: AirConditionerSnapshot, state: DeviceState) {
        var state = state
        let before = AirConditionerSnapshot(state: state, capabilities: caps)
        ACCommand.targetTemperature(22).apply(to: &state, caps: caps)
        return (before, AirConditionerSnapshot(state: state, capabilities: caps), state)
    }

    @Test func flatCapsWithListStateKeepsCurrentTemperature() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let state = DeviceState(values: ["temperatureInUnits": [["unit": "C", "currentTemperature": 21, "targetTemperature": 23]]])
        let result = applyTwentyTwo(to: state, caps: caps)

        #expect(result.before.currentTemperature == Measurement(value: 21, unit: .celsius))
        #expect(result.after.currentTemperature == result.before.currentTemperature)
        #expect(result.after.targetTemperature == Measurement(value: 22, unit: .celsius))
        #expect(result.state.values["temperature"] == nil, "no flat sibling is created")
    }

    @Test func listCapsWithFlatStateKeepsCurrentTemperature() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        let result = applyTwentyTwo(to: try Fixture.stateShapeA(), caps: caps)

        #expect(result.before.currentTemperature == Measurement(value: 27, unit: .celsius))
        #expect(result.after.currentTemperature == result.before.currentTemperature)
        #expect(result.after.targetTemperature == Measurement(value: 22, unit: .celsius))
        #expect(result.state.values["temperatureInUnits"] == nil, "no list sibling is created")
    }

    @Test func celsiusCapsWithFahrenheitOnlyStateWritesTheFahrenheitEntry() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        let state = DeviceState(values: ["temperatureInUnits": [["unit": "F", "currentTemperature": 75, "targetTemperature": 72]]])
        let result = applyTwentyTwo(to: state, caps: caps)

        #expect(result.before.currentTemperature == Measurement(value: 75, unit: .fahrenheit))
        #expect(result.after.currentTemperature == result.before.currentTemperature)
        #expect(result.state.values["temperatureInUnits"]?.arrayValue?.count == 1, "no C entry is appended")
        // The command is in the capability's unit (°C), so the F entry gets the converted value.
        let target = try #require(result.after.targetTemperature)
        #expect(target.unit == .fahrenheit)
        #expect(abs(target.converted(to: .celsius).value - 22) < 1e-9)
        #expect(abs(target.value - 71.6) < 1e-9)
    }

    @Test func fahrenheitOnlyCapsApplyInFahrenheit() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileFahrenheitOnly())
        var state = DeviceState(values: ["temperatureInUnits": [["unit": "F", "currentTemperature": 77, "targetTemperature": 72]]])
        ACCommand.targetTemperature(70).apply(to: &state, caps: caps)

        let snapshot = AirConditionerSnapshot(state: state, capabilities: caps)
        #expect(snapshot.currentTemperature == Measurement(value: 77, unit: .fahrenheit))
        #expect(snapshot.targetTemperature == Measurement(value: 70, unit: .fahrenheit))
    }

    @Test func heatModeApplyWritesTheHeatSetpoint() throws {
        var caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let range = PropertySpec.NumericRange(min: 16, max: 30, step: 1)
        caps.temperature.writableTargets = ["coolTargetTemperature": range, "heatTargetTemperature": range]
        var state = DeviceState(values: [
            "airConJobMode": ["currentJobMode": "HEAT"],
            "temperature": ["currentTemperature": 19, "heatTargetTemperature": 20, "unit": "C"],
        ])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).targetTemperature == Measurement(value: 20, unit: .celsius))

        ACCommand.targetTemperature(23).apply(to: &state, caps: caps)
        #expect(state["temperature", "heatTargetTemperature"] == 23)
        #expect(state["temperature", "coolTargetTemperature"] == nil)
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).targetTemperature == Measurement(value: 23, unit: .celsius))
    }
}
