import Foundation

/// `GET route`: where the API and MQTT brokers live for this account.
public struct RouteInfo: Sendable, Equatable {
    /// e.g. `https://api-aic.lgthinq.com`.
    public var apiServer: String?
    /// e.g. `mqtts://xxxx-ats.iot.us-west-2.amazonaws.com:8883`.
    public var mqttServer: String
    /// Advertised but unusable without AWS SigV4 signing.
    public var webSocketServer: String?

    public init(apiServer: String?, mqttServer: String, webSocketServer: String?) {
        self.apiServer = apiServer
        self.mqttServer = mqttServer
        self.webSocketServer = webSocketServer
    }

    public init(json: JSONValue) throws(ThinQError) {
        guard let mqttServer = json["mqttServer"]?.stringValue else {
            throw ThinQError.decoding(path: "route.mqttServer", underlying: JSONShapeError("missing mqttServer"))
        }
        self.init(
            apiServer: json["apiServer"]?.stringValue,
            mqttServer: mqttServer,
            webSocketServer: json["webSocketServer"]?.stringValue
        )
    }

    /// The broker hostname with the `mqtts://` scheme and `:8883` port stripped.
    public var mqttHost: String? {
        if let host = URL(string: mqttServer)?.host(), !host.isEmpty {
            return host
        }
        // No scheme: treat the whole string as host[:port].
        let host = mqttServer.split(separator: ":").first.map(String.init)
        return host?.isEmpty == false ? host : nil
    }

    /// The broker port, defaulting to 8883.
    public var mqttPort: Int {
        URL(string: mqttServer)?.port ?? 8883
    }
}
