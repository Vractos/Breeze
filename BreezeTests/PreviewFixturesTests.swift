import Foundation
import Testing
@testable import Breeze
import ThinQKit

/// The previews must show what the real unit shows: Auto plus fan levels 1–5.
@Suite("Preview fixtures")
struct PreviewFixturesTests {
    @Test func theFanOffersAutoAndFiveLevelsLikeTheRealUnit() throws {
        let caps = try AirConditionerCapabilities(profile: PreviewFixtures.profile)
        let real = try AirConditionerCapabilities(profile: Fixtures.realProfile())

        #expect(caps.fan.options == [.auto, .level(1), .level(2), .level(3), .level(4), .level(5)])
        #expect(caps.fan == real.fan)
    }

    @Test(arguments: [ACFanSetting.auto, .level(1), .level(2), .level(3), .level(4), .level(5)])
    func previewStatesReadBackTheirFanSetting(fan: ACFanSetting) throws {
        let caps = try AirConditionerCapabilities(profile: PreviewFixtures.profile)
        let snapshot = AirConditionerSnapshot(state: PreviewFixtures.state(power: .on, fan: fan), capabilities: caps)
        #expect(snapshot.fan == fan)
    }

    @Test func level3UsesTheRealUnitsCombination() {
        let state = PreviewFixtures.state(power: .on, fan: .level(3))
        #expect(state["airFlow", "windStep"] == .number(3))
        #expect(state["airFlow", "windStrength"] == "MID")
        #expect(state["airFlow", "windStrengthDetail"] == "MID")
    }

    @Test func autoUsesTheRealUnitsCombination() {
        let state = PreviewFixtures.state(power: .on, fan: .auto)
        #expect(state["airFlow", "windStrength"] == "AUTO")
        #expect(state["airFlow", "windStrengthDetail"] == "NATURE")
        #expect(state["airFlow", "windStep"] == nil)
    }
}
