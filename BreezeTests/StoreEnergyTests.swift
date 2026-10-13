import Foundation
import Observation
import Synchronization
import Testing
@testable import Breeze
import ThinQKit

extension StoreTests {
    /// Energy is fetched only when Settings › Energy appears (at most once
    /// an hour), never at launch, in the poll loop or inside a 1306 back-off, and its failures
    /// never change `phase`.
    @Suite("ACStore energy")
    @MainActor
    struct Energy {
        private static let device = Fixtures.arCondicionadoSala
        private static let rateLimited = ThinQError.api(code: .exceededAPICalls, message: "")

        private static func makeHarness() throws -> StoreHarness {
            try StoreHarness(
                devices: [device, Fixtures.arQuarto],
                state: Fixtures.realState(),
                profile: Fixtures.realProfile()
            )
        }

        @Test func launchAndPollingNeverFetchEnergy() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }

            await harness.store.start()
            await harness.clock.advance(by: .seconds(3 * 3600))

            #expect(await harness.api.stateCallCount > 1)
            #expect(await harness.api.energyCalls.isEmpty)
            #expect(harness.store.energy == nil)
        }

        @Test func theTabFetchesTheProfileThenTwelveMonthsAndThirtyDays() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            let now = harness.clock.now
            let months = EnergySummary.monthRange(endingAt: now, calendar: harness.calendar)
            let days = EnergySummary.dayRange(endingAt: now, calendar: harness.calendar)

            await store.energyTabDidAppear()

            #expect(await harness.api.energyCalls == [
                .energyProperties(Self.device.id),
                .energyUsage(Self.device.id, property: "energyUsage", period: .monthly, from: months.from, to: months.to),
                .energyUsage(Self.device.id, property: "energyUsage", period: .daily, from: days.from, to: days.to),
            ])
            let energy = try #require(store.energy)
            #expect(energy.fetchedAt == now)
            #expect(energy.months.count == 12)
            #expect(energy.days.count == 30)
            #expect(energy.thisMonth == Measurement(value: 13.831, unit: .kilowattHours))
            #expect(energy.days.contains { $0.energy.value == 0 })
            #expect(!store.isLoadingEnergy)
            #expect(store.energyFailureMessage == nil)
            #expect(store.phase == .ready)
        }

        @Test func theTabFetchesAgainOnlyAfterAnHourWithoutTheProfile() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await store.energyTabDidAppear()

            await harness.clock.advance(by: .seconds(3599))
            await store.energyTabDidAppear()
            #expect(await harness.api.energyCalls.count == 3)

            await harness.clock.advance(by: .seconds(1))
            await store.energyTabDidAppear()
            let calls = await harness.api.energyCalls
            #expect(calls.count == 5)
            #expect(!calls.dropFirst(3).contains(.energyProperties(Self.device.id)))
        }

        @Test func aNewDayFetchesAgainWithinTheHour() async throws {
            // 23:40 at the first fetch, 00:20 at the next appearance: "Today" would be yesterday's.
            // Every ManualClock starts at the same instant.
            let harness = try StoreHarness(
                devices: [Self.device],
                state: Fixtures.realState(),
                profile: Fixtures.realProfile(),
                calendar: Self.calendar(placing: ManualClock().now, atHour: 23, minute: 40)
            ) { $0.pollIntervalSeconds = 600 }
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            #expect(harness.calendar.component(.hour, from: harness.clock.now) == 23)
            await store.energyTabDidAppear()

            await harness.clock.advance(by: .seconds(40 * 60))
            await store.energyTabDidAppear()

            #expect(await harness.api.energyCalls.count == 5)
            let energy = try #require(store.energy)
            #expect(harness.calendar.isDate(energy.fetchedAt, inSameDayAs: harness.clock.now))
        }

        @Test func refreshIgnoresTheHourGate() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await store.energyTabDidAppear()

            await store.refreshEnergy()

            #expect(await harness.api.energyCalls.count == 5)
        }

        @Test func concurrentFetchesShareOneSetOfRequests() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()

            async let first: Void = store.energyTabDidAppear()
            async let second: Void = store.refreshEnergy()
            _ = await (first, second)

            #expect(await harness.api.energyCalls.count == 3)
        }

        @Test func nothingIsFetchedBeforeTheStoreStarts() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }

            await harness.store.energyTabDidAppear()

            #expect(await harness.api.calls.isEmpty)
            #expect(!harness.store.canRefreshEnergy)
        }

        @Test func nothingIsFetchedInsideARateLimitWindow() async throws {
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

            await store.energyTabDidAppear()
            await store.refreshEnergy()

            #expect(await harness.api.energyCalls.isEmpty)
            #expect(!store.canRefreshEnergy)
        }

        @Test func refreshAvailabilityIsObservedWhenABackOffOpens() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            #expect(store.canRefreshEnergy)
            let changed = ChangeFlag()
            withObservationTracking {
                _ = store.canRefreshEnergy
            } onChange: {
                changed.fire()
            }

            await harness.api.enqueueState(.failure(Self.rateLimited))
            await store.refresh()

            // The Energy tab's Refresh button re-renders: it reads only `canRefreshEnergy`.
            #expect(changed.didFire)
            #expect(!store.canRefreshEnergy)
        }

        @Test func anEmptyEnergyProfileIsRememberedAsUnsupported() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setEnergyProperties(.success([]))

            await store.energyTabDidAppear()
            #expect(store.isEnergyUnsupported)
            #expect(store.energy == nil)
            #expect(store.energyFailureMessage == nil)

            await harness.clock.advance(by: .seconds(2 * 3600))
            await store.energyTabDidAppear()
            await store.refreshEnergy()

            #expect(await harness.api.energyCalls == [.energyProperties(Self.device.id)])
            #expect(!store.canRefreshEnergy)
            #expect(store.phase == .ready)
        }

        @Test(arguments: [ThinQErrorCode.notSupportedFeature, .notSupportedProduct, .notSupportedCountry])
        func unsupportedCodesMarkTheDeviceWithoutChangingThePhase(code: ThinQErrorCode) async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setEnergyUsage(.failure(.api(code: code, message: "")), for: .monthly)

            await store.energyTabDidAppear()

            #expect(store.isEnergyUnsupported)
            #expect(store.energyFailureMessage == nil)
            #expect(store.phase == .ready)
        }

        @Test func unsupportedIsPerDevice() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setEnergyProperties(.success([]))
            await store.energyTabDidAppear()
            #expect(store.isEnergyUnsupported)

            await harness.api.setEnergyProperties(.success(["energyUsage"]))
            await store.selectDevice(id: Fixtures.arQuarto.id)
            #expect(!store.isEnergyUnsupported)
            await store.energyTabDidAppear()

            #expect(store.energy != nil)
            #expect(store.energyUnsupportedDeviceIDs == [Self.device.id])
        }

        @Test func aRateLimitedEnergyFetchOnlySetsAMessage() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setEnergyUsage(.failure(Self.rateLimited), for: .daily)

            await store.energyTabDidAppear()

            #expect(store.phase == .ready)
            #expect(store.energy == nil)
            #expect(store.energyFailureMessage != nil)
            #expect(!store.isEnergyUnsupported)
            #expect(store.canRefreshEnergy)
        }

        @Test func aFailedRefreshKeepsTheLastSummaryAndASuccessClearsTheMessage() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await store.energyTabDidAppear()
            let summary = store.energy

            await harness.api.setEnergyUsage(.failure(.httpStatus(500)), for: .monthly)
            await store.refreshEnergy()
            #expect(store.energy == summary)
            #expect(store.energyFailureMessage != nil)
            #expect(store.phase == .ready)

            await harness.api.setEnergyUsage(nil, for: .monthly)
            await store.refreshEnergy()
            #expect(store.energyFailureMessage == nil)
        }

        @Test func aFailureAlsoWaitsAnHourBeforeTheTabAsksAgain() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await harness.api.setEnergyUsage(.failure(.httpStatus(500)), for: .monthly)

            await store.energyTabDidAppear()
            await store.energyTabDidAppear()

            #expect(await harness.api.energyCalls.count == 2)
        }

        @Test func aStopBeforeTheFetchStartsSendsNothingAndLeavesNoSpinner() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()

            // `refreshEnergy` creates its fetch task, then a stop() runs before that task starts.
            let refreshing = Task { await store.refreshEnergy() }
            await Task.yield()
            store.stop()
            await refreshing.value
            await settle()

            #expect(!store.isLoadingEnergy)
            #expect(await harness.api.energyCalls.isEmpty)
        }

        @Test func switchingDevicesDropsTheSummary() async throws {
            let harness = try Self.makeHarness()
            defer { harness.tearDown() }
            let store = harness.store
            await store.start()
            await store.energyTabDidAppear()
            #expect(store.energy != nil)

            await store.selectDevice(id: Fixtures.arQuarto.id)
            #expect(store.energy == nil)

            // The new device is fetched right away, not an hour later.
            await store.energyTabDidAppear()
            #expect(await harness.api.energyCalls.contains(.energyProperties(Fixtures.arQuarto.id)))
            #expect(store.energy != nil)
        }

        /// A Gregorian calendar whose fixed time zone puts `date` at `hour`:`minute` (give or
        /// take the seconds) local time.
        private static func calendar(placing date: Date, atHour hour: Int, minute: Int) -> Calendar {
            // The reference date is midnight UTC, so this is the UTC time of day in minutes.
            let utcMinutes = Int(date.timeIntervalSinceReferenceDate / 60) % (24 * 60)
            var offset = (hour * 60 + minute - utcMinutes) % (24 * 60)
            if offset > 12 * 60 { offset -= 24 * 60 } else if offset < -12 * 60 { offset += 24 * 60 }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: offset * 60) ?? .gmt
            return calendar
        }
    }
}

/// Set from an observation `onChange`, which may run on any thread.
private final class ChangeFlag: Sendable {
    private let fired = Mutex(false)

    var didFire: Bool { fired.withLock { $0 } }

    func fire() {
        fired.withLock { $0 = true }
    }
}
