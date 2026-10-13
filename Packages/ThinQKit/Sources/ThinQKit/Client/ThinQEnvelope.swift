import Foundation

/// Decodes LG's response envelope:
/// success `{"messageId", "timestamp", "response": <payload>}`,
/// failure `{"error": {"code": "1222", "message": "…"}}` with a non-2xx status.
enum ThinQEnvelope {
    /// Returns the `response` payload, or `nil` when the body is empty or has no `response`
    /// (several endpoints answer `{}` or nothing at all on success).
    static func decode(data: Data, status: Int, path: String) throws(ThinQError) -> JSONValue? {
        let isSuccess = (200..<300).contains(status)
        let body: JSONValue
        do {
            body = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            guard isSuccess else { throw .httpStatus(status) }
            if isBlank(data) { return nil }
            throw .decoding(path: path, underlying: error)
        }
        if let error = apiError(in: body) { throw error }
        guard isSuccess else { throw .httpStatus(status) }
        if case .null? = body["response"] { return nil }
        return body["response"]
    }

    private static func apiError(in body: JSONValue) -> ThinQError? {
        guard let error = body["error"]?.objectValue else {
            return nil
        }
        // Codes are strings per spec; tolerate a bare number in case a proxy rewrites it.
        let code: String
        if let text = error["code"]?.stringValue {
            code = text
        } else if let number = error["code"]?.doubleValue {
            // Int(Double) traps outside Int's range (e.g. 1e300) and truncates 1103.7 to 1103
            // (INVALID_TOKEN); never trap on network input. Non-integral or huge codes keep their
            // decimal spelling and become `.unknown`.
            if let integral = Int(exactly: number) {
                code = String(integral)
            } else {
                code = String(describing: number)
            }
        } else {
            return nil
        }
        let message = error["message"]?.stringValue ?? ""
        return .api(code: ThinQErrorCode(rawValue: code), message: message)
    }

    private static func isBlank(_ data: Data) -> Bool {
        data.allSatisfy { byte in
            byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
        }
    }
}
