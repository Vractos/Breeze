import Foundation
import ThinQKit

extension ACStore {
    /// "Which one is this?" in Settings › Device: enough of an AC's state
    /// to match it with the room the user is in. Read without the device's profile (fetching
    /// it would cost a second request per AC), so only power and room temperature.
    nonisolated enum DevicePreview: Equatable, Sendable {
        case reported(power: ACPower, roomTemperature: Measurement<UnitTemperature>?)
        /// 1222: LG says the AC is not connected.
        case offline
        /// Not fetched (no client, token rejected, inside a 1306 back-off) or the request failed.
        case unavailable

        /// Missing or unrecognised power reads as `.off`, as in `AirConditionerSnapshot`.
        init(state: DeviceState) {
            let power = state["operation", "airConOperationMode"]?.stringValue.flatMap(ACPower.init(rawValue:))
            self = .reported(power: power ?? .off, roomTemperature: Self.roomTemperature(in: state))
        }

        /// The same lookup order as ThinQKit's temperature capability: `temperatureInUnits`
        /// (the °C entry, else the first), then the flat `temperature` object.
        private static func roomTemperature(in state: DeviceState) -> Measurement<UnitTemperature>? {
            let inUnits = state.values["temperatureInUnits"]?.arrayValue ?? []
            let candidates = [
                inUnits.first { $0["unit"]?.stringValue == "C" } ?? inUnits.first,
                state.values["temperature"],
            ]
            for entry in candidates.compactMap(\.self) {
                guard let value = entry["currentTemperature"]?.doubleValue else { continue }
                let isFahrenheit = entry["unit"]?.stringValue?.uppercased() == "F"
                return Measurement(value: value, unit: isFahrenheit ? .fahrenheit : .celsius)
            }
            return nil
        }
    }
}
