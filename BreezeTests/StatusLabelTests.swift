import Foundation
import Testing
@testable import Breeze
import ThinQKit

@Suite("StatusLabel")
struct StatusLabelTests {
    private let target = Measurement(value: 22, unit: UnitTemperature.celsius)

    @Test func showsTheRunningModeSymbolAndTarget() {
        let snapshot = AirConditionerSnapshot(power: .on, mode: .heat, targetTemperature: target)
        #expect(StatusLabel.symbolName(for: snapshot) == "flame")
        #expect(StatusLabel.displayedTarget(for: snapshot, showsTemperature: true) == target)
    }

    @Test func offOrUnknownIsJustASnowflake() {
        let off = AirConditionerSnapshot(power: .off, mode: .heat, targetTemperature: target)
        #expect(StatusLabel.symbolName(for: off) == "snowflake")
        #expect(StatusLabel.displayedTarget(for: off, showsTemperature: true) == nil)
        #expect(StatusLabel.symbolName(for: nil) == "snowflake")
        #expect(StatusLabel.displayedTarget(for: nil, showsTemperature: true) == nil)
    }

    @Test func theSettingHidesTheTemperature() {
        let snapshot = AirConditionerSnapshot(power: .on, mode: .cool, targetTemperature: target)
        #expect(StatusLabel.displayedTarget(for: snapshot, showsTemperature: false) == nil)
    }

    /// Foundation's narrow width writes "22°C"; the menu bar wants the compact "22°".
    @Test(arguments: [
        (22.0, UnitTemperature.celsius, "pt_BR", "22°"),
        (24.5, UnitTemperature.celsius, "pt_BR", "24,5°"),
        (24.5, UnitTemperature.celsius, "en_US", "24.5°"),
        (72.0, UnitTemperature.fahrenheit, "en_US", "72°"),
    ])
    func menuBarTextIsTheNumberAndADegreeSign(value: Double, unit: UnitTemperature, locale: String, expected: String) {
        var resource = StatusLabel.menuBarText(for: Measurement(value: value, unit: unit))
        resource.locale = Locale(identifier: locale)
        #expect(String(localized: resource) == expected)
    }
}
