import Foundation
import Testing
@testable import ThinQKit

@Suite("Profile parsing")
struct ProfileParsingTests {
    @Test func shapeAOfficialExample() throws {
        let profile = try Fixture.profileShapeA()

        #expect(Set(profile.resources.keys) == [
            "airConJobMode", "airFlow", "filterInfo", "airQualitySensor", "operation", "powerSave",
            "sleepTimer", "temperature", "timer",
        ])
        #expect(profile.temperatureInUnits == nil)

        let mode = try #require(profile["airConJobMode", "currentJobMode"])
        #expect(mode.kind == .enum(readable: ["AIR_DRY", "COOL", "AIR_CLEAN"], writable: ["AIR_DRY", "COOL", "AIR_CLEAN"]))
        #expect(mode.isReadable && mode.isWritable)

        let target = try #require(profile["temperature", "targetTemperature"])
        #expect(target.writableRange == PropertySpec.NumericRange(min: 18, max: 30, step: 1))
        #expect(target.readableRange == PropertySpec.NumericRange(min: 18, max: 30, step: 1))

        let cool = try #require(profile["temperature", "coolTargetTemperature"])
        #expect(!cool.isReadable && cool.isWritable)
        #expect(cool.readableRange == nil)

        let current = try #require(profile["temperature", "currentTemperature"])
        #expect(current.kind == .number)
        #expect(current.isReadable && !current.isWritable)

        #expect(profile["powerSave", "powerSaveEnabled"]?.kind == .boolean(writable: true))
        #expect(profile["temperature", "unit"]?.readableValues == ["C"])
        #expect(profile["sleepTimer", "relativeStopTimer"]?.writableValues == ["UNSET"])
        #expect(profile["operation", "airCleanOperationMode"]?.isReadable == false)
        #expect(profile.raw["notification"]?["push"] == ["WATER_IS_FULL"])
    }

    @Test func shapeBTemperatureInUnits() throws {
        let profile = try Fixture.profileShapeB()
        let entries = try #require(profile.temperatureInUnits)

        #expect(entries.map(\.unit) == ["F", "C"])
        #expect(profile.resources["temperatureInUnits"] == nil)

        let celsius = try #require(entries.first { $0.unit == "C" })
        #expect(celsius["targetTemperature"]?.writableRange == PropertySpec.NumericRange(min: 16, max: 30, step: 0.5, except: [29.5]))
        #expect(celsius["currentTemperature"]?.isReadable == true)
        #expect(celsius["coolTargetTemperature"]?.writableRange == PropertySpec.NumericRange(min: 18, max: 30, step: 1))
        #expect(entries.first { $0.unit == "F" }?["targetTemperature"]?.writableRange?.max == 86)
        #expect(profile["airFlow", "windStrengthDetail"]?.writableValues.count == 7)
    }

    @Test func missingPropertyObjectIsDecodingError() throws {
        let error = try #require(throws: ThinQError.self) { try DeviceProfile(json: ["notification": [:]]) }
        guard case .decoding(let path, _) = error else {
            Issue.record("expected .decoding, got \(error)")
            return
        }
        #expect(path == "profile.property")
    }

    @Test func unknownTypesAndExtraResourcesNeverBreakParsing() throws {
        let profile = try DeviceProfile(json: [
            "property": [
                "mystery": ["thing": ["type": "hologram", "mode": ["r"]]],
                "scalarResource": "weird",
                "listy": ["items": ["type": "list", "mode": ["r", "w"]]],
            ],
        ])
        #expect(profile["mystery", "thing"]?.kind == .unknown)
        #expect(profile["listy", "items"]?.kind == .list)
        #expect(profile.resources["scalarResource"] == nil)
    }
}
