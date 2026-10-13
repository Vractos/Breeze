import Foundation

/// `x-message-id`: URL-safe base64 of the 16 raw bytes of a UUIDv4, padding stripped → 22 chars.
enum ThinQMessageID {
    static func make() -> String {
        let bytes = withUnsafeBytes(of: UUID().uuid) { Data($0) }
        return bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
