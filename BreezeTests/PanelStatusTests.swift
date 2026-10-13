import Foundation
import Testing
@testable import Breeze

@Suite("PanelStatus")
struct PanelStatusTests {
    private let lastSync = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func setupHidesTheStatusEvenWhileSyncing() {
        #expect(PanelStatus(phase: .needsSetup, isSyncing: true, lastSync: nil, hasSnapshot: false) == .hidden)
    }

    @Test func syncingWinsOverThePhase() {
        #expect(PanelStatus(phase: .ready, isSyncing: true, lastSync: lastSync, hasSnapshot: true) == .syncing)
        #expect(PanelStatus(phase: .offline, isSyncing: true, lastSync: lastSync, hasSnapshot: true) == .syncing)
        #expect(PanelStatus(phase: .loadingProfile, isSyncing: true, lastSync: nil, hasSnapshot: false) == .syncing)
    }

    @Test func readyShowsTheLastSync() {
        #expect(PanelStatus(phase: .ready, isSyncing: false, lastSync: lastSync, hasSnapshot: true) == .synced(lastSync))
        #expect(PanelStatus(phase: .ready, isSyncing: false, lastSync: nil, hasSnapshot: true) == .hidden)
    }

    @Test func problemsAreReportedWhileTheControlsAreShown() {
        let until = lastSync.addingTimeInterval(240)
        #expect(PanelStatus(phase: .offline, isSyncing: false, lastSync: lastSync, hasSnapshot: true) == .offline)
        #expect(PanelStatus(phase: .rateLimited(until: until), isSyncing: false, lastSync: lastSync, hasSnapshot: true) == .rateLimited(until: until))
        #expect(PanelStatus(phase: .tokenInvalid, isSyncing: false, lastSync: lastSync, hasSnapshot: true) == .tokenInvalid)
        #expect(PanelStatus(phase: .error("Boom"), isSyncing: false, lastSync: lastSync, hasSnapshot: true) == .error("Boom"))
    }

    @Test func withoutControlsTheBodyShowsTheProblemSoTheFooterStaysQuiet() {
        #expect(PanelStatus(phase: .offline, isSyncing: false, lastSync: nil, hasSnapshot: false) == .hidden)
        #expect(PanelStatus(phase: .tokenInvalid, isSyncing: false, lastSync: nil, hasSnapshot: false) == .hidden)
        #expect(PanelStatus(phase: .error("Boom"), isSyncing: false, lastSync: nil, hasSnapshot: false) == .hidden)
    }
}
