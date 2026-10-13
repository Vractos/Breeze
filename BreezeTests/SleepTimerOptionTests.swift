import Foundation
import Testing
@testable import Breeze
import ThinQKit

@Suite("Sleep timer option")
struct SleepTimerOptionTests {
    @Test func everyOptionIsADurationLGAccepts() throws {
        let caps = try AirConditionerCapabilities(profile: try Fixtures.realProfile())
        for option in SleepTimerOption.all {
            #expect(throws: Never.self) { try option.command.payload(for: caps, currentMode: .cool) }
        }
        #expect(SleepTimerOption.all.first == .off)
        #expect(SleepTimerOption.all.last == .minutes(720))
    }

    @Test func offCancelsAndADurationSetsTheTimer() {
        #expect(SleepTimerOption.off.command == .sleepTimer(minutes: nil))
        #expect(SleepTimerOption.minutes(30).command == .sleepTimer(minutes: 30))
    }

    /// Nothing is checked while a timer runs, so the same duration can be picked to restart it.
    @Test func onlyOffIsEverSelected() {
        #expect(SleepTimerOption.selection(for: .off) == .off)
        #expect(SleepTimerOption.selection(for: .set(remaining: .seconds(3600))) == nil)
        #expect(SleepTimerOption.selection(for: nil) == nil)
    }

    @Test func theCardShowsTheTimeLeftWhileATimerRuns() {
        let remaining = Duration.seconds(80 * 60)
        let running = SleepTimerState.set(remaining: remaining)
        // "1h 20m" / "1 hour, 20 minutes left" in English; durations follow the machine's locale.
        let narrow = remaining.formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        let wide = remaining.formatted(.units(allowed: [.hours, .minutes], width: .wide))
        #expect(SleepTimerOption.cardValue(for: running).map { String(localized: $0) } == narrow)
        #expect(SleepTimerOption.accessibilityValue(for: running).map { String(localized: $0) } == "\(wide) left")
        #expect(SleepTimerOption.cardValue(for: .set(remaining: nil)).map { String(localized: $0) } == "On")
        #expect(SleepTimerOption.cardValue(for: .off) == nil)
        #expect(SleepTimerOption.accessibilityValue(for: nil) == nil)
    }
}
