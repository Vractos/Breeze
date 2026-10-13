import Foundation
import Testing
@testable import ThinQKit

@Suite("Energy API requests")
struct EnergyRequestTests {
    private static let usageOK = FakeTransport.Canned.json(
        #"{"messageId":"m","timestamp":"t","response":{"resultCode":"0000","result":{"dataList":[]}}}"#
    )

    private func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    @Test func profileIsAPlainGet() async throws {
        let transport = FakeTransport(.json(
            #"{"messageId":"m","timestamp":"t","response":{"resultCode":"0000","result":{"property":["energyUsage"]}}}"#
        ))
        let client = ThinQClient(configuration: .test, transport: transport)
        #expect(try await client.energyProperties(deviceID: "dev") == ["energyUsage"])

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString == "https://api-aic.lgthinq.com/devices/energy/dev/profile")
        #expect(request?.value(forHTTPHeaderField: "x-conditional-control") == nil)
        #expect(request?.httpBody == nil)
    }

    @Test func dailyUsageQuery() async throws {
        let transport = FakeTransport(Self.usageOK)
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.energyUsage(
            deviceID: "dev", property: "energyUsage", period: .daily, from: day(2026, 10, 6), to: day(2026, 10, 12)
        )

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString
            == "https://api-aic.lgthinq.com/devices/energy/dev/usage?property=energyUsage&period=DAILY&startDate=20261006&endDate=20261012")
        #expect(request?.value(forHTTPHeaderField: "x-conditional-control") == nil)
        #expect(request?.httpBody == nil)
    }

    @Test func monthlyUsageQueryDropsTheDay() async throws {
        let transport = FakeTransport(Self.usageOK)
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.energyUsage(
            deviceID: "dev", property: "energyUsage", period: .monthly, from: day(2025, 11, 30), to: day(2026, 2, 3)
        )

        #expect(await transport.lastRequest?.url?.absoluteString
            == "https://api-aic.lgthinq.com/devices/energy/dev/usage?property=energyUsage&period=MONTHLY&startDate=202511&endDate=202602")
    }

    @Test func resultCodeBecomesAnAPIError() async throws {
        let transport = FakeTransport(
            .json(#"{"messageId":"m","timestamp":"t","response":{"resultCode":"1221"}}"#),
            .json(#"{"messageId":"m","timestamp":"t","response":{"resultCode":"1220","result":{}}}"#)
        )
        let client = ThinQClient(configuration: .test, transport: transport)

        let profileError = try await #require(throws: ThinQError.self) {
            try await client.energyProperties(deviceID: "dev")
        }
        #expect(profileError.apiCode == .notSupportedProduct)

        let usageError = try await #require(throws: ThinQError.self) {
            try await client.energyUsage(
                deviceID: "dev", property: "energyUsage", period: .daily, from: day(2026, 10, 1), to: day(2026, 10, 1)
            )
        }
        #expect(usageError.apiCode == .notSupportedFeature)
    }

    // MARK: Range validation

    @Test(arguments: [
        // 31 days, across a month boundary.
        (DateComponents(year: 2026, month: 1, day: 25), DateComponents(year: 2026, month: 2, day: 24), "20260125", "20260224"),
        // 31 days, across a year boundary.
        (DateComponents(year: 2025, month: 12, day: 15), DateComponents(year: 2026, month: 1, day: 14), "20251215", "20260114"),
        // A single day, and a leap day.
        (DateComponents(year: 2024, month: 2, day: 29), DateComponents(year: 2024, month: 2, day: 29), "20240229", "20240229"),
    ])
    func acceptedDailyRanges(from: DateComponents, to: DateComponents, start: String, end: String) async throws {
        let transport = FakeTransport(Self.usageOK)
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.energyUsage(deviceID: "dev", property: "energyUsage", period: .daily, from: from, to: to)
        let query = await transport.lastRequest?.url?.query()
        #expect(query == "property=energyUsage&period=DAILY&startDate=\(start)&endDate=\(end)")
    }

    @Test(arguments: [
        // 12 months, across a year boundary.
        (DateComponents(year: 2025, month: 11), DateComponents(year: 2026, month: 10), "202511", "202610"),
        (DateComponents(year: 2026, month: 10), DateComponents(year: 2026, month: 10), "202610", "202610"),
    ])
    func acceptedMonthlyRanges(from: DateComponents, to: DateComponents, start: String, end: String) async throws {
        let transport = FakeTransport(Self.usageOK)
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.energyUsage(deviceID: "dev", property: "energyUsage", period: .monthly, from: from, to: to)
        let query = await transport.lastRequest?.url?.query()
        #expect(query == "property=energyUsage&period=MONTHLY&startDate=\(start)&endDate=\(end)")
    }

    @Test(arguments: [
        // 32 days.
        (EnergyPeriod.daily, DateComponents(year: 2026, month: 1, day: 1), DateComponents(year: 2026, month: 2, day: 1)),
        // End before start.
        (.daily, DateComponents(year: 2026, month: 10, day: 12), DateComponents(year: 2026, month: 10, day: 11)),
        // Daily without a day.
        (.daily, DateComponents(year: 2026, month: 10), DateComponents(year: 2026, month: 10, day: 12)),
        // Not a real date.
        (.daily, DateComponents(year: 2026, month: 2, day: 30), DateComponents(year: 2026, month: 3, day: 1)),
        (.daily, DateComponents(year: 2025, month: 2, day: 29), DateComponents(year: 2025, month: 3, day: 1)),
        // No year.
        (.daily, DateComponents(month: 10, day: 1), DateComponents(year: 2026, month: 10, day: 2)),
        // 13 months.
        (.monthly, DateComponents(year: 2025, month: 1), DateComponents(year: 2026, month: 1)),
        // End before start.
        (.monthly, DateComponents(year: 2026, month: 10), DateComponents(year: 2026, month: 9)),
        // Month 13.
        (.monthly, DateComponents(year: 2026, month: 13), DateComponents(year: 2026, month: 13)),
    ])
    func rejectedRangesNeverReachTheTransport(period: EnergyPeriod, from: DateComponents, to: DateComponents) async throws {
        let transport = FakeTransport(Self.usageOK)
        let client = ThinQClient(configuration: .test, transport: transport)
        let error = try await #require(throws: ThinQError.self) {
            try await client.energyUsage(deviceID: "dev", property: "energyUsage", period: period, from: from, to: to)
        }
        guard case .invalidArgument = error else {
            Issue.record("expected .invalidArgument, got \(error)")
            return
        }
        #expect(await transport.requests.isEmpty)
    }
}

