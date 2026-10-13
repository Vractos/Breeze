import Foundation

extension Duration {
    /// The duration in seconds, for `Date` arithmetic.
    nonisolated var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
