import ThinQKit

extension ACStore {
    /// A command applied on top of the fetched state until a fetch reconciles it. Tagged with an
    /// id so a failed POST removes exactly its own entry.
    nonisolated struct OptimisticCommand: Sendable, Equatable {
        let id: Int
        let command: ACCommand
        /// A `.power(.on)` that `send(_:)` added for display only: no POWER_ON has been POSTed
        /// for it yet, so the queue must not count it when deciding whether the AC is on.
        var isImplicitPowerOn: Bool
    }
}
