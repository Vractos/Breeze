import Foundation
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    @Suite("ACStore commands")
    @MainActor
    struct Commands {
        private static let powerOnBody: JSONObject = ["operation": ["airConOperationMode": "POWER_ON"]]

        private static func temperatureBody(_ value: Double) -> JSONObject {
            ["temperature": ["targetTemperature": .number(value)]]
        }

        /// Seconds between consecutive control POSTs.
        private static func gaps(_ calls: [FakeThinQAPI.RecordedCall]) -> [Double] {
            zip(calls.dropFirst(), calls).map { later, earlier in later.at.timeIntervalSince(earlier.at) }
        }

        @Test func controlPostsAreAtLeastThreeSecondsApart() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.fanSpeed(.low))
            store.send(.mode(.airDry))
            store.send(.powerSave(true))
            #expect(store.pendingCommands == 3)

            await harness.clock.advance(by: .seconds(20))

            let controls = await harness.api.controlCalls
            #expect(controls.count == 3)
            #expect(Self.gaps(controls).allSatisfy { $0 >= 3 })
            #expect(await harness.api.controlBodies == [
                ["airFlow": ["windStrength": "LOW"]],
                ["airConJobMode": ["currentJobMode": "AIR_DRY"]],
                ["powerSave": ["powerSaveEnabled": true]],
            ])
            #expect(store.pendingCommands == 0)
        }

        @Test func spacingAlsoAppliesAcrossBursts() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }

            await harness.store.start()
            harness.store.send(.fanSpeed(.low))
            await harness.clock.advance(by: .seconds(1))
            harness.store.send(.fanSpeed(.mid))
            await harness.clock.advance(by: .seconds(10))

            let controls = await harness.api.controlCalls
            #expect(controls.count == 2)
            #expect(Self.gaps(controls) == [3])
        }

        @Test func powerOnIsSentFirstWhenTheACIsOff() async throws {
            let harness = try StoreHarness(state: try Fixtures.offState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.mode(.cool))

            // Optimistic: shown on and cooling before anything was sent.
            #expect(store.snapshot?.power == .on)
            #expect(store.snapshot?.mode == .cool)
            #expect(store.pendingCommands == 1)

            await harness.clock.advance(by: .seconds(10))

            let controls = await harness.api.controlCalls
            #expect(await harness.api.controlBodies == [
                Self.powerOnBody,
                ["airConJobMode": ["currentJobMode": "COOL"]],
            ])
            #expect(Self.gaps(controls).allSatisfy { $0 >= 2 })
        }

        @Test func noPowerOnWhenTheACIsAlreadyOn() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }

            await harness.store.start()
            harness.store.send(.targetTemperature(22))
            await harness.clock.advance(by: .seconds(5))

            #expect(await harness.api.controlBodies == [Self.temperatureBody(22)])
        }

        @Test func burstOfSetpointsSendsOnlyTheLatest() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.targetTemperature(20))
            store.send(.targetTemperature(21))
            store.send(.targetTemperature(22))
            #expect(store.snapshot?.targetTemperature?.value == 22)

            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies == [Self.temperatureBody(22)])
            #expect(store.pendingCommands == 0)
            #expect(store.snapshot?.targetTemperature?.value == 24)  // reconciled with the (unchanged) fake
        }

        @Test func setpointsArrivingDuringTheSpacingWaitAreCoalesced() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.targetTemperature(20))
            await settle()  // sent immediately
            store.send(.targetTemperature(21))
            await settle()  // waiting for the 3 s slot
            store.send(.targetTemperature(22))
            store.send(.targetTemperature(23))

            await harness.clock.advance(by: .seconds(10))

            let controls = await harness.api.controlCalls
            #expect(await harness.api.controlBodies == [Self.temperatureBody(20), Self.temperatureBody(23)])
            #expect(Self.gaps(controls) == [3])
        }

        @Test func redundantPowerErrorCountsAsSuccess() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .commandNotSupportedInState, message: "already on"))
            store.send(.power(.on))
            await harness.clock.advance(by: .seconds(1))

            #expect(await harness.api.controlBodies == [Self.powerOnBody])
            #expect(store.commandFailureMessage == nil)
            #expect(store.phase == .ready)
            #expect(store.snapshot?.power == .on)
        }

        @Test func redundantPowerOffErrorCountsAsSuccess() async throws {
            let harness = try StoreHarness(state: try Fixtures.offState())
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.api.enqueueControl(error: .api(code: .commandNotSupportedInPowerOff, message: "already off"))
            harness.store.send(.power(.off))
            await harness.clock.advance(by: .seconds(1))

            #expect(harness.store.commandFailureMessage == nil)
            #expect(harness.store.snapshot?.power == .off)
        }

        @Test func rejectedCommandIsRolledBackAndReported() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .commandNotSupportedInMode, message: ""))
            store.send(.fanSpeed(.low))
            #expect(store.snapshot?.fanSpeed == .low)

            await harness.clock.advance(by: .seconds(1))

            #expect(store.snapshot?.fanSpeed == .high)
            #expect(store.commandFailureMessage != nil)
            #expect(store.phase == .ready)

            // A refresh is still scheduled after the failed burst.
            await harness.clock.advance(by: .seconds(4))
            #expect(await harness.api.stateCallCount == 2)

            store.dismissCommandFailure()
            #expect(store.commandFailureMessage == nil)
        }

        @Test func invalidTokenOnACommandStopsPolling() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.api.enqueueControl(error: .api(code: .invalidToken, message: ""))
            harness.store.send(.fanSpeed(.low))
            harness.store.send(.mode(.airDry))  // queued behind; must be dropped, not POSTed
            await harness.clock.advance(by: .seconds(10))

            #expect(harness.store.phase == .tokenInvalid)
            #expect(harness.store.commandFailureMessage == nil)
            #expect(await harness.api.controlCalls.count == 1)
            #expect(harness.store.pendingCommands == 0)
            #expect(harness.store.snapshot?.mode == .cool)
        }

        @Test func outOfRangeSetpointIsRejectedWithoutSending() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.targetTemperature(50))
            await harness.clock.advance(by: .seconds(5))

            #expect(store.commandFailureMessage != nil)
            #expect(store.pendingCommands == 0)
            #expect(store.snapshot?.targetTemperature?.value == 24)
            #expect(await harness.api.controlCalls.isEmpty)
        }

        @Test func commandsBeforeStartAreIgnored() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            harness.store.send(.power(.on))
            await settle()

            #expect(harness.store.pendingCommands == 0)
            #expect(await harness.api.calls.isEmpty)
        }

        @Test func optimisticStateSurvivesStaleFetchesThenTheFetchedStateWins() async throws {
            let harness = try StoreHarness(state: try Fixtures.offState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.power(.on))
            #expect(store.snapshot?.power == .on)
            #expect(store.pendingCommands == 1)

            await settle()  // POST done, post-burst refresh scheduled in 4 s
            #expect(store.pendingCommands == 0)
            #expect(await harness.api.controlBodies == [Self.powerOnBody])

            // LG has not caught up yet: a fetch in between must not flicker the UI back to off.
            await harness.api.enqueueState(.success(try Fixtures.offState()))
            await store.refresh()
            #expect(store.snapshot?.power == .on)

            // The post-burst refresh reconciles with what LG reports.
            await harness.api.enqueueState(.success(try Fixtures.onState(target: 26)))
            await harness.clock.advance(by: .seconds(4))
            #expect(await harness.api.stateCallCount == 3)
            #expect(store.snapshot?.power == .on)
            #expect(store.snapshot?.targetTemperature?.value == 26)

            // Once reconciled, fetched state always wins (the AC was switched off by the remote).
            await harness.clock.advance(by: .seconds(120))
            #expect(store.snapshot?.power == .off)
        }

        @Test func pollDuringABurstKeepsOptimisticValuesButPicksUpOtherChanges() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.fanSpeed(.low))
            store.send(.mode(.airDry))  // waits 3 s behind the fan command

            // A refresh lands while the mode command is still queued; the remote changed the setpoint.
            await harness.api.enqueueState(.success(try Fixtures.onState(target: 19)))
            await store.refresh()

            #expect(store.snapshot?.fanSpeed == .low)
            #expect(store.snapshot?.mode == .airDry)
            #expect(store.snapshot?.targetTemperature?.value == 19)
        }

        // MARK: Mode-specific setpoint keys

        @Test func aSetpointIsWrittenForTheModeItWasSentIn() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState(), profile: try Fixtures.coolHeatProfile())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.targetTemperature(19))  // in COOL
            store.send(.mode(.heat))            // queued behind it
            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies == [
                ["temperature": ["coolTargetTemperature": 19]],
                ["airConJobMode": ["currentJobMode": "HEAT"]],
            ])
            #expect(store.commandFailureMessage == nil)
        }

        @Test func setpointsForDifferentModesAreNotCoalesced() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState(), profile: try Fixtures.coolHeatProfile())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            // Sent in one go, so all four are queued before the first one executes.
            store.send(.targetTemperature(20))  // COOL
            store.send(.targetTemperature(21))  // COOL, supersedes 20
            store.send(.mode(.heat))
            store.send(.targetTemperature(17))  // HEAT
            await harness.clock.advance(by: .seconds(20))

            #expect(await harness.api.controlBodies == [
                ["temperature": ["coolTargetTemperature": 21]],
                ["airConJobMode": ["currentJobMode": "HEAT"]],
                ["temperature": ["heatTargetTemperature": 17]],
            ])
        }

        // MARK: Implicit power-on

        @Test func aMidBurstFetchReportingOffMakesTheQueueSendPowerOn() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.fanSpeed(.low))
            await settle()  // POSTed; post-burst refresh pending, so the next fetch is not quiet

            // The remote switched the AC off meanwhile.
            await harness.api.enqueueState(.success(try Fixtures.onState().merging(delta: [
                "operation": ["airConOperationMode": "POWER_OFF"],
            ])))
            await store.refresh()
            #expect(store.snapshot?.power == .off)

            store.send(.mode(.airDry))
            #expect(store.snapshot?.power == .on)
            await harness.clock.advance(by: .seconds(10))

            #expect(await harness.api.controlBodies.dropFirst() == [
                Self.powerOnBody,
                ["airConJobMode": ["currentJobMode": "AIR_DRY"]],
            ])
            #expect(store.commandFailureMessage == nil)
        }

        @Test func aFailedImplicitPowerOnShowsTheACOffAgain() async throws {
            let harness = try StoreHarness(state: try Fixtures.offState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .failDeviceControl, message: ""))
            store.send(.mode(.cool))
            #expect(store.snapshot?.power == .on)
            await harness.clock.advance(by: .seconds(1))

            #expect(await harness.api.controlBodies == [Self.powerOnBody])
            #expect(store.snapshot?.power == .off)
            #expect(store.snapshot?.mode == .fan)
            #expect(store.commandFailureMessage != nil)
        }

        @Test func aCommandRejectedBecauseTheACIsOffShowsItOffAndTheNextOneTurnsItOn() async throws {
            // The fetched state still says on, but the remote switched the AC off.
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .commandNotSupportedInPowerOff, message: ""))
            store.send(.fanSpeed(.low))
            await harness.clock.advance(by: .seconds(1))

            #expect(store.snapshot?.power == .off)
            #expect(store.commandFailureMessage != nil)

            store.send(.fanSpeed(.low))
            await harness.clock.advance(by: .seconds(10))
            #expect(await harness.api.controlBodies == [
                ["airFlow": ["windStrength": "LOW"]],
                Self.powerOnBody,
                ["airFlow": ["windStrength": "LOW"]],
            ])
            #expect(store.snapshot?.power == .on)
        }

        @Test func aCoalescedSetpointsPowerOnIsStillSent() async throws {
            let harness = try StoreHarness(state: try Fixtures.offState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.targetTemperature(20))  // AC off: implicit power-on, then 20
            store.send(.targetTemperature(22))  // AC shown on: no implicit power-on; supersedes 20
            #expect(store.snapshot?.power == .on)

            await settle()  // 20 is dropped; the panel keeps showing the AC on
            #expect(store.snapshot?.power == .on)
            await harness.clock.advance(by: .seconds(4))  // before the post-burst refresh

            #expect(await harness.api.controlBodies == [Self.powerOnBody, Self.temperatureBody(22)])
            #expect(store.snapshot?.power == .on)
        }

        // MARK: No-op setpoints

        @Test func aSetpointEqualToTheCurrentTargetIsNotSent() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState(target: 24))
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            store.send(.targetTemperature(24))
            await harness.clock.advance(by: .seconds(10))

            #expect(store.pendingCommands == 0)
            #expect(await harness.api.controlCalls.isEmpty)
            #expect(await harness.api.stateCallCount == 1)  // no post-burst refresh either
        }

        @Test func aTargetReportedOutsideTheRangeIsStillCorrected() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState(target: 31))
            defer { harness.tearDown() }

            await harness.store.start()
            harness.store.send(.targetTemperature(30))
            await harness.clock.advance(by: .seconds(1))

            #expect(await harness.api.controlBodies == [Self.temperatureBody(30)])
        }

        // MARK: 2210 RETRY_REQUEST

        @Test func retryRequestIsRetriedOnceAfterTheSpacing() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .retryRequest, message: ""))
            store.send(.fanSpeed(.low))
            await harness.clock.advance(by: .seconds(4))  // before the post-burst refresh

            let controls = await harness.api.controlCalls
            #expect(controls.count == 2)
            #expect(Self.gaps(controls) == [3])
            #expect(store.commandFailureMessage == nil)
            #expect(store.snapshot?.fanSpeed == .low)
        }

        @Test func aSecondRetryRequestFailsTheCommand() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await harness.api.enqueueControl(error: .api(code: .retryRequest, message: ""))
            await harness.api.enqueueControl(error: .api(code: .retryRequest, message: ""))
            store.send(.fanSpeed(.low))
            await harness.clock.advance(by: .seconds(3))

            #expect(await harness.api.controlCalls.count == 2)
            #expect(store.commandFailureMessage != nil)
            #expect(store.snapshot?.fanSpeed == .high)
        }
    }
}
