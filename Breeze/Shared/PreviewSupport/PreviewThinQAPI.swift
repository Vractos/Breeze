#if DEBUG
import Foundation
import ThinQKit

/// A canned `ThinQAPI` for previews: fixed devices and profile, scripted state answers for the
/// controlled AC (each call takes the next one; the last one repeats) and fixed ones for the
/// others, control calls that always succeed, and canned energy use (`PreviewEnergy`).
actor PreviewThinQAPI: ThinQAPI {
    private var stateResults: [Result<DeviceState, ThinQError>]

    init(stateResults: [Result<DeviceState, ThinQError>]) {
        self.stateResults = stateResults
    }

    func devices() async throws(ThinQError) -> [DeviceSummary] {
        PreviewFixtures.devices
    }

    func profile(deviceID: String) async throws(ThinQError) -> DeviceProfile {
        PreviewFixtures.profile
    }

    func state(deviceID: String) async throws(ThinQError) -> DeviceState {
        if let other = PreviewFixtures.otherDeviceStates[deviceID] {
            return other
        }
        guard let next = stateResults.first else { throw .httpStatus(500) }
        if stateResults.count > 1 {
            stateResults.removeFirst()
        }
        return try next.get()
    }

    func control(deviceID: String, body: JSONObject) async throws(ThinQError) {}

    func energyProperties(deviceID: String) async throws(ThinQError) -> [String] {
        PreviewEnergy.properties
    }

    func energyUsage(
        deviceID: String,
        property: String,
        period: EnergyPeriod,
        from: DateComponents,
        to: DateComponents
    ) async throws(ThinQError) -> [EnergyUsageEntry] {
        PreviewEnergy.usage(period: period, from: from, to: to)
    }
}
#endif
