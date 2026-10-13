/// The v1 surface of `ThinQClient`, so the app's store can be tested with a double.
public protocol ThinQAPI: Sendable {
    func devices() async throws(ThinQError) -> [DeviceSummary]
    func profile(deviceID: String) async throws(ThinQError) -> DeviceProfile
    func state(deviceID: String) async throws(ThinQError) -> DeviceState
    func control(deviceID: String, body: JSONObject) async throws(ThinQError)
}
