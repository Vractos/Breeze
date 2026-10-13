/// Which of the two temperature layouts the profile uses. Decides both where
/// the snapshot reads temperatures and what the control payload looks like.
public enum TemperatureShape: String, Sendable, Equatable {
    /// Shape A: `"temperature": {"currentTemperature", "targetTemperature", "unit"}`.
    case flat
    /// Shape B: `"temperatureInUnits": [{"unit": "C", …}, {"unit": "F", …}]`.
    case inUnits

    /// The value for this shape, else the other one.
    func preferring<T>(flat: T?, inUnits: T?) -> T? {
        switch self {
        case .flat: flat ?? inUnits
        case .inUnits: inUnits ?? flat
        }
    }
}
