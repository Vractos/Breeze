/// `sleepTimer` as the state reports it.
public enum SleepTimerState: Sendable, Equatable {
    case off
    /// Running. `remaining` counts down and is `nil` when the state omits it.
    case set(remaining: Duration?)
}
