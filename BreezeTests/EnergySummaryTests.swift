import Foundation
import Testing
@testable import Breeze
import ThinQKit

/// The request ranges and the totals Settings › Energy derives.
@Suite("Energy summary")
struct EnergySummaryTests {
    /// São Paulo, so local dates differ from UTC ones late in the evening.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 15) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private static func month(_ year: Int, _ month: Int, wattHours: Double) -> EnergyUsageEntry {
        EnergyUsageEntry(date: DateComponents(year: year, month: month), energy: Measurement(value: wattHours / 1000, unit: .kilowattHours))
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, wattHours: Double) -> EnergyUsageEntry {
        EnergyUsageEntry(date: DateComponents(year: year, month: month, day: day), energy: Measurement(value: wattHours / 1000, unit: .kilowattHours))
    }

    @Test func rangesCoverTwelveMonthsAndThirtyDaysEndingNow() throws {
        let now = try Self.date(2026, 10, 13)

        let months = EnergySummary.monthRange(endingAt: now, calendar: Self.calendar)
        let days = EnergySummary.dayRange(endingAt: now, calendar: Self.calendar)

        #expect(months == .init(from: DateComponents(year: 2025, month: 11), to: DateComponents(year: 2026, month: 10)))
        #expect(days == .init(from: DateComponents(year: 2026, month: 9, day: 14), to: DateComponents(year: 2026, month: 10, day: 13)))
    }

    @Test func rangesUseTheLocalDateNotUTC() throws {
        // 23:30 in São Paulo on 31 Dec is already 1 Jan in UTC.
        let now = try Self.date(2026, 12, 31, hour: 23)

        let months = EnergySummary.monthRange(endingAt: now, calendar: Self.calendar)
        let days = EnergySummary.dayRange(endingAt: now, calendar: Self.calendar)

        #expect(months.to == DateComponents(year: 2026, month: 12))
        #expect(days.to == DateComponents(year: 2026, month: 12, day: 31))
    }

    @Test func rangesAreAcceptedByThinQKit() throws {
        // ThinQKit rejects spans over 12 months / 31 days; through the fake's canned data, which
        // walks the same inclusive range, count the periods.
        let now = try Self.date(2026, 3, 31)
        let months = EnergySummary.monthRange(endingAt: now, calendar: Self.calendar)
        let days = EnergySummary.dayRange(endingAt: now, calendar: Self.calendar)

        #expect(PreviewEnergy.usage(period: .monthly, from: months.from, to: months.to).count == 12)
        #expect(PreviewEnergy.usage(period: .daily, from: days.from, to: days.to).count == 30)
    }

    @Test func totalsComeFromTheMatchingEntries() throws {
        let now = try Self.date(2026, 10, 13)
        let summary = EnergySummary(
            months: [Self.month(2026, 9, wattHours: 31_640), Self.month(2026, 10, wattHours: 13_831)],
            days: [Self.day(2026, 10, 12, wattHours: 0), Self.day(2026, 10, 13, wattHours: 1_205)],
            fetchedAt: now,
            calendar: Self.calendar
        )

        #expect(summary.thisMonth == Measurement(value: 13.831, unit: .kilowattHours))
        #expect(summary.lastMonth == Measurement(value: 31.64, unit: .kilowattHours))
        #expect(summary.today == Measurement(value: 1.205, unit: .kilowattHours))
        #expect(summary.fetchedAt == now)
    }

    @Test func aJapaneseCalendarSettingStillRequestsAndMatchesGregorianDates() throws {
        // macOS set to the Japanese calendar: Calendar.current would say year 8 (Reiwa).
        let calendar = EnergySummary.calendar(
            timeZone: Self.calendar.timeZone,
            locale: Locale(identifier: "ja_JP@calendar=japanese")
        )
        let now = try Self.date(2026, 10, 13)

        let months = EnergySummary.monthRange(endingAt: now, calendar: calendar)
        let days = EnergySummary.dayRange(endingAt: now, calendar: calendar)
        let summary = EnergySummary(
            months: [Self.month(2026, 10, wattHours: 13_831)],
            days: [Self.day(2026, 10, 13, wattHours: 1_205)],
            fetchedAt: now,
            calendar: calendar
        )

        #expect(calendar.identifier == .gregorian)
        #expect(months.to == DateComponents(year: 2026, month: 10))
        #expect(days.to == DateComponents(year: 2026, month: 10, day: 13))
        #expect(summary.thisMonth == Measurement(value: 13.831, unit: .kilowattHours))
        #expect(summary.today == Measurement(value: 1.205, unit: .kilowattHours))
    }

    @Test func lastMonthOfJanuaryIsDecemberOfTheYearBefore() throws {
        let summary = EnergySummary(
            months: [Self.month(2025, 12, wattHours: 57_300), Self.month(2026, 1, wattHours: 4_000)],
            days: [],
            fetchedAt: try Self.date(2026, 1, 2),
            calendar: Self.calendar
        )

        #expect(summary.lastMonth == Measurement(value: 57.3, unit: .kilowattHours))
        #expect(summary.thisMonth == Measurement(value: 4, unit: .kilowattHours))
        #expect(summary.today == nil)
    }

    @Test func missingPeriodsReadAsNil() throws {
        let summary = EnergySummary(
            months: [Self.month(2026, 8, wattHours: 11_450)],
            days: [Self.day(2026, 10, 1, wattHours: 900)],
            fetchedAt: try Self.date(2026, 10, 13),
            calendar: Self.calendar
        )

        #expect(summary.thisMonth == nil)
        #expect(summary.lastMonth == nil)
        #expect(summary.today == nil)
        #expect(summary.months.count == 1)
        #expect(summary.days.count == 1)
    }

    @Test func entriesOutsideTheRangesAreDroppedAndTheRestSorted() throws {
        let summary = EnergySummary(
            months: [
                Self.month(2026, 10, wattHours: 13_831),
                Self.month(2025, 10, wattHours: 1),  // 13 months back
                Self.month(2025, 11, wattHours: 44_980),
                Self.month(2026, 11, wattHours: 2),  // the future
                Self.day(2026, 10, 13, wattHours: 3),  // a daily entry in the monthly list
            ],
            days: [
                Self.day(2026, 10, 13, wattHours: 1_205),
                Self.day(2026, 9, 13, wattHours: 4),  // 31 days back
                Self.day(2026, 9, 14, wattHours: 0),
            ],
            fetchedAt: try Self.date(2026, 10, 13),
            calendar: Self.calendar
        )

        #expect(summary.months.map(\.date) == [DateComponents(year: 2025, month: 11), DateComponents(year: 2026, month: 10)])
        #expect(summary.days.map(\.date) == [DateComponents(year: 2026, month: 9, day: 14), DateComponents(year: 2026, month: 10, day: 13)])
    }

    @Test func aRepeatedPeriodKeepsTheLastEntry() throws {
        let summary = EnergySummary(
            months: [Self.month(2026, 10, wattHours: 10_000), Self.month(2026, 10, wattHours: 13_831)],
            days: [],
            fetchedAt: try Self.date(2026, 10, 13),
            calendar: Self.calendar
        )

        #expect(summary.months.count == 1)
        #expect(summary.thisMonth == Measurement(value: 13.831, unit: .kilowattHours))
    }

    @Test(arguments: [
        (["energyUsage"], "energyUsage" as String?),
        (["energyUsage_washer", "energyUsage"], "energyUsage"),
        (["energyUsage_dryer"], "energyUsage_dryer"),
        ([], nil),
    ])
    func usagePropertyPrefersEnergyUsage(properties: [String], expected: String?) {
        #expect(EnergySummary.usageProperty(from: properties) == expected)
    }

    @Test func chartBarsHighlightTheCurrentPeriod() throws {
        let summary = EnergySummary(
            months: [Self.month(2026, 9, wattHours: 31_640), Self.month(2026, 10, wattHours: 13_831)],
            days: [Self.day(2026, 10, 12, wattHours: 0), Self.day(2026, 10, 13, wattHours: 1_205)],
            fetchedAt: try Self.date(2026, 10, 13),
            calendar: Self.calendar
        )

        let months = EnergyBar.bars(for: summary, range: .months, calendar: Self.calendar)
        let days = EnergyBar.bars(for: summary, range: .days, calendar: Self.calendar)

        #expect(months.map(\.isCurrent) == [false, true])
        #expect(days.map(\.isCurrent) == [false, true])
        #expect(days.first?.kilowattHours == 0)
        #expect(months.first?.date == (try Self.date(2026, 9, 1, hour: 0)))
    }
}
