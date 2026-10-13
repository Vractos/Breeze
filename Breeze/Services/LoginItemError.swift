import Foundation

/// Registering or unregistering the login item failed. Carries the system's message.
nonisolated enum LoginItemError: Error, Equatable, Sendable {
    case registrationFailed(String)
    case unregistrationFailed(String)

    /// Text the Settings view can show.
    var message: LocalizedStringResource {
        switch self {
        case .registrationFailed(let reason):
            "Breeze couldn't be added to your login items: \(reason)"
        case .unregistrationFailed(let reason):
            "Breeze couldn't be removed from your login items: \(reason)"
        }
    }
}
