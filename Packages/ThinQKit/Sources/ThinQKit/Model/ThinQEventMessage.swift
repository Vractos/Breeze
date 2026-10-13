import Foundation

/// A pushed event (MQTT payload). Accepts both the spec's wrapped form
/// `{"messageId", "timestamp", "event": {...}}` and the flat form the SDKs receive over MQTT
/// `{"deviceId", "deviceType", "pushType", "report"}`.
public struct ThinQEventMessage: Sendable, Equatable {
    public static let deviceStatusPushType = "DEVICE_STATUS"

    public var deviceID: String
    public var deviceType: String?
    /// `DEVICE_STATUS`, `DEVICE_PUSH`, device added/removed/renamed, …
    public var pushType: String?
    /// Partial state tree; present for `DEVICE_STATUS`.
    public var report: JSONObject?

    public init(deviceID: String, deviceType: String?, pushType: String?, report: JSONObject?) {
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.pushType = pushType
        self.report = report
    }

    public init(json: JSONValue) throws(ThinQError) {
        let event = json["event"]?.objectValue != nil ? json["event"] : json
        guard let event, let deviceID = event["deviceId"]?.stringValue else {
            throw ThinQError.decoding(path: "event.deviceId", underlying: JSONShapeError("missing deviceId"))
        }
        self.init(
            deviceID: deviceID,
            deviceType: event["deviceType"]?.stringValue,
            pushType: event["pushType"]?.stringValue,
            report: event["report"]?.objectValue
        )
    }

    public init(data: Data) throws(ThinQError) {
        try self.init(json: JSONValue(jsonData: data))
    }

    /// The state delta to merge, when this is a status report.
    public var statusDelta: JSONObject? {
        guard pushType == nil || pushType == Self.deviceStatusPushType else { return nil }
        return report
    }
}
