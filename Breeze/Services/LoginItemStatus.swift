/// `SMAppService.Status`, mirrored so `LoginItem` can be tested without ServiceManagement.
nonisolated enum LoginItemStatus: Equatable, Sendable {
    case enabled
    /// Registered, but the user must allow it in System Settings › General › Login Items.
    case requiresApproval
    case notRegistered
    case notFound
}
