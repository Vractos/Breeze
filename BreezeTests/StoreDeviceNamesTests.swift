import Foundation
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    /// Local nicknames, collision labels and the Device tab's live preview.
    @Suite("ACStore device names and previews")
    @MainActor
    struct DeviceNames {
        private static let account = [Fixtures.arCondicionadoSala, Fixtures.arCondicionadoPraia, Fixtures.arQuarto]
        private static let rateLimited = ThinQError.api(code: .exceededAPICalls, message: "")
        private static let offline = ThinQError.api(code: .notConnectedDevice, message: "")

        private static func makeHarness() throws -> StoreHarness {
            try StoreHarness(devices: account, state: Fixtures.realState(), profile: Fixtures.realProfile())
        }

        @Test func labelsFollowTheAccountAndTheSavedNicknames() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store

            await store.start()
            #expect(store.deviceLabels.map(\.fullName) == [
                "Ar-condicionado · RAC_0B0001_WW · …0001",
                "Ar-condicionado · RAC_056905_WW · …a3f2",
                "Ar Quarto",
            ])
            #expect(store.deviceLabel?.id == Fixtures.arCondicionadoSala.id)
            #expect(store.deviceLabel?.isAmbiguous == true)

            harness.settings.setNickname("Sala", for: Fixtures.arCondicionadoSala.id)

            #expect(store.deviceLabels.map(\.fullName) == ["Sala", "Ar-condicionado", "Ar Quarto"])
            #expect(store.deviceLabel?.name == "Sala")
        }

        @Test func theSelectedDeviceIsPreviewedFromItsSnapshotWithoutARequest() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            let stateCalls = await harness.api.stateCallCount

            let preview = await store.statePreview(for: Fixtures.arCondicionadoSala.id)

            #expect(preview == .reported(power: .on, roomTemperature: Measurement(value: 24, unit: .celsius)))
            #expect(await harness.api.stateCallCount == stateCalls)
        }

        @Test func anotherDeviceCostsOneGETAndLeavesTheSnapshotAlone() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            let snapshot = store.snapshot
            await harness.api.setState(.success(try Fixtures.offState()), forDevice: Fixtures.arCondicionadoPraia.id)

            let preview = await store.statePreview(for: Fixtures.arCondicionadoPraia.id)

            #expect(preview == .reported(power: .off, roomTemperature: Measurement(value: 27, unit: .celsius)))
            let calls = await harness.api.calls
            #expect(calls.filter { $0.call == .state(Fixtures.arCondicionadoPraia.id) }.count == 1)
            #expect(store.snapshot == snapshot)
            #expect(store.device == Fixtures.arCondicionadoSala)
            #expect(store.phase == .ready)
        }

        @Test func anOfflineDeviceReadsOfflineWithoutChangingThePhase() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setState(.failure(Self.offline), forDevice: Fixtures.arQuarto.id)

            let preview = await store.statePreview(for: Fixtures.arQuarto.id)

            #expect(preview == .offline)
            #expect(store.phase == .ready)
        }

        @Test func noRequestGoesOutInsideARateLimitWindow() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.enqueueState(.failure(Self.rateLimited))
            await store.refresh()
            guard case .rateLimited = store.phase else {
                Issue.record("expected .rateLimited, got \(store.phase)")
                return
            }
            let stateCalls = await harness.api.stateCallCount

            let preview = await store.statePreview(for: Fixtures.arQuarto.id)

            #expect(preview == .unavailable)
            #expect(await harness.api.stateCallCount == stateCalls)
        }

        @Test func aRateLimitedPreviewOpensTheBackOffForTheNextOne() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setState(.failure(Self.rateLimited), forDevice: Fixtures.arCondicionadoPraia.id)

            let first = await store.statePreview(for: Fixtures.arCondicionadoPraia.id)
            let stateCalls = await harness.api.stateCallCount
            let second = await store.statePreview(for: Fixtures.arQuarto.id)

            #expect(first == .unavailable)
            #expect(second == .unavailable)
            #expect(await harness.api.stateCallCount == stateCalls)
            guard case .rateLimited = store.phase else {
                Issue.record("expected .rateLimited, got \(store.phase)")
                return
            }
        }

        @Test func nothingIsFetchedBeforeTheStoreStarts() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }

            let preview = await harness.store.statePreview(for: Fixtures.arQuarto.id)

            #expect(preview == .unavailable)
            #expect(await harness.api.calls.isEmpty)
        }

        @Test func aDeviceSwitchDuringAPreviewKeepsItsAnswer() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setState(.success(try Fixtures.offState()), forDevice: Fixtures.arQuarto.id)
            await harness.api.holdStateRequests()
            let previewing = Task { await store.statePreview(for: Fixtures.arQuarto.id) }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })

            // A row's select button while the preview GET is out: the session changes.
            let selecting = Task { await store.selectDevice(id: Fixtures.arCondicionadoPraia.id) }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 2 })
            await harness.api.releaseHeldStateRequests()
            let preview = await previewing.value
            await selecting.value

            #expect(preview == .reported(power: .off, roomTemperature: Measurement(value: 27, unit: .celsius)))
            #expect(store.device == Fixtures.arCondicionadoPraia)
            #expect(store.phase == .ready)
        }

        @Test func aRateLimitLandingAfterADeviceSwitchOpensNoBackOff() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setState(.failure(Self.rateLimited), forDevice: Fixtures.arQuarto.id)
            await harness.api.holdStateRequests()
            let previewing = Task { await store.statePreview(for: Fixtures.arQuarto.id) }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 1 })

            let selecting = Task { await store.selectDevice(id: Fixtures.arCondicionadoPraia.id) }
            #expect(await waitUntil { await harness.api.heldStateRequestCount == 2 })
            await harness.api.releaseHeldStateRequests()
            let preview = await previewing.value
            await selecting.value
            let stateCalls = await harness.api.stateCallCount

            #expect(preview == .unavailable)
            #expect(store.phase == .ready)
            // The new session is not inside a back-off: the next preview still asks LG.
            _ = await store.statePreview(for: Fixtures.arCondicionadoSala.id)
            #expect(await harness.api.stateCallCount == stateCalls + 1)
        }

        @Test func switchingFromTheHeaderSelectsAndPersistsTheOtherDevice() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()

            await store.selectDevice(id: Fixtures.arCondicionadoPraia.id)

            #expect(store.device == Fixtures.arCondicionadoPraia)
            #expect(store.deviceLabel?.fullName == "Ar-condicionado · RAC_056905_WW · …a3f2")
            #expect(AppSettings(defaults: harness.defaults).selectedDeviceID == Fixtures.arCondicionadoPraia.id)
        }
    }

    @Suite("Device preview from a state")
    struct DevicePreviewParsing {
        @Test func theRealUnitReadsOnAtTheCelsiusRoomTemperature() throws {
            let preview = ACStore.DevicePreview(state: try Fixtures.realState())
            #expect(preview == .reported(power: .on, roomTemperature: Measurement(value: 24, unit: .celsius)))
        }

        @Test func theCelsiusEntryWinsOverAFirstFahrenheitOne() {
            let state = DeviceState(values: [
                "operation": ["airConOperationMode": "POWER_OFF"],
                "temperatureInUnits": [
                    ["currentTemperature": 80, "unit": "F"],
                    ["currentTemperature": 27, "unit": "C"],
                ],
            ])
            #expect(ACStore.DevicePreview(state: state) == .reported(power: .off, roomTemperature: Measurement(value: 27, unit: .celsius)))
        }

        @Test func aFahrenheitOnlyFlatStateKeepsItsUnit() {
            let state = DeviceState(values: [
                "operation": ["airConOperationMode": "POWER_ON"],
                "temperature": ["currentTemperature": 76, "unit": "F"],
            ])
            #expect(ACStore.DevicePreview(state: state) == .reported(power: .on, roomTemperature: Measurement(value: 76, unit: .fahrenheit)))
        }

        @Test func missingValuesReadAsOffWithoutATemperature() {
            #expect(ACStore.DevicePreview(state: DeviceState()) == .reported(power: .off, roomTemperature: nil))
        }
    }
}
