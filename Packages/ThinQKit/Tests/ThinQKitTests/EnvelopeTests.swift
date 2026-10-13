import Foundation
import Testing
@testable import ThinQKit

@Suite("Envelope and error decoding")
struct EnvelopeTests {
    private func decode(_ text: String, status: Int = 200) -> Result<JSONValue?, ThinQError> {
        do {
            return .success(try ThinQEnvelope.decode(data: Data(text.utf8), status: status, path: "test"))
        } catch {
            return .failure(error)
        }
    }

    @Test func successReturnsResponsePayload() throws {
        let result = decode(#"{"messageId":"fNvdZ1brTn-wWKUlWGoSVw","timestamp":"2024-09-01T06:23:20.866279","response":{"a":1}}"#)
        #expect(try result.get() == ["a": 1])
    }

    @Test(arguments: ["", "  \n", "{}", #"{"messageId":"m","timestamp":"t"}"#, #"{"response":null}"#])
    func emptyOrMissingResponseIsNil(body: String) throws {
        #expect(try decode(body).get() == nil)
    }

    @Test func errorBodyMapsToAPIError() {
        let result = decode(#"{"error":{"code":"1222","message":"Not connected device"}}"#, status: 400)
        guard case .failure(.api(let code, let message)) = result else {
            Issue.record("expected .api, got \(result)")
            return
        }
        #expect(code == .notConnectedDevice)
        #expect(message == "Not connected device")
    }

    @Test func unknownCodeIsPreserved() {
        let result = decode(#"{"error":{"code":"9999","message":"?"}}"#, status: 400)
        guard case .failure(.api(let code, _)) = result else {
            Issue.record("expected .api, got \(result)")
            return
        }
        #expect(code == .unknown("9999"))
        #expect(code.rawValue == "9999")
        #expect(code.name == "UNKNOWN")
    }

    @Test func numericCodeIsTolerated() {
        let result = decode(#"{"error":{"code":1306}}"#, status: 429)
        guard case .failure(let error) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(error.isRateLimited)
    }

    @Test(arguments: [
        (#"{"error":{"code":1e30,"message":"x"}}"#, "1e+30"),
        (#"{"error":{"code":1e300}}"#, "1e+300"),
        (#"{"error":{"code":1103.7,"message":"x"}}"#, "1103.7"),
        (#"{"error":{"code":12.5}}"#, "12.5"),
    ])
    func hugeOrFractionalNumericCodeIsUnknownNotATrap(body: String, expectedCode: String) {
        // Int(Double) used to trap on 1e30 and truncate 1103.7 to 1103 (INVALID_TOKEN).
        let result = decode(body, status: 400)
        guard case .failure(.api(let code, _)) = result else {
            Issue.record("expected .api, got \(result)")
            return
        }
        #expect(code == .unknown(expectedCode))
        #expect(code != .invalidToken)
    }

    @Test(arguments: [(500, ""), (502, "<html>Bad gateway</html>"), (404, "{}"), (401, #"{"message":"nope"}"#)])
    func nonSuccessWithoutErrorBodyIsHTTPStatus(status: Int, body: String) {
        let result = decode(body, status: status)
        guard case .failure(.httpStatus(let reported)) = result else {
            Issue.record("expected .httpStatus, got \(result)")
            return
        }
        #expect(reported == status)
    }

    @Test func malformedSuccessBodyIsDecodingError() {
        let result = decode("not json", status: 200)
        guard case .failure(.decoding(let path, _)) = result else {
            Issue.record("expected .decoding, got \(result)")
            return
        }
        #expect(path == "test")
    }

    @Test func clientSurfacesAPIErrors() async throws {
        let transport = FakeTransport(.json(#"{"error":{"code":"1103","message":"Invalid token"}}"#, status: 401))
        let client = ThinQClient(configuration: .test, transport: transport)
        let error = try await #require(throws: ThinQError.self) { try await client.devices() }
        #expect(error.isTokenInvalid)
        #expect(error.apiCode == .invalidToken)
    }

    @Test func wrongShapeIsDecodingError() async throws {
        let transport = FakeTransport(.json(#"{"response":{"not":"an array"}}"#))
        let client = ThinQClient(configuration: .test, transport: transport)
        let error = try await #require(throws: ThinQError.self) { try await client.devices() }
        guard case .decoding(let path, _) = error else {
            Issue.record("expected .decoding, got \(error)")
            return
        }
        #expect(path == "devices")
    }
}
