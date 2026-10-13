import Foundation
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    @Suite("ACStore refresh and polling")
    @MainActor
    struct Refresh {
        private static let rateLimited = ThinQError.api(code: .exceededAPICalls, message: "")
        private static let invalidToken = ThinQError.api(code: .invalidToken, message: "")
        private static let offline = ThinQError.api(code: .notConnectedDevice, message: "")
        private static let deviceResponseDelay = ThinQError.api(code: .deviceResponseDelay, message: "")

        @Test func pollsAtTheConfiguredInterval() async throws {
            let harness = try StoreHarness { $0.pollIntervalSeconds = 180 }
            defer { harness.tearDown() }

            await harness.store.start()
            await settle()
            #expect(harness.clock.pendingSleeps == [.seconds(180)])

            await harness.clock.advance(by: .seconds(179))
            #expect(await harness.api.stateCallCount == 1)

            await harness.clock.advance(by: .seconds(1))
            #expect(await harness.api.stateCallCount == 2)
            #expect(harness.store.lastSync == harness.clock.now)
            #expect(harness.clock.pendingSleeps == [.seconds(180)])
        }

        @Test(arguments: [(10, 60), (59, 60), (60, 60), (600, 600), (5000, 600)])
        func pollIntervalIsClamped(configured: Int, expected: Int) async throws {
            let harness = try StoreHarness { $0.pollIntervalSeconds = configured }
            defer { harness.tearDown() }

            await harness.store.start()
            await settle()

            #expect(harness.clock.pendingSleeps == [.seconds(expected)])
        }

        @Test func rateLimitDoublesTheIntervalUpToFifteenMinutesThenResets() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let clock = harness.clock

            await harness.store.start()
            for _ in 0..<4 {
                await harness.api.enqueueState(.failure(Self.rateLimited))
            }

            await clock.advance(by: .seconds(120))
            #expect(harness.store.phase == .rateLimited(until: clock.now.addingTimeInterval(240)))
            #expect(clock.pendingSleeps == [.seconds(240)])

            await clock.advance(by: .seconds(240))
            #expect(harness.store.phase == .rateLimited(until: clock.now.addingTimeInterval(480)))
            #expect(clock.pendingSleeps == [.seconds(480)])

            await clock.advance(by: .seconds(480))
            #expect(harness.store.phase == .rateLimited(until: clock.now.addingTimeInterval(900)))
            #expect(clock.pendingSleeps == [.seconds(900)])

            await clock.advance(by: .seconds(900))
            #expect(clock.pendingSleeps == [.seconds(900)])  // capped

            await clock.advance(by: .seconds(900))
            #expect(harness.store.phase == .ready)
            #expect(clock.pendingSleeps == [.seconds(120)])  // reset after success
            #expect(await harness.api.stateCallCount == 6)
        }

        @Test func rateLimitDuringStartupRetriesAfterBackoff() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            await harness.api.enqueueDevices(.failure(Self.rateLimited))

            await harness.store.start()
            await settle()

            #expect(harness.store.phase == .rateLimited(until: harness.clock.now.addingTimeInterval(240)))
            #expect(harness.store.snapshot == nil)
            #expect(harness.clock.pendingSleeps == [.seconds(240)])

            await harness.clock.advance(by: .seconds(240))
            #expect(harness.store.phase == .ready)
            #expect(harness.store.snapshot != nil)
        }

        @Test func invalidTokenStopsPollingUntilReconfigure() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.api.enqueueState(.failure(Self.invalidToken))
            await harness.clock.advance(by: .seconds(120))

            #expect(harness.store.phase == .tokenInvalid)
            #expect(harness.clock.pendingSleeps.isEmpty)

            await harness.clock.advance(by: .seconds(3600))
            await harness.store.refresh()
            await harness.store.panelDidAppear()
            #expect(await harness.api.stateCallCount == 2)

            await harness.store.reconfigure()
            await settle()
            #expect(harness.store.phase == .ready)
            #expect(harness.clock.pendingSleeps == [.seconds(120)])
        }

        @Test func offlineKeepsTheSnapshotAndPollingAtTheNormalInterval() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.api.enqueueState(.failure(Self.offline))
            await harness.clock.advance(by: .seconds(120))

            #expect(harness.store.phase == .offline)
            #expect(harness.store.snapshot != nil)
            #expect(harness.clock.pendingSleeps == [.seconds(120)])

            await harness.clock.advance(by: .seconds(120))
            #expect(harness.store.phase == .ready)
        }

        @Test func otherErrorsShowAMessageAndKeepPolling() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.api.enqueueState(.failure(.transport(underlying: URLError(.notConnectedToInternet))))
            await harness.clock.advance(by: .seconds(120))

            guard case .error(let message) = harness.store.phase else {
                Issue.record("expected .error, got \(harness.store.phase)")
                return
            }
            #expect(!message.isEmpty)
            #expect(harness.clock.pendingSleeps == [.seconds(120)])
        }

        @Test func concurrentRefreshesShareOneRequest() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.holdStateRequests()

            let first = Task { await store.refresh() }
            let second = Task { await store.refresh() }
            let third = Task { await store.refresh() }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })
            await settle()
            #expect(store.isSyncing)
            #expect(await harness.api.stateCallCount == 2)

            await harness.api.releaseHeldStateRequests()
            await first.value
            await second.value
            await third.value

            #expect(await harness.api.stateCallCount == 2)
            #expect(!store.isSyncing)
        }

        @Test func panelOpenRefreshesOnlyWhenTheLastSyncIsOlderThan15Seconds() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.clock.advance(by: .seconds(14))
            await harness.store.panelDidAppear()
            #expect(await harness.api.stateCallCount == 1)

            await harness.clock.advance(by: .seconds(1))
            await harness.store.panelDidAppear()
            #expect(await harness.api.stateCallCount == 2)

            harness.store.panelDidDisappear()
            await settle()
            #expect(await harness.api.stateCallCount == 2)
        }

        @Test func panelOpenDoesNotRefreshWhileRateLimited() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.api.enqueueState(.failure(Self.rateLimited))
            await harness.clock.advance(by: .seconds(120))
            await harness.clock.advance(by: .seconds(30))

            await harness.store.panelDidAppear()

            #expect(await harness.api.stateCallCount == 2)
        }

        @Test func panelOpensWhileOfflineAreLimitedByTheLastAttempt() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueState(.failure(Self.offline))
            await harness.clock.advance(by: .seconds(120))
            #expect(store.phase == .offline)
            #expect(await harness.api.stateCallCount == 2)

            // The last success is 140 s old, but the last attempt only 20 s: one refresh…
            await harness.clock.advance(by: .seconds(20))
            await harness.api.enqueueState(.failure(Self.offline))
            await store.panelDidAppear()
            #expect(await harness.api.stateCallCount == 3)

            // …and a second open 5 s later doesn't send another request.
            await harness.clock.advance(by: .seconds(5))
            await store.panelDidAppear()
            #expect(await harness.api.stateCallCount == 3)
            #expect(store.phase == .offline)
        }

        @Test func aShorterPollIntervalAppliesWithoutWaitingOutTheOldSleep() async throws {
            let harness = try StoreHarness { $0.pollIntervalSeconds = 600 }
            defer { harness.tearDown() }

            await harness.store.start()
            await settle()
            #expect(harness.clock.pendingSleeps == [.seconds(600)])

            harness.settings.pollIntervalSeconds = 60
            harness.store.pollIntervalDidChange()
            await settle()
            // The old 600 s sleep is gone; only the new loop waits.
            #expect(harness.clock.pendingSleeps == [.seconds(60)])

            await harness.clock.advance(by: .seconds(60))
            #expect(await harness.api.stateCallCount == 2)
            #expect(harness.clock.pendingSleeps == [.seconds(60)])
        }

        @Test func aNewPollIntervalCountsFromTheLastFetch() async throws {
            let harness = try StoreHarness { $0.pollIntervalSeconds = 600 }
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.clock.advance(by: .seconds(100))

            harness.settings.pollIntervalSeconds = 120
            harness.store.pollIntervalDidChange()
            await settle()
            #expect(harness.clock.pendingSleeps == [.seconds(20)])

            // Already overdue: fetch right away.
            harness.settings.pollIntervalSeconds = 60
            harness.store.pollIntervalDidChange()
            await settle()
            #expect(await harness.api.stateCallCount == 2)
            #expect(harness.clock.pendingSleeps == [.seconds(60)])
        }

        @Test func deviceResponseDelayIsRetriedOnceAndThenReconciles() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueState(.failure(Self.deviceResponseDelay))
            await harness.api.enqueueState(.success(try Fixtures.onState(target: 21)))

            await harness.clock.advance(by: .seconds(120))
            // The 2209 changes nothing the panel shows.
            #expect(store.phase == .ready)
            #expect(store.snapshot?.power == .off)
            #expect(await harness.api.stateCallCount == 2)

            await harness.clock.advance(by: .seconds(3))
            #expect(await harness.api.stateCallCount == 3)
            #expect(store.phase == .ready)
            #expect(store.snapshot?.power == .on)
            #expect(store.snapshot?.targetTemperature?.value == 21)
        }

        @Test func aPersistentDeviceResponseDelayCostsOneExtraFetchThenShowsAnError() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueState(.failure(Self.deviceResponseDelay))
            await harness.api.enqueueState(.failure(Self.deviceResponseDelay))

            await harness.clock.advance(by: .seconds(123))
            #expect(await harness.api.stateCallCount == 3)
            guard case .error = store.phase else {
                Issue.record("expected .error, got \(store.phase)")
                return
            }
            // No further retry; the next request is the regular poll.
            #expect(harness.clock.pendingSleeps == [.seconds(117)])

            // The next poll's own 2209 is retried again.
            await harness.api.enqueueState(.failure(Self.deviceResponseDelay))
            await harness.clock.advance(by: .seconds(117))
            #expect(await harness.api.stateCallCount == 4)
            await harness.clock.advance(by: .seconds(3))
            #expect(await harness.api.stateCallCount == 5)
            #expect(store.phase == .ready)
        }
    }
}
