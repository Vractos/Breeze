import Foundation
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    /// 1306 (hourly quota used up) from a request other than the poll itself: no
    /// automatic GET inside the window, and one quota event doubles the back-off once.
    @Suite("ACStore rate limiting")
    @MainActor
    struct RateLimit {
        private static let rateLimited = ThinQError.api(code: .exceededAPICalls, message: "")

        private static func stateCallTimes(_ api: FakeThinQAPI) async -> [Date] {
            await api.calls.compactMap { if case .state = $0.call { $0.at } else { nil } }
        }

        @Test func aCommandHitting1306SilencesThePostBurstRefreshAndThePollUntilTheDeadline() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let clock = harness.clock
            let store = harness.store
            let start = clock.now

            await store.start()
            await clock.advance(by: .seconds(100))
            await harness.api.enqueueControl(error: Self.rateLimited)
            store.send(.fan(.level(1)))
            await settle()

            // Back-off doubled once: 120 → 240 s from the POST at t=100.
            let deadline = start.addingTimeInterval(340)
            #expect(store.phase == .rateLimited(until: deadline))

            // Neither the post-burst refresh (t=104) nor the poll that was asleep since t=0 (due
            // at t=120) goes out inside the window.
            await clock.advance(by: .seconds(239))
            #expect(await Self.stateCallTimes(harness.api) == [start])
            #expect(store.phase == .rateLimited(until: deadline))

            // Polling resumes exactly at the deadline and the back-off resets.
            await clock.advance(by: .seconds(1))
            #expect(await Self.stateCallTimes(harness.api) == [start, deadline])
            #expect(store.phase == .ready)
            #expect(clock.pendingSleeps == [.seconds(120)])
        }

        @Test func aPanelOpenHitting1306MidIntervalMovesTheNextPollToTheDeadline() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let clock = harness.clock
            let start = clock.now

            await harness.store.start()
            await clock.advance(by: .seconds(60))
            await harness.api.enqueueState(.failure(Self.rateLimited))
            await harness.store.panelDidAppear()

            let deadline = start.addingTimeInterval(300)
            #expect(harness.store.phase == .rateLimited(until: deadline))

            await clock.advance(by: .seconds(239))  // t=299; the old schedule would have polled at t=120
            #expect(await Self.stateCallTimes(harness.api) == [start, start.addingTimeInterval(60)])

            await clock.advance(by: .seconds(1))
            #expect(await Self.stateCallTimes(harness.api) == [start, start.addingTimeInterval(60), deadline])
            #expect(harness.store.phase == .ready)
        }

        @Test func aManualRefreshInsideTheWindowDoesNotDoubleTheBackoffAgain() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let clock = harness.clock
            let start = clock.now

            await harness.store.start()
            await harness.api.enqueueState(.failure(Self.rateLimited))
            await clock.advance(by: .seconds(120))
            let deadline = start.addingTimeInterval(360)
            #expect(harness.store.phase == .rateLimited(until: deadline))

            // ⌘R stays allowed, but its 1306 is the same quota event.
            await clock.advance(by: .seconds(30))
            await harness.api.enqueueState(.failure(Self.rateLimited))
            await harness.store.refresh()
            #expect(harness.store.phase == .rateLimited(until: deadline))
            #expect(await harness.api.stateCallCount == 3)

            await clock.advance(by: .seconds(209))
            #expect(await harness.api.stateCallCount == 3)
            await clock.advance(by: .seconds(1))
            #expect(await harness.api.stateCallCount == 4)
            #expect(harness.store.phase == .ready)
        }
    }
}
