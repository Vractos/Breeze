import Foundation
import Security
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    @Suite("ACStore lifecycle")
    @MainActor
    struct Lifecycle {
        @Test func withoutTokenNeedsSetupAndCallsNothing() async throws {
            let harness = try StoreHarness(token: nil)
            defer { harness.tearDown() }

            await harness.store.start()

            #expect(harness.store.phase == .needsSetup)
            #expect(!harness.store.hasToken)
            #expect(await harness.api.calls.isEmpty)
            #expect(harness.clock.pendingSleeps.isEmpty)
        }

        @Test func keychainFailureIsAnErrorPhase() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            harness.tokenStore.failure = .unexpectedStatus(-25293)

            await harness.store.start()

            guard case .error = harness.store.phase else {
                Issue.record("expected .error, got \(harness.store.phase)")
                return
            }
            #expect(await harness.api.calls.isEmpty)
        }

        @Test func startLoadsDeviceProfileAndStateThenIsReady() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()

            #expect(store.phase == .ready)
            #expect(store.hasToken)
            #expect(store.device == Fixtures.livingRoomAC)
            #expect(store.capabilities?.modes == [.airDry, .cool, .airClean])
            #expect(store.snapshot?.power == .off)
            #expect(store.snapshot?.mode == .fan)
            #expect(store.snapshot?.targetTemperature?.value == 24.5)
            #expect(store.snapshot?.currentTemperature?.value == 27)
            #expect(store.lastSync == harness.clock.now)
            #expect(!store.isSyncing)
            #expect(store.availableDevices == [Fixtures.livingRoomAC])

            let calls = await harness.api.calls.map(\.call)
            #expect(calls == [.devices, .profile(Fixtures.livingRoomAC.id), .state(Fixtures.livingRoomAC.id)])

            let configuration = try #require(harness.configurations.first)
            #expect(configuration.accessToken == "test-token")
            #expect(configuration.countryCode == "BR")
            #expect(configuration.clientID == harness.settings.clientID)
        }

        @Test func startTwiceIsANoOp() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.store.start()

            #expect(await harness.api.calls.count == 3)
            #expect(harness.configurations.count == 1)
        }

        @Test func savedDeviceIsUsedWhenStillOnTheAccount() async throws {
            let harness = try StoreHarness(devices: [Fixtures.livingRoomAC, Fixtures.bedroomAC]) { settings in
                settings.selectedDeviceID = Fixtures.bedroomAC.id
            }
            defer { harness.tearDown() }

            await harness.store.start()

            #expect(harness.store.device == Fixtures.bedroomAC)
            #expect(harness.settings.selectedDeviceID == Fixtures.bedroomAC.id)
        }

        @Test func missingSavedDeviceFallsBackToFirstAirConditionerAndPersistsIt() async throws {
            let harness = try StoreHarness(devices: [Fixtures.washer, Fixtures.bedroomAC, Fixtures.livingRoomAC]) { settings in
                settings.selectedDeviceID = "gone"
            }
            defer { harness.tearDown() }

            await harness.store.start()

            #expect(harness.store.device == Fixtures.bedroomAC)
            #expect(harness.settings.selectedDeviceID == Fixtures.bedroomAC.id)
            #expect(harness.store.availableDevices == [Fixtures.bedroomAC, Fixtures.livingRoomAC])
            // A fresh AppSettings on the same defaults sees the persisted choice.
            #expect(AppSettings(defaults: harness.defaults).selectedDeviceID == Fixtures.bedroomAC.id)
        }

        @Test func noAirConditionerIsAnErrorAndStopsPolling() async throws {
            let harness = try StoreHarness(devices: [Fixtures.washer])
            defer { harness.tearDown() }

            await harness.store.start()
            await settle()

            guard case .error = harness.store.phase else {
                Issue.record("expected .error, got \(harness.store.phase)")
                return
            }
            #expect(harness.store.device == nil)
            #expect(harness.clock.pendingSleeps.isEmpty)
        }

        @Test func reconfigureCancelsTheOldLoopsAndRestartsWithNewSettings() async throws {
            let harness = try StoreHarness(devices: [Fixtures.livingRoomAC, Fixtures.bedroomAC])
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            await settle()
            #expect(harness.clock.pendingSleeps == [.seconds(120)])

            harness.settings.selectedDeviceID = Fixtures.bedroomAC.id
            harness.settings.countryCode = "US"
            await store.reconfigure()
            await settle()

            #expect(store.phase == .ready)
            #expect(store.device == Fixtures.bedroomAC)
            #expect(harness.configurations.count == 2)
            #expect(harness.configurations.last?.countryCode == "US")
            // Only the new session's poll loop is sleeping.
            #expect(harness.clock.pendingSleeps == [.seconds(120)])

            await harness.clock.advance(by: .seconds(120))
            let stateCalls = await harness.api.calls.map(\.call).filter { if case .state = $0 { true } else { false } }
            #expect(stateCalls == [
                .state(Fixtures.livingRoomAC.id),
                .state(Fixtures.bedroomAC.id),
                .state(Fixtures.bedroomAC.id),
            ])
        }

        @Test func selectDevicePersistsAndReloads() async throws {
            let harness = try StoreHarness(devices: [Fixtures.livingRoomAC, Fixtures.bedroomAC])
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.store.selectDevice(id: Fixtures.bedroomAC.id)

            #expect(harness.store.device == Fixtures.bedroomAC)
            #expect(harness.settings.selectedDeviceID == Fixtures.bedroomAC.id)
        }

        @Test func saveTokenStoresTrimmedTokenAndRestarts() async throws {
            let harness = try StoreHarness(token: nil)
            defer { harness.tearDown() }

            await harness.store.start()
            #expect(harness.store.phase == .needsSetup)

            let saved = await harness.store.saveToken("  new-token \n")

            #expect(saved)
            #expect(harness.tokenStore.storedToken == "new-token")
            #expect(harness.store.phase == .ready)
            #expect(harness.configurations.last?.accessToken == "new-token")

            await harness.store.removeToken()
            #expect(harness.tokenStore.storedToken == nil)
            #expect(harness.store.phase == .needsSetup)
            #expect(harness.store.snapshot == nil)
        }

        @Test func stopCancelsEverySleep() async throws {
            let harness = try StoreHarness(state: try Fixtures.onState())
            defer { harness.tearDown() }

            await harness.store.start()
            harness.store.send(.fan(.level(1)))
            await settle()
            #expect(harness.clock.pendingSleeps.count == 2)  // poll + post-burst refresh

            harness.store.stop()
            await settle()

            #expect(harness.clock.pendingSleeps.isEmpty)
            #expect(harness.store.pendingCommands == 0)
        }

        @Test func testConnectionReportsAirConditionerCount() async throws {
            let harness = try StoreHarness(token: nil, devices: [Fixtures.washer, Fixtures.livingRoomAC, Fixtures.bedroomAC])
            defer { harness.tearDown() }

            #expect(await harness.store.testConnection() == .missingToken)
            #expect(await harness.store.testConnection(token: "candidate") == .success(airConditioners: 2))
            #expect(harness.configurations.last?.accessToken == "candidate")
            // Testing never saves the token, and a typed token's devices never reach the picker.
            #expect(harness.tokenStore.storedToken == nil)
            #expect(harness.store.availableDevices.isEmpty)

            await harness.api.enqueueDevices(.failure(.api(code: .invalidToken, message: "")))
            #expect(await harness.store.testConnection(token: "bad") == .tokenInvalid)

            await harness.api.enqueueDevices(.failure(.api(code: .notSupportedCountry, message: "")))
            #expect(await harness.store.testConnection(token: "candidate") == .unsupportedCountry)

            await harness.api.setDevices([Fixtures.washer])
            #expect(await harness.store.testConnection(token: "candidate") == .noAirConditioners)
        }

        @Test func onlyATestOfTheSavedTokenUpdatesTheDeviceList() async throws {
            let harness = try StoreHarness(devices: [Fixtures.livingRoomAC])
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            #expect(store.availableDevices == [Fixtures.livingRoomAC])

            // Another account's token: reported, not listed.
            await harness.api.setDevices([Fixtures.bedroomAC])
            #expect(await store.testConnection(token: "other-account") == .success(airConditioners: 1))
            #expect(store.availableDevices == [Fixtures.livingRoomAC])

            // The saved token (nil or blank): the list follows the account.
            #expect(await store.testConnection(token: nil) == .success(airConditioners: 1))
            #expect(store.availableDevices == [Fixtures.bedroomAC])
            await harness.api.setDevices([Fixtures.livingRoomAC, Fixtures.bedroomAC])
            #expect(await store.testConnection(token: "  ") == .success(airConditioners: 2))
            #expect(store.availableDevices == [Fixtures.livingRoomAC, Fixtures.bedroomAC])
        }

        @Test func removingTheTokenClearsTheDeviceList() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            #expect(!harness.store.availableDevices.isEmpty)

            #expect(await harness.store.removeToken())
            #expect(harness.store.phase == .needsSetup)
            #expect(harness.store.availableDevices.isEmpty)
        }

        @Test func deniedKeychainAccessHasItsOwnMessage() async throws {
            let harness = try StoreHarness()
            defer { harness.tearDown() }
            harness.tokenStore.failure = .accessDenied(errSecAuthFailed)

            await harness.store.start()

            guard case .error(let message) = harness.store.phase else {
                Issue.record("expected .error, got \(harness.store.phase)")
                return
            }
            #expect(message.contains("Keychain Access"))
            #expect(await harness.store.testConnection() == .failed(message))
            #expect(await harness.api.calls.isEmpty)
        }

        @Test func keychainStatusesMapToAccessDenied() {
            #expect(KeychainError(status: errSecAuthFailed) == .accessDenied(errSecAuthFailed))
            #expect(KeychainError(status: errSecUserCanceled) == .accessDenied(errSecUserCanceled))
            #expect(KeychainError(status: errSecInteractionNotAllowed) == .accessDenied(errSecInteractionNotAllowed))
            #expect(KeychainError(status: errSecDuplicateItem) == .unexpectedStatus(errSecDuplicateItem))
        }
    }
}
