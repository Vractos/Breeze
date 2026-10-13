import Foundation

extension ACStore {
    /// What the UI should show. Views never see raw errors, only this.
    nonisolated enum Phase: Equatable, Sendable {
        /// No token saved yet: show the "Set up Breeze" view.
        case needsSetup
        /// Fetching devices, profile and first state.
        case loadingProfile
        case ready
        /// LG says the AC is not connected (1222). The last state stays visible, greyed out.
        case offline
        /// Quota exceeded (1306). Polling resumes at `until`.
        case rateLimited(until: Date)
        /// The PAT was rejected (1103 / 1218 / 1302). Polling is stopped until `reconfigure()`.
        case tokenInvalid
        /// Anything else, with a localized message for the user.
        case error(String)
    }
}
