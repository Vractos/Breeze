import ThinQKit

extension ACStore {
    /// A command in the queue, with what `send(_:)` knew when the user issued it.
    nonisolated struct QueuedCommand: Sendable, Equatable {
        /// Tags the command's own entry in the optimistic list.
        let id: Int
        let command: ACCommand
        /// The mode in effect when the command was sent (the snapshot with every earlier command
        /// applied). The setpoint key depends on the mode, and reading the snapshot at POST time
        /// would pick up mode changes queued *after* this command and write the wrong key.
        let mode: ACMode?
        /// For `.targetTemperature` and `.sleepTimer`: the slot it writes, for coalescing.
        let setpointSlot: SetpointSlot?
    }
}
