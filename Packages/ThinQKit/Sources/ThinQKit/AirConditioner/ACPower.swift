/// `operation.airConOperationMode`.
public enum ACPower: String, Sendable, CaseIterable {
    case on = "POWER_ON"
    case off = "POWER_OFF"

    public var toggled: ACPower {
        self == .on ? .off : .on
    }
}
