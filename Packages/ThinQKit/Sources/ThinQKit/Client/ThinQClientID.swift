import Foundation

/// Generates the per-installation `x-client-id`. Generate once, persist, reuse forever: LG
/// throttles accounts that keep registering new client ids. The app keeps its id in
/// UserDefaults; the CLI keeps its own in Application Support (the sandbox prevents sharing).
public enum ThinQClientID {
    /// A fresh lowercase UUIDv4 string, the same format LG's Python SDK documents.
    public static func generate() -> String {
        UUID().uuidString.lowercased()
    }
}
