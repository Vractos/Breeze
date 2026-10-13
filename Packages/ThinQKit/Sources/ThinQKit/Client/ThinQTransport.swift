import Foundation

/// The single HTTP primitive `ThinQClient` needs. Tests inject canned responses through it.
public protocol ThinQTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

// Gotcha: this adds a `data(for:)` overload to URLSession that differs from Foundation's
// `data(for:delegate:)` only by return type (HTTPURLResponse vs URLResponse). Call sites outside
// ThinQKit that destructure without type context could become ambiguous; annotate the response
// type there if that ever happens. The app should never call URLSession directly anyway.
extension URLSession: ThinQTransport {
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request, delegate: nil)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}
