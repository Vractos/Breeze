import Foundation
import Testing
@testable import Breeze
import ThinQKit

@Suite("Held sleep timer")
struct HeldSleepTimerTests {
    private static let postedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func minutes(_ value: Double) -> Date {
        postedAt.addingTimeInterval(value * 60)
    }

    private static func running(_ minutesLeft: Int?) -> SleepTimerState {
        .set(remaining: minutesLeft.map { .seconds($0 * 60) })
    }

    @Test func aCancelIsReflectedOnlyByOff() {
        let held = ACStore.HeldSleepTimer(minutes: nil, postedAt: Self.postedAt)
        #expect(held.isReflected(by: .off, at: Self.minutes(1)))
        #expect(!held.isReflected(by: Self.running(60), at: Self.minutes(1)))
        #expect(!held.isReflected(by: nil, at: Self.minutes(1)))
    }

    @Test func aNewTimerIsReflectedByACountdownFromItsDuration() {
        let held = ACStore.HeldSleepTimer(minutes: 60, postedAt: Self.postedAt)
        #expect(held.isReflected(by: Self.running(60), at: Self.minutes(0.5)))
        #expect(held.isReflected(by: Self.running(57), at: Self.minutes(2)))
        #expect(held.isReflected(by: Self.running(nil), at: Self.minutes(1)))
    }

    @Test func anOldTimerIsNotMistakenForTheNewOne() {
        let held = ACStore.HeldSleepTimer(minutes: 60, postedAt: Self.postedAt)
        #expect(!held.isReflected(by: .off, at: Self.minutes(1)))
        #expect(!held.isReflected(by: Self.running(110), at: Self.minutes(1)))  // a longer one still running
        #expect(!held.isReflected(by: Self.running(20), at: Self.minutes(1)))   // a shorter one about to end
    }

    @Test func itExpiresAfterTheStateLag() {
        let held = ACStore.HeldSleepTimer(minutes: 60, postedAt: Self.postedAt)
        #expect(!held.hasExpired(at: Self.minutes(2.9)))
        #expect(held.hasExpired(at: Self.minutes(3)))
    }
}
