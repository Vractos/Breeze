import Foundation
@testable import ThinQKit

/// Records every request and answers with canned responses, in order (the last one repeats).
actor FakeTransport: ThinQTransport {
    struct Canned: Sendable {
        var status: Int
        var body: Data

        static func json(_ text: String, status: Int = 200) -> Canned {
            Canned(status: status, body: Data(text.utf8))
        }

        static let emptyOK = Canned.json(#"{"messageId":"x","timestamp":"t","response":{}}"#)
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Canned]
    private let failure: URLError?

    init(_ responses: Canned..., failure: URLError? = nil) {
        self.responses = responses.isEmpty ? [.emptyOK] : responses
        self.failure = failure
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        let canned = responses.count > 1 ? responses.removeFirst() : responses[0]
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let response = HTTPURLResponse(url: url, statusCode: canned.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (canned.body, response)
    }

    var lastRequest: URLRequest? { requests.last }
}

extension ThinQConfiguration {
    static let test = ThinQConfiguration(
        accessToken: "test-token-not-real",
        countryCode: "BR",
        clientID: "11111111-2222-3333-4444-555555555555"
    )
}
