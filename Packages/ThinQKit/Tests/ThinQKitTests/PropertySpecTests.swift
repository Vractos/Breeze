import Foundation
import Testing
@testable import ThinQKit

@Suite("PropertySpec validation")
struct PropertySpecTests {
    @Test func enumMembershipUsesWritableSet() {
        let spec = PropertySpec(json: ["type": "enum", "mode": ["r", "w"], "value": ["r": ["SET", "UNSET"], "w": ["UNSET"]]])
        #expect(spec.validate("UNSET"))
        #expect(!spec.validate("SET"))
        #expect(!spec.validate(1))
    }

    @Test func rangeChecksBoundsStepAndExcept() {
        let range = PropertySpec.NumericRange(min: 16, max: 30, step: 0.5, except: [29.5])
        #expect(range.contains(16))
        #expect(range.contains(22.5))
        #expect(range.contains(30))
        #expect(!range.contains(15.5))
        #expect(!range.contains(30.5))
        #expect(!range.contains(22.25))
        #expect(!range.contains(29.5))
        #expect(!range.contains(.nan))
    }

    @Test func rangeWithoutStepAcceptsAnyValueInBounds() {
        let range = PropertySpec.NumericRange(min: 0, max: 10)
        #expect(range.contains(3.14159))
        #expect(!range.contains(10.01))
    }

    @Test func snappedMovesOntoTheStepAndRoundsIntegralSteps() {
        let whole = PropertySpec.NumericRange(min: 18, max: 30, step: 1)
        #expect(whole.hasIntegralStep)
        #expect(whole.snapped(23.9999999) == 24)
        #expect(whole.snapped(24.000000000000004) == 24)
        #expect(whole.snapped(30.0000005) == 30)
        #expect(whole.snapped(17.9999999) == 18)

        let half = PropertySpec.NumericRange(min: 16, max: 30, step: 0.5)
        #expect(!half.hasIntegralStep)
        #expect(half.snapped(22.4999999) == 22.5)

        let tenth = PropertySpec.NumericRange(min: 16, max: 30, step: 0.1)
        #expect(tenth.snapped(22.3000000001) == 22.3, "no 22.299999999999997 from step arithmetic")

        let offset = PropertySpec.NumericRange(min: 16.5, max: 30.5, step: 1)
        #expect(!offset.hasIntegralStep, "16.5, 17.5, … are not whole numbers")
        #expect(offset.snapped(22.5000001) == 22.5)
    }

    @Test func snappedWithoutStepOnlyClamps() {
        let range = PropertySpec.NumericRange(min: 0, max: 10)
        #expect(!range.hasIntegralStep)
        #expect(range.snapped(3.14159) == 3.14159)
        #expect(range.snapped(10.0000001) == 10)
        #expect(range.snapped(-0.0000001) == 0)
    }

    @Test func readOnlyNeverValidates() {
        let spec = PropertySpec(json: ["type": "number", "mode": ["r"]])
        #expect(!spec.validate(5))
    }

    @Test func rangeParsesFlatValueForm() {
        let spec = PropertySpec(json: ["type": "range", "mode": ["r", "w"], "value": ["min": 1, "max": 5, "step": 1]])
        #expect(spec.writableRange == PropertySpec.NumericRange(min: 1, max: 5, step: 1))
        #expect(spec.validate(3))
        #expect(!spec.validate(6))
    }

    @Test func booleanAndPrimitiveTypes() {
        let boolean = PropertySpec(json: ["type": "boolean", "mode": ["r", "w"]])
        #expect(boolean.validate(true))
        #expect(!boolean.validate("true"))
        let number = PropertySpec(json: ["type": "number", "mode": ["w"]])
        #expect(number.validate(42))
        #expect(!number.validate("42"))
    }
}
