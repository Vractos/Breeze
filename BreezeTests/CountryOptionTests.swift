import Foundation
import Testing
@testable import Breeze

@Suite("CountryOption")
struct CountryOptionTests {
    private let english = Locale(identifier: "en_US")

    @Test func listsLGCountriesSortedByName() {
        let countries = CountryOption.all(including: "BR", locale: english)
        let codes = Set(countries.map(\.code))
        #expect(codes.isSuperset(of: ["BR", "US", "GB", "DE", "KR"]))
        #expect(countries.first { $0.code == "BR" }?.name == "Brazil")
        let names = countries.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func keepsTheSavedCodeEvenIfLGDoesNotListIt() {
        // Antarctica is not in LG's table; the saved value must still be selectable.
        let countries = CountryOption.all(including: "aq", locale: english)
        #expect(countries.contains { $0.code == "AQ" })
    }
}
