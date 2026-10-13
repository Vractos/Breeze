import Foundation
import Testing
@testable import Breeze
import ThinQKit

@Suite("TemperatureSetpoint")
struct TemperatureSetpointTests {
    private static func capabilities(
        unit: UnitTemperature = .celsius,
        targets: [String: PropertySpec.NumericRange] = ["targetTemperature": .init(min: 18, max: 30, step: 1)]
    ) -> AirConditionerCapabilities {
        AirConditionerCapabilities(
            powerOptions: [.on, .off],
            modes: [.cool, .heat, .fan],
            fanSpeeds: [.low, .high],
            fanSpeedKey: "windStrength",
            temperature: TemperatureCapability(unit: unit, currentReadable: true, shape: .flat, writableTargets: targets),
            hasPowerSave: false,
            hasVerticalSwing: false,
            hasHorizontalSwing: false
        )
    }

    @Test func usesTheSnapshotTargetWithoutADraft() throws {
        let snapshot = AirConditionerSnapshot(power: .on, mode: .cool, targetTemperature: .init(value: 24, unit: .celsius))
        let setpoint = try #require(TemperatureSetpoint(snapshot: snapshot, capabilities: Self.capabilities(), draft: nil))
        #expect(setpoint.value == 24)
        #expect(setpoint.range == PropertySpec.NumericRange(min: 18, max: 30, step: 1))
    }

    @Test func theDraftWins() throws {
        let snapshot = AirConditionerSnapshot(power: .on, mode: .cool, targetTemperature: .init(value: 24, unit: .celsius))
        let setpoint = try #require(TemperatureSetpoint(snapshot: snapshot, capabilities: Self.capabilities(), draft: 27))
        #expect(setpoint.value == 27)
    }

    @Test func convertsTheStateUnitToTheCapabilityUnitAndClamps() throws {
        // 86 °F = 30 °C; the capability is in Celsius.
        let snapshot = AirConditionerSnapshot(power: .on, mode: .cool, targetTemperature: .init(value: 86, unit: .fahrenheit))
        let setpoint = try #require(TemperatureSetpoint(snapshot: snapshot, capabilities: Self.capabilities(), draft: nil))
        #expect(abs(setpoint.value - 30) < 0.001)

        let tooHot = AirConditionerSnapshot(power: .on, mode: .cool, targetTemperature: .init(value: 35, unit: .celsius))
        #expect(TemperatureSetpoint(snapshot: tooHot, capabilities: Self.capabilities(), draft: nil)?.value == 30)
    }

    @Test func missingTargetStartsAtTheMinimum() throws {
        let snapshot = AirConditionerSnapshot(power: .on, mode: .cool)
        #expect(TemperatureSetpoint(snapshot: snapshot, capabilities: Self.capabilities(), draft: nil)?.value == 18)
    }

    @Test func nilWhenTheModeHasNoWritableSetpoint() {
        // Only a cool setpoint: HEAT never falls back to it (ThinQKit rule).
        let caps = Self.capabilities(targets: ["coolTargetTemperature": .init(min: 18, max: 30, step: 1)])
        let snapshot = AirConditionerSnapshot(power: .on, mode: .heat, targetTemperature: .init(value: 22, unit: .celsius))
        #expect(TemperatureSetpoint(snapshot: snapshot, capabilities: caps, draft: nil) == nil)
    }
}
