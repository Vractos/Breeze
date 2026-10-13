import Foundation
import Testing
@testable import ThinQKit

@Suite("Swing, display light and sleep timer")
struct SwingLightSleepTests {
    private func realCaps() throws -> AirConditionerCapabilities {
        try AirConditionerCapabilities(profile: Fixture.realProfile())
    }

    private func wireText(_ command: ACCommand, caps: AirConditionerCapabilities) throws -> String {
        String(decoding: try JSONValue.object(command.payload(for: caps, currentMode: .cool)).jsonData(), as: UTF8.self)
    }

    // MARK: - Capabilities

    @Test func realUnitCapabilities() throws {
        let caps = try realCaps()
        #expect(caps.hasVerticalSwing)
        #expect(!caps.hasHorizontalSwing)
        #expect(caps.hasDisplayLight)
        #expect(caps.hasSleepTimer)
        #expect(!caps.hasPowerSave)
    }

    @Test func displayLightNeedsBothOnAndOff() throws {
        let profile = try DeviceProfile(json: [
            "property": [
                "operation": ["airConOperationMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["POWER_ON"]]]],
                "airConJobMode": ["currentJobMode": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["COOL"]]]],
                "display": ["light": ["type": "enum", "mode": ["r", "w"], "value": ["w": ["OFF", "LEVEL_1", "LEVEL_2"]]]],
            ],
        ])
        #expect(try !AirConditionerCapabilities(profile: profile).hasDisplayLight)
    }

    // MARK: - Swing and light bodies

    @Test func realUnitSwingAndLightBodies() throws {
        let caps = try realCaps()
        #expect(try wireText(.verticalSwing(true), caps: caps) == #"{"windDirection":{"rotateUpDown":true}}"#)
        #expect(try wireText(.verticalSwing(false), caps: caps) == #"{"windDirection":{"rotateUpDown":false}}"#)
        #expect(try wireText(.displayLight(true), caps: caps) == #"{"display":{"light":"ON"}}"#)
        #expect(try wireText(.displayLight(false), caps: caps) == #"{"display":{"light":"OFF"}}"#)
    }

    @Test func horizontalSwingBodyWhereWritable() throws {
        var caps = try realCaps()
        caps.hasHorizontalSwing = true
        #expect(try wireText(.horizontalSwing(true), caps: caps) == #"{"windDirection":{"rotateLeftRight":true}}"#)
    }

    @Test func unwritableSwingAndLightAreRejected() throws {
        let real = try realCaps()
        #expect(throws: ACModelError.notWritable("windDirection.rotateLeftRight")) {
            try ACCommand.horizontalSwing(true).payload(for: real, currentMode: nil)
        }
        let shapeA = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(throws: ACModelError.notWritable("windDirection.rotateUpDown")) {
            try ACCommand.verticalSwing(true).payload(for: shapeA, currentMode: nil)
        }
        #expect(throws: ACModelError.notWritable("display.light")) {
            try ACCommand.displayLight(true).payload(for: shapeA, currentMode: nil)
        }
    }

    @Test func swingAndLightApplyAndRead() throws {
        let caps = try realCaps()
        var state = try Fixture.realState()
        ACCommand.verticalSwing(false).apply(to: &state, caps: caps)
        ACCommand.displayLight(true).apply(to: &state, caps: caps)
        let snapshot = AirConditionerSnapshot(state: state, capabilities: caps)
        #expect(snapshot.verticalSwing == false)
        #expect(snapshot.displayLight == true)
    }

    @Test(arguments: [("ON", true), ("OFF", false), ("LEVEL_1", nil)] as [(JSONValue, Bool?)])
    func displayLightReads(value: JSONValue, expected: Bool?) throws {
        let state = DeviceState(values: ["display": ["light": value]])
        #expect(try AirConditionerSnapshot(state: state, capabilities: realCaps()).displayLight == expected)
    }

    // MARK: - Sleep timer bodies

    @Test func thirtyMinutesSendsHourZeroAndMinutes() throws {
        #expect(try wireText(.sleepTimer(minutes: 30), caps: realCaps())
            == #"{"sleepTimer":{"relativeHourToStop":0,"relativeMinuteToStop":30}}"#)
    }

    @Test(arguments: [1, 2, 3, 4, 6, 8, 10, 12])
    func wholeHoursSendTheHourAlone(hours: Int) throws {
        #expect(try wireText(.sleepTimer(minutes: hours * 60), caps: realCaps())
            == #"{"sleepTimer":{"relativeHourToStop":\#(hours)}}"#)
    }

    @Test func cancelSendsUnset() throws {
        #expect(try wireText(.sleepTimer(minutes: nil), caps: realCaps()) == #"{"sleepTimer":{"relativeStopTimer":"UNSET"}}"#)
    }

    @Test(arguments: [0, 15, 29, 45, 59, 90, 150, 780, 1440, -60])
    func sleepValuesLGRejectsAreInvalid(minutes: Int) throws {
        #expect(throws: ACModelError.invalidSleepTimer(minutes: minutes)) {
            try ACCommand.sleepTimer(minutes: minutes).payload(for: realCaps(), currentMode: nil)
        }
    }

    @Test func sleepTimerNotWritable() throws {
        var caps = try realCaps()
        caps.hasSleepTimer = false
        for minutes in [60, nil] as [Int?] {
            #expect(throws: ACModelError.notWritable("sleepTimer.relativeHourToStop")) {
                try ACCommand.sleepTimer(minutes: minutes).payload(for: caps, currentMode: nil)
            }
        }
    }

    // MARK: - Sleep timer state

    @Test func setDeltaRecordsTheFullDuration() throws {
        let caps = try realCaps()
        var state = try Fixture.realState()

        ACCommand.sleepTimer(minutes: 30).apply(to: &state, caps: caps)
        #expect(state.values["sleepTimer"] == ["relativeStopTimer": "SET", "relativeHourToStop": 0, "relativeMinuteToStop": 30])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).sleepTimer == .set(remaining: .seconds(30 * 60)))

        ACCommand.sleepTimer(minutes: 120).apply(to: &state, caps: caps)
        #expect(state.values["sleepTimer"] == ["relativeStopTimer": "SET", "relativeHourToStop": 2, "relativeMinuteToStop": 0])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).sleepTimer == .set(remaining: .seconds(2 * 3600)))
    }

    @Test func cancelDeltaReadsOffDespiteLeftoverNumbers() throws {
        let caps = try realCaps()
        var state = try Fixture.realState()
        ACCommand.sleepTimer(minutes: 60).apply(to: &state, caps: caps)
        ACCommand.sleepTimer(minutes: nil).apply(to: &state, caps: caps)
        #expect(state.values["sleepTimer"] == ["relativeStopTimer": "UNSET", "relativeHourToStop": 1, "relativeMinuteToStop": 0])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).sleepTimer == .off)
    }

    @Test(arguments: [
        (["relativeStopTimer": "SET", "relativeHourToStop": 0, "relativeMinuteToStop": 56], .set(remaining: .seconds(56 * 60))),
        (["relativeStopTimer": "SET", "relativeHourToStop": 11], .set(remaining: .seconds(11 * 3600))),
        (["relativeStopTimer": "SET"], .set(remaining: nil)),
        (["relativeStopTimer": "SET", "relativeHourToStop": -1], .set(remaining: nil)),
        (["relativeStopTimer": "SET", "relativeHourToStop": 1e300], .set(remaining: nil)),
        (["relativeStopTimer": "UNSET"], .off),
        (["relativeStopTimer": "UNSET", "relativeHourToStop": 3, "relativeMinuteToStop": 10], .off),
        (["relativeHourToStop": 3], .off),
    ] as [(JSONValue, SleepTimerState?)])
    func sleepTimerReads(sleepTimer: JSONValue, expected: SleepTimerState?) throws {
        let state = DeviceState(values: ["sleepTimer": sleepTimer])
        #expect(try AirConditionerSnapshot(state: state, capabilities: realCaps()).sleepTimer == expected)
    }

    @Test func noSleepTimerResourceReadsNil() throws {
        #expect(try AirConditionerSnapshot(state: DeviceState(), capabilities: realCaps()).sleepTimer == nil)
    }

    // MARK: - The real fixture

    @Test func realFixtureSnapshot() throws {
        let snapshot = AirConditionerSnapshot(state: try Fixture.realState(), capabilities: try realCaps())
        #expect(snapshot == AirConditionerSnapshot(
            power: .on,
            mode: .cool,
            fan: .level(1),
            currentTemperature: Measurement(value: 24, unit: .celsius),
            targetTemperature: Measurement(value: 21, unit: .celsius),
            verticalSwing: true,
            displayLight: false,
            sleepTimer: .off
        ))
    }

    @Test(arguments: [
        ACCommand.verticalSwing(true), .displayLight(false), .sleepTimer(minutes: 60), .fan(.level(2)),
    ])
    func newCommandsAreNeverRedundant(command: ACCommand) {
        #expect(!command.isRedundant(.api(code: .commandNotSupportedInPowerOff, message: "")))
    }
}
