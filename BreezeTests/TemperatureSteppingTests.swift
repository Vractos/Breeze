import Testing
@testable import Breeze
import ThinQKit

@Suite("NumericRange stepping")
struct TemperatureSteppingTests {
    private let wholeDegrees = PropertySpec.NumericRange(min: 18, max: 30, step: 1)

    @Test func movesOneStepAndClampsAtTheEnds() {
        #expect(wholeDegrees.value(steppingFrom: 22, up: true) == 23)
        #expect(wholeDegrees.value(steppingFrom: 22, up: false) == 21)
        #expect(wholeDegrees.value(steppingFrom: 30, up: true) == 30)
        #expect(wholeDegrees.value(steppingFrom: 18, up: false) == 18)
    }

    @Test func offGridValuesMoveToTheAdjacentGridPoint() {
        // The official fixture reports 24.5 on a whole-degree model.
        #expect(wholeDegrees.value(steppingFrom: 24.5, up: true) == 25)
        #expect(wholeDegrees.value(steppingFrom: 24.5, up: false) == 24)
    }

    @Test func halfDegreeSteps() {
        let range = PropertySpec.NumericRange(min: 16, max: 30, step: 0.5)
        #expect(range.value(steppingFrom: 22, up: true) == 22.5)
        #expect(range.value(steppingFrom: 22.5, up: false) == 22)
    }

    @Test func skipsExcludedValues() {
        let range = PropertySpec.NumericRange(min: 18, max: 30, step: 1, except: [23, 24])
        #expect(range.value(steppingFrom: 22, up: true) == 25)
        #expect(range.value(steppingFrom: 25, up: false) == 22)
    }

    @Test func excludedEndpointLeavesTheValueAlone() {
        let range = PropertySpec.NumericRange(min: 18, max: 30, step: 1, except: [30])
        #expect(range.value(steppingFrom: 29, up: true) == 29)
    }

    @Test func noStepFallsBackToHalfDegrees() {
        let range = PropertySpec.NumericRange(min: 18, max: 30)
        #expect(range.effectiveStep == 0.5)
        #expect(range.value(steppingFrom: 20, up: true) == 20.5)
    }

    @Test func outOfRangeStartIsClampedFirst() {
        #expect(wholeDegrees.value(steppingFrom: 40, up: false) == 29)
        #expect(wholeDegrees.value(steppingFrom: 10, up: true) == 19)
    }

    @Test func singleValueRangeIsNotAdjustable() {
        #expect(!PropertySpec.NumericRange(min: 20, max: 20).isAdjustable)
        #expect(wholeDegrees.isAdjustable)
    }
}
