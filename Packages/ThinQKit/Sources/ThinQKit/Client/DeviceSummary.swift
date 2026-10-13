/// One entry of `GET devices`.
public struct DeviceSummary: Sendable, Hashable, Identifiable {
    public static let airConditionerType = "DEVICE_AIR_CONDITIONER"

    public var id: String
    /// e.g. `DEVICE_AIR_CONDITIONER`.
    public var deviceType: String
    public var modelName: String
    /// The user-visible name set in the ThinQ app.
    public var alias: String

    public var isAirConditioner: Bool {
        deviceType == Self.airConditionerType
    }

    public init(
        id: String,
        deviceType: String,
        modelName: String,
        alias: String
    ) {
        self.id = id
        self.deviceType = deviceType
        self.modelName = modelName
        self.alias = alias
    }

    /// Parses `{"deviceId", "deviceInfo": {"deviceType", "modelName", "alias"}}`.
    public init(json: JSONValue) throws(ThinQError) {
        guard let id = json["deviceId"]?.stringValue else {
            throw ThinQError.decoding(path: "devices[].deviceId", underlying: JSONShapeError("missing deviceId"))
        }
        let info = json["deviceInfo"]
        self.init(
            id: id,
            deviceType: info?["deviceType"]?.stringValue ?? "",
            modelName: info?["modelName"]?.stringValue ?? "",
            alias: info?["alias"]?.stringValue ?? ""
        )
    }
}
