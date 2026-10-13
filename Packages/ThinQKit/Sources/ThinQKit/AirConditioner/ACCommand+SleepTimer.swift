/// `.sleepTimer(minutes:)` bodies, as probed on a real unit. Its payload and state delta differ, so it has its own builders like the setpoint.
extension ACCommand {
    static let sleepTimerResource = "sleepTimer"
    static let sleepHourKey = "relativeHourToStop"
    static let sleepMinuteKey = "relativeMinuteToStop"
    static let sleepStatusKey = "relativeStopTimer"

    /// 30 min, or whole hours from 1 to 12: LG rejects 1 h 30 and 13 h with `2201`, and a
    /// minute-only body with `2207`.
    static func isValidSleepTimer(minutes: Int) -> Bool {
        minutes == 30 || (minutes.isMultiple(of: 60) && (60...720).contains(minutes))
    }

    static func validateSleepTimer(minutes: Int?, caps: AirConditionerCapabilities) throws(ACModelError) {
        guard caps.hasSleepTimer else { throw .notWritable("\(sleepTimerResource).\(sleepHourKey)") }
        if let minutes, !isValidSleepTimer(minutes: minutes) {
            throw .invalidSleepTimer(minutes: minutes)
        }
    }

    /// Whole hours send the hour alone, 30 min sends `hour 0, minute 30`, and `nil` cancels.
    /// `relativeStopTimer: SET` is never sent: the profile only allows writing `UNSET`.
    static func sleepTimerPayload(minutes: Int?) -> JSONObject {
        guard let minutes else {
            return [sleepTimerResource: [sleepStatusKey: "UNSET"]]
        }
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        var body: JSONObject = [sleepHourKey: .number(Double(hours))]
        if rest != 0 {
            body[sleepMinuteKey] = .number(Double(rest))
        }
        return [sleepTimerResource: .object(body)]
    }

    /// What the state reads once the write lands: `SET` with the full duration as the remaining
    /// time, or `UNSET` (leftover hour/minute keys are ignored when reading `UNSET`).
    static func sleepTimerStateDelta(minutes: Int?) -> JSONObject {
        guard let minutes else {
            return [sleepTimerResource: [sleepStatusKey: "UNSET"]]
        }
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        return [
            sleepTimerResource: [
                sleepStatusKey: "SET",
                sleepHourKey: .number(Double(hours)),
                sleepMinuteKey: .number(Double(rest)),
            ],
        ]
    }

    /// `nil` when the state has no `sleepTimer`; `.off` unless `relativeStopTimer` is `SET`.
    static func sleepTimer(in state: DeviceState) -> SleepTimerState? {
        guard let timer = state.values[sleepTimerResource]?.objectValue else { return nil }
        guard timer[sleepStatusKey]?.stringValue == "SET" else { return .off }
        let hours = timer[sleepHourKey]?.doubleValue
        let minutes = timer[sleepMinuteKey]?.doubleValue
        guard hours != nil || minutes != nil else { return .set(remaining: nil) }
        let total = (hours ?? 0) * 60 + (minutes ?? 0)
        // A garbled value must not trap in `Duration`; a week is far beyond the 12 h maximum.
        guard total.isFinite, (0...maximumReportedSleepMinutes).contains(total) else { return .set(remaining: nil) }
        return .set(remaining: .seconds(total * 60))
    }

    private static let maximumReportedSleepMinutes = 7.0 * 24 * 60
}
