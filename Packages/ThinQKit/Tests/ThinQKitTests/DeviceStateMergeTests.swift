import Foundation
import Testing
@testable import ThinQKit

@Suite("DeviceState merge")
struct DeviceStateMergeTests {
    @Test func nestedMergeKeepsSiblingKeys() throws {
        var state = try Fixture.stateShapeA()
        state.merge(delta: [
            "airFlow": ["windStrength": "LOW"],
            "temperature": ["targetTemperature": 23],
            "newResource": ["flag": true],
        ])

        #expect(state["airFlow", "windStrength"] == "LOW")
        #expect(state["airFlow", "windStep"] == 5)
        #expect(state["temperature", "targetTemperature"] == 23)
        #expect(state["temperature", "currentTemperature"] == 27)
        #expect(state["temperature", "unit"] == "C")
        #expect(state["newResource", "flag"] == true)
        #expect(state["operation", "airConOperationMode"] == "POWER_OFF")
    }

    @Test func deepObjectsMergeRecursively() {
        var state = DeviceState(values: ["a": ["b": ["c": 1, "d": 2], "e": 3]])
        state.merge(delta: ["a": ["b": ["c": 10]]])
        #expect(state.values["a"] == ["b": ["c": 10, "d": 2], "e": 3])
    }

    @Test func scalarsAndTypeChangesReplace() {
        var state = DeviceState(values: ["a": ["b": ["c": 1]], "x": 1])
        state.merge(delta: ["a": ["b": "flat now"], "x": ["now": "object"]])
        #expect(state.values["a"] == ["b": "flat now"])
        #expect(state.values["x"] == ["now": "object"])
    }

    @Test func unitTaggedListsMergeByUnit() throws {
        var state = try Fixture.stateShapeB()
        state.merge(delta: ["temperatureInUnits": [["unit": "C", "currentTemperature": 25]]])
        let entries = try #require(state.values["temperatureInUnits"]?.arrayValue)
        #expect(entries == [
            ["unit": "F", "currentTemperature": 75, "targetTemperature": 72],
            ["unit": "C", "currentTemperature": 25, "targetTemperature": 22.5],
        ])
    }

    @Test func untaggedListsReplace() {
        var state = DeviceState(values: ["r": ["list": [1, 2, 3]]])
        state.merge(delta: ["r": ["list": [4]]])
        #expect(state["r", "list"] == [4])
    }

    @Test func mergingIsNonMutating() throws {
        let state = try Fixture.stateShapeA()
        let merged = state.merging(delta: ["operation": ["airConOperationMode": "POWER_ON"]])
        #expect(state["operation", "airConOperationMode"] == "POWER_OFF")
        #expect(merged["operation", "airConOperationMode"] == "POWER_ON")
    }

    @Test func nonObjectStateIsDecodingError() throws {
        let error = try #require(throws: ThinQError.self) { try DeviceState(json: [1, 2]) }
        guard case .decoding = error else {
            Issue.record("expected .decoding, got \(error)")
            return
        }
    }
}
