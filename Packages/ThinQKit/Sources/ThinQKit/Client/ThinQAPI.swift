import Foundation

/// The v1 surface of `ThinQClient`, so the app's store can be tested with a double.
public protocol ThinQAPI: Sendable {
    func devices() async throws(ThinQError) -> [DeviceSummary]
    func profile(deviceID: String) async throws(ThinQError) -> DeviceProfile
    func state(deviceID: String) async throws(ThinQError) -> DeviceState
    func control(deviceID: String, body: JSONObject) async throws(ThinQError)
    func energyProperties(deviceID: String) async throws(ThinQError) -> [String]
    func energyUsage(
        deviceID: String,
        property: String,
        period: EnergyPeriod,
        from: DateComponents,
        to: DateComponents
    ) async throws(ThinQError) -> [EnergyUsageEntry]
}
