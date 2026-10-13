import Foundation
import Testing
@testable import ThinQKit

@Suite("Event messages")
struct EventMessageTests {
    @Test func officialExampleParsesAndMerges() throws {
        let message = try ThinQEventMessage(data: Fixture.data("event_message_example"))

        #expect(message.deviceID == "HW1-69C3EDD9-1993-4442-B139-794CA5997ECA")
        #expect(message.pushType == "DEVICE_STATUS")
        #expect(message.deviceType == "DEVICE_WASHER")
        let delta = try #require(message.statusDelta)
        #expect(delta == ["operation": ["airConOperationMode": "POWER_ON"]])

        var state = try Fixture.stateShapeA()
        state.merge(delta: delta)
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        let snapshot = AirConditionerSnapshot(state: state, capabilities: caps)
        #expect(snapshot.power == .on)
        #expect(snapshot.mode == .fan)
        #expect(snapshot.targetTemperature == Measurement(value: 24.5, unit: .celsius))
    }

    @Test func flatMQTTFormParses() throws {
        let message = try ThinQEventMessage(json: [
            "deviceId": "ac1",
            "deviceType": "DEVICE_AIR_CONDITIONER",
            "pushType": "DEVICE_STATUS",
            "report": ["airFlow": ["windStrength": "HIGH"]],
        ])
        #expect(message.deviceID == "ac1")
        #expect(message.statusDelta == ["airFlow": ["windStrength": "HIGH"]])
    }

    @Test func nonStatusPushHasNoDelta() throws {
        let message = try ThinQEventMessage(json: ["deviceId": "ac1", "pushType": "DEVICE_PUSH", "pushCode": "WATER_IS_FULL"])
        #expect(message.statusDelta == nil)
    }

    @Test func missingDeviceIDThrows() {
        #expect(throws: ThinQError.self) { try ThinQEventMessage(json: ["event": ["report": [:]]]) }
    }
}
