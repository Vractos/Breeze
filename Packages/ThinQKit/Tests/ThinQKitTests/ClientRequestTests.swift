import Foundation
import Testing
@testable import ThinQKit

@Suite("Client requests and headers")
struct ClientRequestTests {
    private static let deviceID = "eb8ce6a99e63beb7e2074409bc244f3fd6c534e40ca270b6895371f12b398660"

    private func header(_ request: URLRequest?, _ name: String) -> String? {
        request?.value(forHTTPHeaderField: name)
    }

    private func body(_ request: URLRequest?) throws -> JSONValue {
        try JSONValue(jsonData: #require(request?.httpBody))
    }

    @Test func getCarriesEveryCommonHeader() async throws {
        let transport = FakeTransport(.json(#"{"messageId":"m","timestamp":"t","response":[]}"#))
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.devices()

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString == "https://api-aic.lgthinq.com/devices")
        #expect(header(request, "Authorization") == "Bearer test-token-not-real")
        #expect(header(request, "x-country") == "BR")
        #expect(header(request, "x-client-id") == "11111111-2222-3333-4444-555555555555")
        #expect(header(request, "x-api-key") == "v6GFvkweNo7DK7yD3ylIZ9w52aKBU0eJ7wLXkSR3")
        #expect(header(request, "x-service-phase") == "OP")
        #expect(header(request, "x-message-id")?.count == 22)
        #expect(header(request, "x-conditional-control") == nil)
        #expect(header(request, "Content-Type") == nil)
        #expect(request?.httpBody == nil)
        #expect(request?.timeoutInterval == 15)
    }

    @Test func controlAddsConditionalControlAndJSONBody() async throws {
        let transport = FakeTransport()
        let client = ThinQClient(configuration: .test, transport: transport)
        try await client.control(deviceID: Self.deviceID, body: ["operation": ["airConOperationMode": "POWER_ON"]])

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://api-aic.lgthinq.com/devices/\(Self.deviceID)/control")
        #expect(header(request, "x-conditional-control") == "true")
        #expect(header(request, "Content-Type") == "application/json")
        #expect(try body(request) == ["operation": ["airConOperationMode": "POWER_ON"]])
    }

    @Test func conditionalControlOnlyOnControl() async throws {
        let transport = FakeTransport(.json(#"{"response":{"property":{}}}"#))
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.profile(deviceID: Self.deviceID)
        try await client.registerClient()
        try await client.subscribePush(deviceID: Self.deviceID)

        for request in await transport.requests {
            #expect(header(request, "x-conditional-control") == nil)
        }
    }

    @Test func freshMessageIDPerRequest() async throws {
        let transport = FakeTransport(.json(#"{"response":[]}"#))
        let client = ThinQClient(configuration: .test, transport: transport)
        _ = try await client.devices()
        _ = try await client.devices()
        let ids = await transport.requests.compactMap { $0.value(forHTTPHeaderField: "x-message-id") }
        #expect(ids.count == 2)
        #expect(ids[0] != ids[1])
    }

    @Test func usesRegionHostAndEscapesDeviceID() async throws {
        let configuration = ThinQConfiguration(accessToken: "t", countryCode: "DE", clientID: "c")
        let transport = FakeTransport(.json(#"{"response":{}}"#))
        let client = ThinQClient(configuration: configuration, transport: transport)
        _ = try await client.state(deviceID: "a/b")
        let url = await transport.lastRequest?.url?.absoluteString
        #expect(url == "https://api-eic.lgthinq.com/devices/a%2Fb/state")
    }

    @Test(arguments: ["", ".", ".."])
    func emptyOrDotSegmentPathComponentsAreRejected(deviceID: String) throws {
        let client = ThinQClient(configuration: .test, transport: FakeTransport())
        let error = try #require(throws: ThinQError.self) {
            try client.makeRequest(.get, ["devices", deviceID, "state"], body: nil, conditionalControl: false)
        }
        guard case .invalidArgument = error else {
            Issue.record("expected .invalidArgument, got \(error)")
            return
        }
    }

    @Test func rejectedPathNeverReachesTheTransport() async throws {
        let transport = FakeTransport()
        let client = ThinQClient(configuration: .test, transport: transport)
        let error = try await #require(throws: ThinQError.self) { try await client.state(deviceID: "") }
        guard case .invalidArgument = error else {
            Issue.record("expected .invalidArgument, got \(error)")
            return
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func slashQueryAndFragmentArePercentEncoded() throws {
        let client = ThinQClient(configuration: .test, transport: FakeTransport())
        for (deviceID, encoded) in [("a/b", "a%2Fb"), ("a?b", "a%3Fb"), ("a#b", "a%23b"), ("...", "...")] {
            let request = try client.makeRequest(.get, ["devices", deviceID, "state"], body: nil, conditionalControl: false)
            #expect(request.url?.absoluteString == "https://api-aic.lgthinq.com/devices/\(encoded)/state")
        }
    }

    @Test func emptyBodyResponsesDoNotFail() async throws {
        let transport = FakeTransport(Canned(status: 200, body: Data()))
        let client = ThinQClient(configuration: .test, transport: transport)
        try await client.control(deviceID: Self.deviceID, body: ["powerSave": ["powerSaveEnabled": true]])
        try await client.unsubscribePush(deviceID: Self.deviceID)
        try await client.unsubscribeEvents(deviceID: Self.deviceID)
        #expect(try await client.devices() == [])
    }

    // MARK: - MQTT setup REST

    @Test func registerAndUnregisterClientBodies() async throws {
        let transport = FakeTransport()
        let client = ThinQClient(configuration: .test, transport: transport)
        try await client.registerClient()
        try await client.unregisterClient()

        let requests = await transport.requests
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path() == "/client")
        #expect(try body(requests[0]) == ["type": "MQTT", "service-code": "SVC202", "device-type": "607", "allowExist": true])
        #expect(requests[1].httpMethod == "DELETE")
        #expect(requests[1].url?.path() == "/client")
        #expect(header(requests[1], "Content-Type") == "application/json")
        // As the official SDK sends it; the OpenAPI unregister schema has no device-type (VERIFY).
        #expect(try body(requests[1]) == ["type": "MQTT", "service-code": "SVC202", "device-type": "607"])
    }

    @Test func eventAndPushSubscriptions() async throws {
        let transport = FakeTransport()
        let client = ThinQClient(configuration: .test, transport: transport)
        try await client.subscribeEvents(deviceID: "dev", hours: 24)
        try await client.subscribePush(deviceID: "dev")
        try await client.unsubscribeEvents(deviceID: "dev")
        try await client.unsubscribePush(deviceID: "dev")

        let requests = await transport.requests
        #expect(requests.map { $0.httpMethod ?? "" } == ["POST", "POST", "DELETE", "DELETE"])
        #expect(requests.map { $0.url?.path() ?? "" } == [
            "/event/dev/subscribe", "/push/dev/subscribe", "/event/dev/unsubscribe", "/push/dev/unsubscribe",
        ])
        #expect(try body(requests[0]) == ["expire": ["unit": "HOUR", "timer": 24]])
        #expect(String(decoding: try #require(requests[0].httpBody), as: UTF8.self).contains(#""timer":24"#))
        #expect(requests[1].httpBody == nil)
    }

    @Test func routeParsesMQTTHost() async throws {
        let transport = FakeTransport(.json("""
            {"messageId":"m","timestamp":"t","response":{"apiServer":"https://api-aic.lgthinq.com",
             "mqttServer":"mqtts://a3phael99lf879-ats.iot.us-west-2.amazonaws.com:8883",
             "webSocketServer":"wss://a3phael99lf879-ats.iot.us-west-2.amazonaws.com:443/mqtt"}}
            """))
        let client = ThinQClient(configuration: .test, transport: transport)
        let route = try await client.route()
        #expect(route.mqttHost == "a3phael99lf879-ats.iot.us-west-2.amazonaws.com")
        #expect(route.mqttPort == 8883)
        #expect(route.apiServer == "https://api-aic.lgthinq.com")
        #expect(await transport.lastRequest?.url?.path() == "/route")
    }

    @Test func issueCertificateSendsCSRAndParsesResult() async throws {
        let transport = FakeTransport(.json("""
            {"response":{"resultCode":"0000","result":{"certificatePem":"-----BEGIN CERTIFICATE-----\\nMIIE\\n-----END CERTIFICATE-----\\n",
             "subscriptions":["app/clients/abc/push"]}}}
            """))
        let client = ThinQClient(configuration: .test, transport: transport)
        let certificate = try await client.issueCertificate(csrBody: "MIIBCSR")
        #expect(certificate.certificatePEM.hasPrefix("-----BEGIN CERTIFICATE-----"))
        #expect(certificate.subscriptions == ["app/clients/abc/push"])
        let request = await transport.lastRequest
        #expect(request?.url?.path() == "/client/certificate")
        #expect(try body(request) == ["service-code": "SVC202", "csr": "MIIBCSR"])
    }

    @Test func devicesParsesSummaries() async throws {
        let transport = FakeTransport(.json("""
            {"messageId":"m","timestamp":"t","response":[
              {"deviceId":"ac1","deviceInfo":{"deviceType":"DEVICE_AIR_CONDITIONER","modelName":"PAC_910604_WW","alias":"Bedroom","reportable":true}},
              {"deviceId":"w1","deviceInfo":{"deviceType":"DEVICE_WASHER","modelName":"F_V","alias":"Washer","groupId":"234"}}
            ]}
            """))
        let devices = try await ThinQClient(configuration: .test, transport: transport).devices()
        #expect(devices.count == 2)
        #expect(devices[0] == DeviceSummary(id: "ac1", deviceType: "DEVICE_AIR_CONDITIONER", modelName: "PAC_910604_WW", alias: "Bedroom"))
        #expect(devices[0].isAirConditioner)
        #expect(!devices[1].isAirConditioner)
    }

    @Test func transportFailureIsWrapped() async throws {
        let transport = FakeTransport(failure: URLError(.notConnectedToInternet))
        let client = ThinQClient(configuration: .test, transport: transport)
        let error = try await #require(throws: ThinQError.self) { try await client.devices() }
        guard case .transport(let underlying) = error else {
            Issue.record("expected .transport, got \(error)")
            return
        }
        #expect((underlying as? URLError)?.code == .notConnectedToInternet)
    }
}

private typealias Canned = FakeTransport.Canned
