import Foundation
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    /// Fan levels, swing, display light and the sleep timer on a real unit's profile.
    @Suite("ACStore fan, swing, light and sleep timer")
    @MainActor
    struct NewControls {
        private static let powerOnBody: JSONObject = ["operation": ["airConOperationMode": "POWER_ON"]]
        private static let cancelBody: JSONObject = ["sleepTimer": ["relativeStopTimer": "UNSET"]]

        private static func sleepBody(hours: Int) -> JSONObject {
            ["sleepTimer": ["relativeHourToStop": .number(Double(hours))]]
        }

        /// The real state (on, no timer) with `delta` merged in.
        private static func realState(_ delta: JSONObject = [:]) throws -> DeviceState {
            try Fixtures.realState().merging(delta: delta)
        }

        private static func realOffState() throws -> DeviceState {
            try realState(["operation": ["airConOperationMode": "POWER_OFF"]])
        }

        /// The state LG reports while a timer runs: `SET` with the time left.
        private static func runningSleepState(minutesLeft: Int) throws -> DeviceState {
            let (hours, minutes) = minutesLeft.quotientAndRemainder(dividingBy: 60)
            return try realState([
                "sleepTimer": [
                    "relativeStopTimer": "SET",
                    "relativeHourToStop": .number(Double(hours)),
                    "relativeMinuteToStop": .number(Double(minutes)),
                ],
            ])
        }

        /// Polls every 60 s so the tests can step through the 3 min sleep-state lag.
        private static func makeHarness(state: DeviceState) throws -> StoreHarness {
            try StoreHarness(state: state, profile: try Fixtures.realProfile()) { settings in
                settings.pollIntervalSeconds = 60
            }
        }

        // MARK: - Power-on prepend

        /// Each new control with the body it POSTs after the implicit POWER_ON.
        nonisolated static let commandsThatNeedPower: [(ACCommand, JSONObject)] = [
            (.fan(.level(2)), ["airFlow": ["windStrengthDetail": "LOW_MID"]]),
            (.fan(.auto), ["airFlow": ["windStrength": "AUTO"]]),
            (.verticalSwing(false), ["windDirection": ["rotateUpDown": false]]),
            (.displayLight(true), ["display": ["light": "ON"]]),
            (.sleepTimer(minutes: 60), ["sleepTimer": ["relativeHourToStop": 1]]),
            (.sleepTimer(minutes: 30), ["sleepTimer": ["relativeHourToStop": 0, "relativeMinuteToStop": 30]]),
        ]

        @Test(arguments: commandsThatNeedPower)
        func newControlsTurnTheACOnFirst(command: ACCommand, body: JSONObject) async throws {
            let harness = try Self.makeHarness(state: try Self.realOffState())
            defer { harness.tearDown() }

            await harness.store.start()
            harness.store.send(command)
            #expect(harness.store.snapshot?.power == .on)

            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies == [Self.powerOnBody, body])
        }

        @Test func newControlsAreSentAloneWhenTheACIsOn() async throws {
            let harness = try Self.makeHarness(state: try Self.realState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.fan(.level(4)))
            store.send(.displayLight(true))
            #expect(store.snapshot?.fan == .level(4))
            #expect(store.snapshot?.displayLight == true)

            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies == [
                ["airFlow": ["windStrengthDetail": "MID_HIGH"]],
                ["display": ["light": "ON"]],
            ])
        }

        // MARK: - Cancel

        @Test func aCancelWhileTheACIsOffIsNotSent() async throws {
            let harness = try Self.makeHarness(state: try Self.realOffState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.sleepTimer(minutes: nil))
            #expect(store.pendingCommands == 0)

            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlCalls.isEmpty)
            #expect(store.snapshot?.power == .off)
        }

        @Test func aCancelWhileTheACIsOnIsSentWithoutPowerOn() async throws {
            let harness = try Self.makeHarness(state: try Self.runningSleepState(minutesLeft: 90))
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(90 * 60)))
            store.send(.sleepTimer(minutes: nil))
            #expect(store.snapshot?.sleepTimer == .off)

            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies == [Self.cancelBody])
            // LG still reports the old timer (state lag): the cancel stays shown.
            #expect(await harness.api.stateCallCount == 2)
            #expect(store.snapshot?.sleepTimer == .off)
        }

        @Test func aCancelLeftAloneByASupersededPickWhileOffIsNotSent() async throws {
            let harness = try Self.makeHarness(state: try Self.realOffState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.sleepTimer(minutes: 60))  // shows the AC on (display-only power-on)
            store.send(.sleepTimer(minutes: nil))  // so this is queued, and supersedes the pick
            #expect(store.pendingCommands == 2)

            await harness.clock.advance(by: .seconds(10))

            // Nothing turned the AC on, so the cancel is skipped too and the AC shows off again.
            #expect(await harness.api.controlCalls.isEmpty)
            #expect(store.pendingCommands == 0)
            #expect(store.snapshot?.power == .off)
        }

        // MARK: - Coalescing

        @Test func aLaterSleepPickSupersedesAQueuedOne() async throws {
            let harness = try Self.makeHarness(state: try Self.realState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.sleepTimer(minutes: 60))
            await settle()  // sent immediately
            store.send(.sleepTimer(minutes: 120))
            await settle()  // waiting for the 3 s slot
            store.send(.sleepTimer(minutes: 180))
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(3 * 3600)))

            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies == [Self.sleepBody(hours: 1), Self.sleepBody(hours: 3)])
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(3 * 3600)))
        }

        // MARK: - State lag

        @Test func staleSleepStatesDoNotRevertTheTimerUntilLGCatchesUp() async throws {
            let harness = try Self.makeHarness(state: try Self.realState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.sleepTimer(minutes: 60))
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(3600)))

            // POST, then the post-burst refresh 4 s later: LG still reports no timer.
            await harness.clock.advance(by: .seconds(10))
            #expect(await harness.api.controlBodies == [Self.sleepBody(hours: 1)])
            #expect(await harness.api.stateCallCount == 2)
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(3600)))

            // A refresh in between (⌘R) is still stale.
            await store.refresh()
            #expect(await harness.api.stateCallCount == 3)
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(3600)))

            // LG catches up at the 60 s poll and counts down: the fetched value wins from now on.
            await harness.api.setDefaultState(try Self.runningSleepState(minutesLeft: 59))
            await harness.clock.advance(by: .seconds(60))
            #expect(await harness.api.stateCallCount == 4)
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(59 * 60)))

            // So a cancel from the LG app shows up on the next poll, well inside the 3 min lag.
            await harness.api.setDefaultState(try Self.realState())
            await harness.clock.advance(by: .seconds(60))
            #expect(await harness.api.stateCallCount == 5)
            #expect(store.snapshot?.sleepTimer == .off)
        }

        @Test func theHeldTimerGivesWayToTheFetchedStateAfterTheLag() async throws {
            let harness = try Self.makeHarness(state: try Self.realState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.sleepTimer(minutes: 120))
            await harness.clock.advance(by: .seconds(150))  // POST, post-burst refresh, 2 polls
            #expect(await harness.api.stateCallCount == 4)
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(7200)))

            // 3 min after the POST LG still reports no timer: believe it.
            await harness.clock.advance(by: .seconds(60))
            #expect(await harness.api.stateCallCount == 5)
            #expect(store.snapshot?.sleepTimer == .off)
        }

        @Test func aFailedSleepPickIsRolledBackAndNotHeld() async throws {
            let harness = try Self.makeHarness(state: try Self.realState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .notProvidedFeature, message: ""))
            store.send(.sleepTimer(minutes: 60))
            #expect(store.snapshot?.sleepTimer == .set(remaining: .seconds(3600)))

            await harness.clock.advance(by: .seconds(10))

            #expect(store.commandFailureMessage != nil)
            #expect(store.snapshot?.sleepTimer == .off)
        }
    }
}
