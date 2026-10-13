#if DEBUG
import Foundation
import ThinQKit

/// The store states the previews show.
enum PreviewScenario: CaseIterable {
    case ready
    case off
    case needsSetup
    case offline
    case tokenInvalid
    case loading

    var token: String? {
        self == .needsSetup ? nil : "preview-token"
    }

    var stateResults: [Result<DeviceState, ThinQError>] {
        switch self {
        case .ready, .needsSetup, .loading:
            [.success(PreviewFixtures.state(power: .on, powerSave: true))]
        case .off:
            [.success(PreviewFixtures.state(power: .off))]
        case .offline:
            // First load succeeds, the next poll finds the AC unplugged: the last state stays
            // visible, read-only, with "AC offline" in the footer.
            [
                .success(PreviewFixtures.state(power: .on, mode: .heat, target: 21, current: 18)),
                .failure(.api(code: .notConnectedDevice, message: "")),
            ]
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
        case .ready, .off, .needsSetup, .tokenInvalid:
            await store.start()
        }
    }
}
#endif
