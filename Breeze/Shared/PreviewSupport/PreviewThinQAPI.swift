#if DEBUG
import Foundation
import ThinQKit

/// A canned `ThinQAPI` for previews: fixed devices and profile, scripted state answers (each
/// call takes the next one; the last one repeats), and control calls that always succeed.
actor PreviewThinQAPI: ThinQAPI {
    private var stateResults: [Result<DeviceState, ThinQError>]

    init(stateResults: [Result<DeviceState, ThinQError>]) {
        self.stateResults = stateResults
    }

    func devices() async throws(ThinQError) -> [DeviceSummary] {
        [PreviewFixtures.device, PreviewFixtures.bedroom]
    }

    func profile(deviceID: String) async throws(ThinQError) -> DeviceProfile {
        PreviewFixtures.profile
    }

    func state(deviceID: String) async throws(ThinQError) -> DeviceState {
        guard let next = stateResults.first else { throw .httpStatus(500) }
        if stateResults.count > 1 {
            stateResults.removeFirst()
        }
        return try next.get()
    }

    func control(deviceID: String, body: JSONObject) async throws(ThinQError) {}
}
#endif
