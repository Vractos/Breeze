/// `POST client/certificate` result: the AWS IoT client certificate and the MQTT topics to
/// subscribe to. Secret-adjacent: never log `certificatePEM`.
public struct ClientCertificate: Sendable, Equatable {
    public var certificatePEM: String
    /// e.g. `["app/clients/<client-id>/push"]`.
    public var subscriptions: [String]

    public init(certificatePEM: String, subscriptions: [String]) {
        self.certificatePEM = certificatePEM
        self.subscriptions = subscriptions
    }

    /// Parses `{"resultCode", "result": {"certificatePem", "subscriptions"}}`.
    public init(json: JSONValue) throws(ThinQError) {
        guard let result = json["result"], let pem = result["certificatePem"]?.stringValue else {
            throw ThinQError.decoding(
                path: "client/certificate.result.certificatePem",
                underlying: JSONShapeError("missing certificatePem")
            )
        }
        let topics = result["subscriptions"]?.arrayValue?.compactMap(\.stringValue) ?? []
        self.init(certificatePEM: pem, subscriptions: topics)
    }
}
