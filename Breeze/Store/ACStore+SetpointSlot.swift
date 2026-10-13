import ThinQKit

extension ACStore {
    /// The setpoint a `.targetTemperature` writes: the property key and the mode it was sent in.
    /// A queued setpoint is superseded only by a later one for the same slot. With the generic
    /// `targetTemperature` key the mode still matters: a value sent in COOL must reach the AC
    /// even when a later value is sent after switching to HEAT.
    nonisolated struct SetpointSlot: Hashable, Sendable {
        let key: String
        let mode: ACMode?
    }
}
