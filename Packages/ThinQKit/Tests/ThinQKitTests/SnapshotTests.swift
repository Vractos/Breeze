import Foundation
import Testing
@testable import ThinQKit

@Suite("Snapshot derivation")
struct SnapshotTests {
    @Test func fromOfficialObjectExample() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let snapshot = AirConditionerSnapshot(state: try Fixture.stateShapeA(), capabilities: caps)

        #expect(snapshot == AirConditionerSnapshot(
            power: .off,
            mode: .fan,
            fan: .level(3),
            currentTemperature: Measurement(value: 27, unit: .celsius),
            targetTemperature: Measurement(value: 24.5, unit: .celsius),
            powerSave: false,
            sleepTimer: .off
        ))
    }

    @Test func fromShapeBStateUsesCelsiusEntryAndDetailedFan() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        let snapshot = AirConditionerSnapshot(state: try Fixture.stateShapeB(), capabilities: caps)

        #expect(snapshot.power == .on)
        #expect(snapshot.mode == .cool)
        #expect(snapshot.fan == .auto, "NATURE reads as Auto")
        #expect(snapshot.verticalSwing == true)
        #expect(snapshot.horizontalSwing == false)
        #expect(snapshot.sleepTimer == nil)
        #expect(snapshot.currentTemperature == Measurement(value: 24, unit: .celsius))
        #expect(snapshot.targetTemperature == Measurement(value: 22.5, unit: .celsius))
        #expect(snapshot.powerSave == nil)
    }

    @Test func emptyStateIsOffWithNothingElse() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let snapshot = AirConditionerSnapshot(state: DeviceState(), capabilities: caps)
        #expect(snapshot == AirConditionerSnapshot(power: .off))
    }

    @Test func fallsBackToTheOtherShape() throws {
        // Profile says flat, state reports the list: still readable.
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let state = DeviceState(values: ["temperatureInUnits": [["unit": "C", "currentTemperature": 21, "targetTemperature": 23]]])
        let snapshot = AirConditionerSnapshot(state: state, capabilities: caps)
        #expect(snapshot.targetTemperature == Measurement(value: 23, unit: .celsius))
        #expect(snapshot.currentTemperature == Measurement(value: 21, unit: .celsius))
    }

    @Test func fahrenheitOnlyStateReadsInFahrenheit() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileFahrenheitOnly())
        let state = DeviceState(values: ["temperatureInUnits": [["unit": "F", "targetTemperature": 72]]])
        let snapshot = AirConditionerSnapshot(state: state, capabilities: caps)
        #expect(snapshot.targetTemperature == Measurement(value: 72, unit: .fahrenheit))
        #expect(snapshot.currentTemperature == nil)
    }

    @Test func readableButNotWritableModeIsStillReported() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        var state = try Fixture.stateShapeB()
        state.merge(delta: ["airConJobMode": ["currentJobMode": "ENERGY_SAVING"]])
        let snapshot = AirConditionerSnapshot(state: state, capabilities: caps)
        // The app's mode picker must cope with a current mode it cannot offer.
        #expect(snapshot.mode == .energySaving)
        #expect(!caps.modes.contains(.energySaving))
    }

    @Test(arguments: [nil, "STANDBY"] as [JSONValue?])
    func missingOrUnknownPowerReadsAsOffButKeepsTheRest(operation: JSONValue?) throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        var values = try Fixture.stateShapeA().values
        values["operation"] = operation.map { ["airConOperationMode": $0] }
        let snapshot = AirConditionerSnapshot(state: DeviceState(values: values), capabilities: caps)
        #expect(snapshot == AirConditionerSnapshot(
            power: .off,
            mode: .fan,
            fan: .level(3),
            currentTemperature: Measurement(value: 27, unit: .celsius),
            targetTemperature: Measurement(value: 24.5, unit: .celsius),
            powerSave: false,
            sleepTimer: .off
        ))
    }

    @Test func modeSpecificSetpointIsReadForTheCurrentMode() throws {
        var caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        caps.temperature.writableTargets = [:]
        let heating = DeviceState(values: [
            "airConJobMode": ["currentJobMode": "HEAT"],
            "temperature": ["coolTargetTemperature": 18, "heatTargetTemperature": 26, "unit": "C"],
        ])
        #expect(AirConditionerSnapshot(state: heating, capabilities: caps).targetTemperature == Measurement(value: 26, unit: .celsius))
        var cooling = heating
        cooling.merge(delta: ["airConJobMode": ["currentJobMode": "COOL"]])
        #expect(AirConditionerSnapshot(state: cooling, capabilities: caps).targetTemperature == Measurement(value: 18, unit: .celsius))
    }
}