@Suite("Energy API responses")
struct EnergyResponseTests {
    private func entries(_ dataList: JSONValue, property: String = "energyUsage") throws(ThinQError) -> [EnergyUsageEntry] {
        try EnergyResponse.entries(json: ["resultCode": "0000", "result": ["dataList": dataList]], property: property)
    }

    private func kWh(_ value: Double) -> Measurement<UnitEnergy> {
        Measurement(value: value, unit: .kilowattHours)
    }

    private func expectDecodingError(_ dataList: JSONValue, property: String = "energyUsage") {
        do {
            let parsed = try entries(dataList, property: property)
            Issue.record("expected .decoding, parsed \(parsed)")
        } catch {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test func absentPropertiesAreEmpty() throws {
        #expect(try EnergyResponse.properties(json: ["resultCode": "0000", "result": [:]]) == [])
        #expect(try EnergyResponse.properties(json: ["resultCode": "0000"]) == [])
        #expect(try EnergyResponse.properties(json: nil) == [])
        #expect(try EnergyResponse.properties(json: ["result": ["property": ["energyUsage", "energyUsage_washer"]]])
            == ["energyUsage", "energyUsage_washer"])
    }

    @Test func nonArrayPropertiesAreADecodingError() throws {
        let error = try #require(throws: ThinQError.self) {
            try EnergyResponse.properties(json: ["resultCode": "0000", "result": ["property": "energyUsage"]])
        }
        guard case .decoding = error else {
            Issue.record("expected .decoding, got \(error)")
            return
        }
    }

    @Test func nonZeroResultCodeIsAnAPIError() throws {
        let error = try #require(throws: ThinQError.self) {
            try EnergyResponse.entries(json: ["resultCode": "2214", "result": ["dataList": []]], property: "energyUsage")
        }
        #expect(error.apiCode == ThinQErrorCode(rawValue: "2214"))
    }

    @Test func absentDataListIsEmpty() throws {
        #expect(try EnergyResponse.entries(json: ["resultCode": "0000", "result": [:]], property: "energyUsage") == [])
        #expect(try EnergyResponse.entries(json: nil, property: "energyUsage") == [])
    }

    @Test func dailyAndMonthlyEntriesInKilowattHours() throws {
        let parsed = try entries([
            ["usedDate": "20261001", "energyUsage": 1500],
            ["usedDate": "202609", "energyUsage": 0.5],
        ])
        #expect(parsed == [
            EnergyUsageEntry(date: DateComponents(year: 2026, month: 10, day: 1), energy: kWh(1.5)),
            EnergyUsageEntry(date: DateComponents(year: 2026, month: 9), energy: kWh(0.0005)),
        ])
        #expect(parsed.allSatisfy { $0.energy.unit == .kilowattHours })
    }

    @Test func valueKeyIsThePropertyFallingBackToUseAmount() throws {
        #expect(try entries([["usedDate": "20261001", "useAmount": 2000]]).map(\.energy) == [kWh(2)])
        #expect(try entries([["usedDate": "20261001", "useAmount": 2000, "energyUsage": 3000]]).map(\.energy) == [kWh(3)])
        #expect(try entries([["usedDate": "20261001", "energyUsage_washer": 4000]], property: "energyUsage_washer")
            .map(\.energy) == [kWh(4)])
    }

    @Test(arguments: [
        "2026-10-01", "2026100", "20261301", "202613", "20260230", "20250229", "2026１001", "", "abcdefgh",
    ])
    func malformedUsedDateIsADecodingError(usedDate: String) {
        expectDecodingError([["usedDate": .string(usedDate), "energyUsage": 1]])
    }

    @Test func missingUsedDateOrValueIsADecodingError() {
        expectDecodingError([["energyUsage": 1]])
        expectDecodingError([["usedDate": 20261001, "energyUsage": 1]])
        expectDecodingError([["usedDate": "20261001"]])
        expectDecodingError([["usedDate": "20261001", "energyUsage": "1500"]])
        expectDecodingError([["usedDate": "20261001", "energyUsage": nil]])
        expectDecodingError([["usedDate": "20261001", "energyUsage": true]])
        expectDecodingError("not a list")
    }
}
