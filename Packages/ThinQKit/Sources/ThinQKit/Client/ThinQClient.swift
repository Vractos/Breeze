import Foundation
import os

/// REST client for LG ThinQ Connect. Stateless apart from its configuration, so it is a plain
/// `Sendable` struct usable from any isolation domain.
public struct ThinQClient: ThinQAPI {
    /// Public program key shared by every LG SDK; identifies ThinQ Connect, not the user.
    static let apiKey = "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3"
    static let servicePhase = "OP"
    /// Fixed values for MQTT client registration (as LG's official SDK sends them).
    static let serviceCode = "SVC202"
    static let clientDeviceType = "607"
    private static let clientRegistration: JSONObject = [
        "type": "MQTT",
        "service-code": .string(serviceCode),
        "device-type": .string(clientDeviceType),
    ]

    public let configuration: ThinQConfiguration
    private let transport: any ThinQTransport
    private let logger = Logger(subsystem: "com.vinicius.Breeze", category: "api")

    public init(configuration: ThinQConfiguration, transport: any ThinQTransport = URLSession.shared) {
        self.configuration = configuration
        self.transport = transport
    }

    // MARK: - v1

    public func devices() async throws(ThinQError) -> [DeviceSummary] {
        let response = try await send(.get, ["devices"])
        guard let response else { return [] }
        guard let items = response.arrayValue else {
            throw ThinQError.decoding(path: "devices", underlying: JSONShapeError("response is not an array"))
        }
        return try items.map(DeviceSummary.init(json:))
    }

    public func profile(deviceID: String) async throws(ThinQError) -> DeviceProfile {
        let response = try await send(.get, ["devices", deviceID, "profile"])
        return try DeviceProfile(json: response ?? .null)
    }

    public func state(deviceID: String) async throws(ThinQError) -> DeviceState {
        let response = try await send(.get, ["devices", deviceID, "state"])
        return try DeviceState(json: response ?? .null)
    }

    public func control(deviceID: String, body: JSONObject) async throws(ThinQError) {
        _ = try await send(.post, ["devices", deviceID, "control"], body: .object(body), conditionalControl: true)
    }

    // MARK: - REST side of MQTT setup

    public func route() async throws(ThinQError) -> RouteInfo {
        let response = try await send(.get, ["route"])
        return try RouteInfo(json: response ?? .null)
    }

    /// Registers this client id for MQTT. `allowExist` makes re-registration idempotent.
    public func registerClient() async throws(ThinQError) {
        var body = Self.clientRegistration
        body["allowExist"] = true
        _ = try await send(.post, ["client"], body: .object(body))
    }

    /// Body = the register body minus `allowExist`. The official SDK sends the
    /// full register body on DELETE, device-type included; the OpenAPI `client-unregister-req`
    /// schema lists only type and service-code. VERIFY which one LG accepts.
    public func unregisterClient() async throws(ThinQError) {
        _ = try await send(.delete, ["client"], body: .object(Self.clientRegistration))
    }

    /// - Parameter csrBody: the base64 body of a PEM CSR, without header, footer or newlines.
    public func issueCertificate(csrBody: String) async throws(ThinQError) -> ClientCertificate {
        let body: JSONValue = [
            "service-code": .string(Self.serviceCode),
            "csr": .string(csrBody),
        ]
        let response = try await send(.post, ["client", "certificate"], body: body)
        return try ClientCertificate(json: response ?? .null)
    }

    /// - Parameter hours: subscription lifetime. The spec says 1…24; the SDK sends 4464
    ///   (VERIFY). Not clamped here so both can be tried.
    public func subscribeEvents(deviceID: String, hours: Int) async throws(ThinQError) {
        let body: JSONValue = ["expire": ["unit": "HOUR", "timer": .number(Double(hours))]]
        _ = try await send(.post, ["event", deviceID, "subscribe"], body: body)
    }

    /// `1207 ALREADY_SUBSCRIBED_PUSH` is benign; callers decide whether to ignore it.
    public func subscribePush(deviceID: String) async throws(ThinQError) {
        _ = try await send(.post, ["push", deviceID, "subscribe"])
    }

    public func unsubscribeEvents(deviceID: String) async throws(ThinQError) {
        _ = try await send(.delete, ["event", deviceID, "unsubscribe"])
    }

    public func unsubscribePush(deviceID: String) async throws(ThinQError) {
        _ = try await send(.delete, ["push", deviceID, "unsubscribe"])
    }

    // MARK: - Plumbing

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case delete = "DELETE"
    }

    /// Builds the request with the headers LG requires on every call. A fresh message id per call.
    func makeRequest(
        _ method: Method,
        _ pathComponents: [String],
        body: JSONValue?,
        conditionalControl: Bool
    ) throws(ThinQError) -> URLRequest {
        // appending(component:) percent-encodes "/", "?" and "#" in each segment, but it drops
        // empty components and passes "." / ".." through, which servers resolve to another
        // endpoint (`devices//state` → `devices/state`, `devices/../state` → `/state`).
        for component in pathComponents where component.isEmpty || component == "." || component == ".." {
            throw ThinQError.invalidArgument("path component '\(component)' is empty or a dot-segment")
        }
        let url = pathComponents.reduce(configuration.region.baseURL) { url, component in
            url.appending(component: component, directoryHint: .notDirectory)
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.countryCode, forHTTPHeaderField: "x-country")
        request.setValue(ThinQMessageID.make(), forHTTPHeaderField: "x-message-id")
        request.setValue(configuration.clientID, forHTTPHeaderField: "x-client-id")
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.servicePhase, forHTTPHeaderField: "x-service-phase")
        if conditionalControl {
            request.setValue("true", forHTTPHeaderField: "x-conditional-control")
        }
        if let body {
            request.httpBody = try body.jsonData()
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(
        _ method: Method,
        _ pathComponents: [String],
        body: JSONValue? = nil,
        conditionalControl: Bool = false
    ) async throws(ThinQError) -> JSONValue? {
        let path = pathComponents.joined(separator: "/")
        let request = try makeRequest(method, pathComponents, body: body, conditionalControl: conditionalControl)
        let clock = ContinuousClock()
        let start = clock.now

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            let elapsed = Int((clock.now - start) / .milliseconds(1))
            logger.debug(
                "\(method.rawValue, privacy: .public) \(path, privacy: .public) failed after \(elapsed, privacy: .public) ms: \(error.localizedDescription, privacy: .public)"
            )
            throw ThinQError.transport(underlying: error)
        }

        let elapsed = Int((clock.now - start) / .milliseconds(1))
        // Never log headers or the request: the Authorization header carries the PAT.
        logger.debug(
            "\(method.rawValue, privacy: .public) \(path, privacy: .public) → \(response.statusCode, privacy: .public) in \(elapsed, privacy: .public) ms"
        )
        return try ThinQEnvelope.decode(data: data, status: response.statusCode, path: path)
    }
}
