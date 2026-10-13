import Testing
@testable import Breeze

@Suite("PollSchedule")
struct PollScheduleTests {
    @Test func doublesFromTheBaseUpToFifteenMinutesAndResets() {
        let base: Duration = .seconds(120)
        var schedule = PollSchedule()
        #expect(schedule.interval(base: base) == .seconds(120))

        #expect(schedule.recordRateLimit(base: base) == .seconds(240))
        #expect(schedule.recordRateLimit(base: base) == .seconds(480))
        #expect(schedule.recordRateLimit(base: base) == .seconds(900))
        #expect(schedule.recordRateLimit(base: base) == .seconds(900))
        #expect(schedule.interval(base: base) == .seconds(900))

        schedule.recordSuccess()
        #expect(schedule.interval(base: base) == .seconds(120))
    }

    @Test func baseChangesApplyWhenNotBackingOff() {
        var schedule = PollSchedule()
        #expect(schedule.interval(base: .seconds(300)) == .seconds(300))
        #expect(schedule.recordRateLimit(base: .seconds(300)) == .seconds(600))
    }
}
