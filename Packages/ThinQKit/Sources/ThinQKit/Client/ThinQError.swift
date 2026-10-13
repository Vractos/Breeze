import Foundation

/// Every failure that can cross the ThinQKit API boundary.
public enum ThinQError: Error, Sendable, CustomStringConvertible {
    /// LG answered with `{"error": {"code", "message"}}`.
    case api(code: ThinQErrorCode, message: String)
    /// The request never produced an HTTP response (offline, DNS, TLS, timeout, cancellation).
    case transport(underlying: any Error)
    /// The response (or a fixture) did not have the expected shape. `path` names the endpoint or
    /// the JSON location that failed.
    case decoding(path: String, underlying: any Error)
    /// A non-2xx status without a parseable LG error body.
    case httpStatus(Int)
    /// A request body could not be serialised. JSONEncoder is a throwing API
    /// and this keeps that failure honest instead of mislabelling it as `.decoding`.
    case encoding(underlying: any Error)
    /// A caller-supplied value cannot be sent, e.g. an empty or `..` device id that would
    /// address a different endpoint.
    case invalidArgument(String)

    /// `1103`, `1218`, `1302`: ask the user for a new token.
    public var isTokenInvalid: Bool {
        apiCode.map { [.invalidToken, .invalidTokenAgain, .notFoundToken].contains($0) } ?? false
    }

    /// `1306`: hourly quota exceeded; back off.
    public var isRateLimited: Bool {
        apiCode == .exceededAPICalls
    }

    /// `1222`: the AC is unplugged or its Wi-Fi is down.
    public var isDeviceOffline: Bool {
        apiCode == .notConnectedDevice
    }

    /// The LG error code, when this is an `.api` error.
    public var apiCode: ThinQErrorCode? {
        if case .api(let code, _) = self { return code }
        return nil
    }

    public var description: String {
        switch self {
        case .api(let code, let message):
            message.isEmpty ? "LG API error \(code)" : "LG API error \(code): \(message)"
        case .transport(let underlying):
            "Network error: \(underlying.localizedDescription)"
        case .decoding(let path, let underlying):
            "Unexpected response shape at \(path): \(underlying)"
        case .httpStatus(let status):
            "HTTP \(status) without an LG error body"
        case .encoding(let underlying):
            "Could not encode request body: \(underlying)"
        case .invalidArgument(let message):
            "Invalid argument: \(message)"
        }
    }
}
