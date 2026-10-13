import Foundation

/// What the panel footer says about the connection, derived from the store so
/// the rules are testable without a view.
nonisolated enum PanelStatus: Equatable, Sendable {
    /// Nothing to say: setup, first load, or the panel body already shows the problem.
    case hidden
    /// "Syncing…" with a rotating arrow.
    case syncing
    /// "Synced 12 s ago".
    case synced(Date)
    case offline
    case rateLimited(until: Date)
    /// "Token invalid — open Settings"; tapping it opens Settings.
    case tokenInvalid
    case error(String)

    /// - Parameter hasSnapshot: whether the panel shows the AC's controls. Without them the panel
    ///   body is a full-size message for the same phase, so the footer only reports syncing.
    init(phase: ACStore.Phase, isSyncing: Bool, lastSync: Date?, hasSnapshot: Bool) {
        if phase == .needsSetup {
            self = .hidden
        } else if isSyncing {
            self = .syncing
        } else if !hasSnapshot {
            self = .hidden
        } else {
            self = Self.status(for: phase, lastSync: lastSync)
        }
    }

    private static func status(for phase: ACStore.Phase, lastSync: Date?) -> PanelStatus {
        switch phase {
        case .needsSetup, .loadingProfile:
            .hidden
        case .ready:
            lastSync.map(PanelStatus.synced) ?? .hidden
        case .offline:
            .offline
        case .rateLimited(let until):
            .rateLimited(until: until)
        case .tokenInvalid:
            .tokenInvalid
        case .error(let message):
            .error(message)
        }
    }
}
