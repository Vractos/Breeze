import Foundation
import Testing
@testable import ThinQKit

@Suite("Fan levels")
struct FanLevelTests {
    private static let realLevels = ["LOW", "LOW_MID", "MID", "MID_HIGH", "HIGH"]

    private func realCaps() throws -> AirConditionerCapabilities {
        try AirConditionerCapabilities(profile: Fixture.realProfile())
    }

    private func snapshotFan(_ airFlow: JSONObject, caps: AirConditionerCapabilities) -> ACFanSetting? {
        AirConditionerSnapshot(state: DeviceState(values: ["airFlow": .object(airFlow)]), capabilities: caps).fan
    }

    // MARK: - Capability

    @Test func realUnitOffersAutoAndFiveLevelsViaTheDetailKey() throws {
        let fan = try realCaps().fan
        #expect(fan.options == [.auto, .level(1), .level(2), .level(3), .level(4), .level(5)])
        #expect(fan.levelValues == Self.realLevels, "NATURE is not a level")
        #expect(fan.levelKey == "windStrengthDetail")
        #expect(fan.autoKey == "windStrength")
        #expect(fan.stateKeys == ["windStrength", "windStrengthDetail", "windStep"])
        #expect(fan.detailReportsNature)
    }

    @Test func autoOnlyInTheDetailKeyIsWrittenThere() throws {
        let fan = FanCapability(airFlow: [
            "windStrengthDetail": PropertySpec(kind: .enum(readable: [], writable: ["HIGH", "AUTO", "LOW"]), isReadable: true, isWritable: true),
        ])
        #expect(fan.options == [.auto, .level(1), .level(2)])
        #expect(fan.levelValues == ["LOW", "HIGH"])
        #expect(try fan.payload(for: .auto) == ["airFlow": ["windStrengthDetail": "AUTO"]])
    }

    @Test func detailWithoutLevelsFallsBackToTheCoarseKey() throws {
        let fan = FanCapability(airFlow: [
            "windStrength": PropertySpec(kind: .enum(readable: [], writable: ["MID", "LOW"]), isReadable: true, isWritable: true),
            "windStrengthDetail": PropertySpec(kind: .enum(readable: [], writable: ["NATURE"]), isReadable: true, isWritable: true),
        ])
        #expect(fan.options == [.level(1), .level(2)])
        #expect(fan.levelKey == "windStrength")
        #expect(try fan.payload(for: .level(2)) == ["airFlow": ["windStrength": "MID"]])
    }

    @Test func unsupportedFanOffersNothing() throws {
        #expect(FanCapability.unsupported.options.isEmpty)
        #expect(throws: ACModelError.notWritable("airFlow.windStrength")) { try FanCapability.unsupported.payload(for: .auto) }
    }

    // MARK: - POST bodies (exactly one key)

    @Test func realUnitAutoBody() throws {
        #expect(try ACCommand.fan(.auto).payload(for: realCaps(), currentMode: .cool) == ["airFlow": ["windStrength": "AUTO"]])
    }

