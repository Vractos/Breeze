/// The fan settings a model offers, and how each one is written and read.
///
/// LG reports one fan setting through up to three `airFlow` keys: the coarse `windStrength`, the
/// finer `windStrengthDetail` and the numeric `windStep`. Levels are the writable
/// detail values in canonical order (else the coarse ones) and are written through that key.
/// `windStep` is never written to LG nor read: the official object example reports `windStep: 5`
/// on a 3-level profile, and while Auto a real unit drops it, so it is often stale.
public struct FanCapability: Sendable, Equatable {
    /// Raw values of levels 1…n, slowest first.
    public var levelValues: [String]
    /// The `airFlow` key levels are written through.
    public var levelKey: String
    /// The `airFlow` key `AUTO` is written through; `nil` when Auto isn't writable.
    public var autoKey: String?
    /// The fan keys the profile has (`windStrength`, `windStrengthDetail`, `windStep`). An
    /// optimistic change rewrites each of them, because `DeviceState.merge` can't delete stale ones.
    public var stateKeys: Set<String>
    /// Whether the detail key reports `NATURE` while Auto (a real unit does).
    public var detailReportsNature: Bool

    public static let unsupported = FanCapability(levelValues: [], levelKey: strengthKey, autoKey: nil)

    public init(
        levelValues: [String],
        levelKey: String,
        autoKey: String?,
        stateKeys: Set<String> = [],
        detailReportsNature: Bool = false
    ) {
        self.levelValues = levelValues
        self.levelKey = levelKey
        self.autoKey = autoKey
        self.stateKeys = stateKeys
        self.detailReportsNature = detailReportsNature
    }

    static let resource = "airFlow"
    static let strengthKey = "windStrength"
    static let detailKey = "windStrengthDetail"
    static let stepKey = "windStep"
    static let autoValue = "AUTO"
    static let natureValue = "NATURE"

    /// Level order of each key, slowest first. Values outside these lists (e.g. `NATURE`, or a
    /// model-specific one) are not levels.
    static let detailOrder = ["SLOW", "LOW", "LOW_MID", "MID", "MID_HIGH", "HIGH", "POWER"]
    static let strengthOrder = ["SLOW", "LOW", "MID", "HIGH", "POWER"]

    /// The coarse `windStrength` that goes with a detail level, as observed on a real unit
    /// (levels 1–5 → LOW, MID, MID, HIGH, HIGH). Other detail values keep their own name.
    static let coarseStrengthForDetail = ["LOW_MID": "MID", "MID_HIGH": "HIGH"]

    /// Display order: Auto first, then levels 1…n.
    public var options: [ACFanSetting] {
        (autoKey == nil ? [] : [.auto]) + levelValues.indices.map { .level($0 + 1) }
    }

    /// Derives the capability from the profile's `airFlow` resource.
    init(airFlow: [String: PropertySpec]) {
        let detail = airFlow[Self.detailKey]
        let strength = airFlow[Self.strengthKey]
        let detailLevels = Self.detailOrder.filter((detail?.writableValues ?? []).contains)
        let useDetail = !detailLevels.isEmpty

        let autoKey: String? = if strength?.writableValues.contains(Self.autoValue) == true {
            Self.strengthKey
        } else if detail?.writableValues.contains(Self.autoValue) == true {
            Self.detailKey
        } else {
            nil
        }
        let detailValues = (detail?.readableValues ?? []) + (detail?.writableValues ?? [])

        self.init(
            levelValues: useDetail ? detailLevels : Self.strengthOrder.filter((strength?.writableValues ?? []).contains),
            levelKey: useDetail ? Self.detailKey : Self.strengthKey,
            autoKey: autoKey,
            stateKeys: Set([Self.strengthKey, Self.detailKey, Self.stepKey].filter { airFlow[$0] != nil }),
            detailReportsNature: detailValues.contains(Self.natureValue)
        )
    }

    // MARK: - Write

    /// The one-key control body for `setting`.
    func payload(for setting: ACFanSetting) throws(ACModelError) -> JSONObject {
        guard !options.isEmpty else { throw .notWritable("\(Self.resource).\(levelKey)") }
        switch setting {
        case .auto:
            guard let autoKey else { throw .unsupportedFan(setting) }
            return [Self.resource: [autoKey: .string(Self.autoValue)]]
        case .level(let level):
            guard let value = levelValue(level) else { throw .unsupportedFan(setting) }
            return [Self.resource: [levelKey: .string(value)]]
        }
    }

    /// What the state should read after `setting` lands: every fan key the profile has, so no
    /// stale key contradicts the new value. No validation; an unknown level changes nothing.
    func stateDelta(for setting: ACFanSetting) -> JSONObject {
        var airFlow: JSONObject = [:]
        switch setting {
        case .auto:
            airFlow[autoKey ?? Self.strengthKey] = .string(Self.autoValue)
            if autoKey != Self.detailKey, detailReportsNature {
                airFlow[Self.detailKey] = .string(Self.natureValue)
            }
        case .level(let level):
            guard let value = levelValue(level) else { return [:] }
            airFlow[levelKey] = .string(value)
            if levelKey == Self.detailKey, stateKeys.contains(Self.strengthKey) {
                airFlow[Self.strengthKey] = .string(Self.coarseStrengthForDetail[value] ?? value)
            }
            if stateKeys.contains(Self.stepKey) {
                airFlow[Self.stepKey] = .number(Double(level))
            }
        }
        return [Self.resource: .object(airFlow)]
    }

    private func levelValue(_ level: Int) -> String? {
        levelValues.indices.contains(level - 1) ? levelValues[level - 1] : nil
    }

    // MARK: - Read

    /// The setting the state reports, or `nil` when it isn't one of `options`. Auto wins over
    /// any level key (on a real unit Auto also reports detail `NATURE` and drops `windStep`);
    /// then the level key's value, else the other key's, gives the level.
    func setting(in state: DeviceState) -> ACFanSetting? {
        let strength = state[Self.resource, Self.strengthKey]?.stringValue
        let detail = state[Self.resource, Self.detailKey]?.stringValue
        let setting: ACFanSetting?
        if strength == Self.autoValue || detail == Self.autoValue || detail == Self.natureValue {
            setting = .auto
        } else {
            let candidates = levelKey == Self.detailKey ? [detail, strength] : [strength, detail]
            setting = candidates
                .lazy
                .compactMap { $0.flatMap(levelValues.firstIndex(of:)) }
                .first
                .map { .level($0 + 1) }
        }
        return setting.flatMap { options.contains($0) ? $0 : nil }
    }
}
