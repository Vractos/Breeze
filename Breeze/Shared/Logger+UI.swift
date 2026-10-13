import os

extension Logger {
    /// Views and view helpers log here. Never log the token.
    nonisolated static let ui = Logger(subsystem: "com.vinicius.Breeze", category: "ui")
}
