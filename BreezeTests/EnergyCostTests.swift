import Foundation
import Testing
@testable import Breeze

/// Settings › Energy's estimated cost, kWh × price per kWh.
@Suite("Energy cost")
struct EnergyCostTests {
    private static func price(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test func multipliesKilowattHoursByThePrice() throws {
        // October on a real unit: 13 831 Wh at R$ 0,85/kWh.
        let cost = EnergyCost.estimate(for: Measurement(value: 13.831, unit: .kilowattHours), pricePerKWh: try Self.price("0.85"))
        #expect(cost == (try Self.price("11.75635")))
    }

    @Test func convertsToKilowattHoursFirst() throws {
        // 4 338 kJ = 1.205 kWh.
        let cost = EnergyCost.estimate(for: Measurement(value: 4_338, unit: .kilojoules), pricePerKWh: 2)
        #expect(cost == (try Self.price("2.41")))
    }

    @Test func dropsBinaryNoiseBelowAWattHour() throws {
        // 0.1 + 0.2 kWh is 0.30000000000000004 as a Double.
        let cost = EnergyCost.estimate(for: Measurement(value: 0.1 + 0.2, unit: .kilowattHours), pricePerKWh: 1)
        #expect(cost == (try Self.price("0.3")))
    }

    @Test func zeroEnergyOrPriceCostsNothing() {
        #expect(EnergyCost.estimate(for: Measurement(value: 0, unit: .kilowattHours), pricePerKWh: 5) == 0)
        #expect(EnergyCost.estimate(for: Measurement(value: 42.3, unit: .kilowattHours), pricePerKWh: 0) == 0)
    }
}