    @Test(arguments: zip(1...5, realLevels))
    func realUnitLevelBodies(level: Int, detail: String) throws {
        #expect(try ACCommand.fan(.level(level)).payload(for: realCaps(), currentMode: .cool) == [
            "airFlow": ["windStrengthDetail": .string(detail)],
        ])
    }

    @Test(arguments: [0, 6, -1])
    func realUnitRejectsLevelsOutsideOneToFive(level: Int) throws {
        #expect(throws: ACModelError.unsupportedFan(.level(level))) {
            try ACCommand.fan(.level(level)).payload(for: realCaps(), currentMode: nil)
        }
    }

    // MARK: - Reading (states observed on a real unit)

    @Test(arguments: [
        (1, "LOW", "LOW"), (2, "MID", "LOW_MID"), (3, "MID", "MID"), (4, "HIGH", "MID_HIGH"), (5, "HIGH", "HIGH"),
    ])
    func observedLevelStatesRead(step: Int, strength: String, detail: String) throws {
        let airFlow: JSONObject = ["windStep": .number(Double(step)), "windStrength": .string(strength), "windStrengthDetail": .string(detail)]
        #expect(try snapshotFan(airFlow, caps: realCaps()) == .level(step))
    }

    @Test func observedAutoStateReadsAuto() throws {
        #expect(try snapshotFan(["windStrength": "AUTO", "windStrengthDetail": "NATURE"], caps: realCaps()) == .auto)
    }

    @Test func realFixtureReadsLevelOne() throws {
        let snapshot = AirConditionerSnapshot(state: try Fixture.realState(), capabilities: try realCaps())
        #expect(snapshot.fan == .level(1))
    }

    @Test func autoWinsOverAStaleWindStep() throws {
        // `merge` can't delete keys: a windStep left over from a level must not win.
        let caps = try realCaps()
        #expect(snapshotFan(["windStep": 3, "windStrength": "AUTO", "windStrengthDetail": "NATURE"], caps: caps) == .auto)
        #expect(snapshotFan(["windStep": 3, "windStrength": "MID", "windStrengthDetail": "AUTO"], caps: caps) == .auto)
        #expect(snapshotFan(["windStep": 3, "windStrength": "MID", "windStrengthDetail": "NATURE"], caps: caps) == .auto)
    }

    @Test func windStepIsIgnored() throws {
        let caps = try realCaps()
        #expect(snapshotFan(["windStep": 5, "windStrength": "LOW", "windStrengthDetail": "LOW_MID"], caps: caps) == .level(2))
        #expect(snapshotFan(["windStep": 4], caps: caps) == nil)
    }

    @Test func coarseKeyIsTheFallbackForTheLevel() throws {
        #expect(try snapshotFan(["windStrength": "MID"], caps: realCaps()) == .level(3))
    }

    @Test func valuesOutsideTheOptionsReadAsNil() throws {
        let caps = try realCaps()
        #expect(snapshotFan(["windStrengthDetail": "POWER"], caps: caps) == nil)
        #expect(snapshotFan([:], caps: caps) == nil)
        // Shape A offers no Auto, so even an explicit AUTO is not a setting it can show.
        let shapeA = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        #expect(snapshotFan(["windStrength": "AUTO"], caps: shapeA) == nil)
    }

    // MARK: - Official fixtures

    @Test func officialObjectExampleReadsLevelThreeAndIgnoresItsWindStep() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeA())
        var state = try Fixture.stateShapeA()
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .level(3))

        ACCommand.fan(.level(1)).apply(to: &state, caps: caps)
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .level(1))
        #expect(state["airFlow", "windStep"] == 5, "the profile has no windStep, so it is left alone")
        #expect(state["airFlow", "windStrength"] == "LOW")
    }

    // MARK: - Optimistic state

    @Test(arguments: [(1, "LOW", "LOW"), (2, "MID", "LOW_MID"), (3, "MID", "MID"), (4, "HIGH", "MID_HIGH"), (5, "HIGH", "HIGH")])
    func realUnitLevelDeltaWritesEveryFanKey(level: Int, strength: String, detail: String) throws {
        #expect(try realCaps().fan.stateDelta(for: .level(level)) == [
            "airFlow": ["windStep": .number(Double(level)), "windStrength": .string(strength), "windStrengthDetail": .string(detail)],
        ])
    }

    @Test func realUnitAutoDeltaMatchesTheObservedAutoState() throws {
        #expect(try realCaps().fan.stateDelta(for: .auto) == ["airFlow": ["windStrength": "AUTO", "windStrengthDetail": "NATURE"]])
    }

    @Test func unknownLevelChangesNothing() throws {
        #expect(try realCaps().fan.stateDelta(for: .level(9)) == [:])
    }

    @Test func autoToLevelTwoToAutoRoundTrips() throws {
        let caps = try realCaps()
        var state = try Fixture.realState()

        ACCommand.fan(.auto).apply(to: &state, caps: caps)
        #expect(state.values["airFlow"] == ["windStep": 1, "windStrength": "AUTO", "windStrengthDetail": "NATURE"])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .auto)

        ACCommand.fan(.level(2)).apply(to: &state, caps: caps)
        #expect(state.values["airFlow"] == ["windStep": 2, "windStrength": "MID", "windStrengthDetail": "LOW_MID"])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .level(2))

        ACCommand.fan(.level(4)).apply(to: &state, caps: caps)
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .level(4))

        ACCommand.fan(.auto).apply(to: &state, caps: caps)
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .auto)
    }

    @Test func shapeBAutoDeltaKeepsTheDetailReadingAuto() throws {
        let caps = try AirConditionerCapabilities(profile: Fixture.profileShapeB())
        var state = try Fixture.stateShapeB()
        ACCommand.fan(.level(5)).apply(to: &state, caps: caps)
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .level(5))
        ACCommand.fan(.auto).apply(to: &state, caps: caps)
        #expect(state.values["airFlow"] == ["windStrength": "AUTO", "windStrengthDetail": "NATURE"])
        #expect(AirConditionerSnapshot(state: state, capabilities: caps).fan == .auto)
    }
}
