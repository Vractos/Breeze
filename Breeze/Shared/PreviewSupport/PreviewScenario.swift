#if DEBUG
import Foundation
import ThinQKit

/// The store states the previews show.
enum PreviewScenario: CaseIterable {
    case ready
    case off
    case fanAuto
    case fanLevel3
    case sleepSet
    /// Ready, with energy use fetched (Settings › Energy).
    case energy
    case needsSetup
    case offline
    /// The saved AC is offline from the first load (no snapshot), with other ACs on the
    /// account: the panel offers the device switch above the message.
    case offlineAtLoad
    case tokenInvalid
    case loading

    var token: String? {
        self == .needsSetup ? nil : "preview-token"
    }

    var stateResults: [Result<DeviceState, ThinQError>] {
        switch self {
        case .ready, .energy, .needsSetup, .loading:
            [.success(PreviewFixtures.state(power: .on, powerSave: true))]
        case .off:
            [.success(PreviewFixtures.state(power: .off))]
        case .fanAuto:
            [.success(PreviewFixtures.state(power: .on, fan: .auto, swing: false, light: false))]
        case .fanLevel3:
            [.success(PreviewFixtures.state(power: .on, fan: .level(3)))]
        case .sleepSet:
            [.success(PreviewFixtures.state(power: .on, fan: .level(2), sleepMinutes: 80))]
        case .offline:
            // First load succeeds, the next poll finds the AC unplugged: the last state stays
            // visible, read-only, with "AC offline" in the footer.
            [
                .success(PreviewFixtures.state(power: .on, mode: .heat, target: 21, current: 18)),
                .failure(.api(code: .notConnectedDevice, message: "")),
            ]
        case .offlineAtLoad:
            [.failure(.api(code: .notConnectedDevice, message: ""))]
        case .tokenInvalid:
            [.failure(.api(code: .invalidToken, message: ""))]
        }
    }

    /// Brings a freshly made store into this scenario.
    @MainActor
    func prepare(_ store: ACStore) async {
        switch self {
        case .loading:
            return  // never started: stays in `.loadingProfile`
        case .offline:
            await store.start()
            await store.refresh()
        case .energy:
            await store.start()
            await store.refreshEnergy()
        case .ready, .off, .fanAuto, .fanLevel3, .sleepSet, .needsSetup, .offlineAtLoad, .tokenInvalid:
            await store.start()
        }
    }
}
#endif
