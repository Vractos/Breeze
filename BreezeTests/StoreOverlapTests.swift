import Foundation
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    /// Requests that overlap: a GET still in flight while a command POST changes the picture.
    @Suite("ACStore overlapping requests")
    @MainActor
    struct Overlap {
        @Test func aFetchLandingAfterAHaltKeepsTheHaltPhase() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.holdStateRequests()
            let refreshing = Task { await store.refresh() }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })

            // The command POST is rejected with 1103 while the GET is still out.
            await harness.api.enqueueControl(error: .api(code: .invalidToken, message: ""))
            store.send(.fanSpeed(.low))
            await settle()
            #expect(store.phase == .tokenInvalid)

            await harness.api.releaseHeldStateRequests()
            await refreshing.value
            await settle()

            #expect(store.phase == .tokenInvalid)
            // Still halted: commands are dropped, nothing polls.
            store.send(.mode(.airDry))
            await harness.clock.advance(by: .seconds(600))
            #expect(store.pendingCommands == 0)
            #expect(await harness.api.controlCalls.count == 1)
            #expect(await harness.api.stateCallCount == 2)
        }

        @Test func aNewCommandStillCancelsAPostBurstRefreshThatIsWaitingForAFetch() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.fanSpeed(.low))
            await settle()  // POSTed at t=0; post-burst refresh due at t=4

            await harness.api.holdStateRequests()
            let refreshing = Task { await store.refresh() }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })

            // The post-burst task wakes and waits for the held fetch…
            await harness.clock.advance(by: .seconds(4))
            // …then a new command arrives: it must cancel that task.
            store.send(.mode(.airDry))
            await settle()
            #expect(await harness.api.controlCalls.count == 2)

            await harness.api.releaseHeldStateRequests()
            await refreshing.value
            await settle()
            #expect(await harness.api.stateCallCount == 2)

            // Only the new burst's refresh, 4 s after its POST, fetches again.
            await harness.clock.advance(by: .seconds(3))
            #expect(await harness.api.stateCallCount == 2)
            await harness.clock.advance(by: .seconds(1))
            #expect(await harness.api.stateCallCount == 3)
        }

        /// A GET that started before a send and lands after its POST predates the command: it
        /// must not reconcile, even though the queue already drained by then.
        @Test func aFetchThatOverlappedASendKeepsTheOptimisticValue() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState(target: 24))
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.holdStateRequests()
            let refreshing = Task { await store.refresh() }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })

            store.send(.targetTemperature(26))
            await settle()
            #expect(await harness.api.controlCalls.count == 1)
            #expect(store.pendingCommands == 0)

            // The post-burst refresh wakes and waits for the held (old) fetch.
            await harness.clock.advance(by: .seconds(5))
            await harness.api.releaseHeldStateRequests()
            await harness.api.holdStateRequests()
            await refreshing.value
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })

            // The old fetch landed (target 24) and the post-burst GET is out: still optimistic.
            #expect(await harness.api.stateCallCount == 3)
            #expect(store.snapshot?.targetTemperature?.value == 26)

            await harness.api.enqueueState(.success(try Fixtures.onState(target: 26)))
            await harness.api.releaseHeldStateRequests()
            await settle()
            #expect(store.snapshot?.targetTemperature?.value == 26)
            #expect(await harness.api.stateCallCount == 3)
        }
    }
}
