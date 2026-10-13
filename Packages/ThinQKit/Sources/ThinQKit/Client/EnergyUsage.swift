import Foundation

/// `period` of `GET devices/energy/{id}/usage`.
public enum EnergyPeriod: String, Sendable {
    /// Days, `yyyyMMdd`, at most 31 per request.
    case daily = "DAILY"
    /// Months, `yyyyMM`, at most 12 per request.
    case monthly = "MONTHLY"

    /// The `startDate`/`endDate` query values of the inclusive range `from…to`, which must be
    /// real Gregorian dates covering 1…31 days or 1…12 months.
    func queryDates(from: DateComponents, to: DateComponents) throws(ThinQError) -> (start: String, end: String) {
        let start = try validated(from)
        let end = try validated(to)
        let unit: Calendar.Component = self == .daily ? .day : .month
        let maximum = self == .daily ? 31 : 12
        let span = (Self.gregorian.dateComponents([unit], from: start, to: end).value(for: unit) ?? 0) + 1
        guard (1...maximum).contains(span) else {
            throw ThinQError.invalidArgument("\(rawValue) energy range must cover 1…\(maximum) periods, got \(span)")
        }
        return (queryValue(start), queryValue(end))
    }

    /// Year, month and day; monthly dates count from the 1st.
    private func validated(_ date: DateComponents) throws(ThinQError) -> DateComponents {
        let day = self == .daily ? date.day : 1
        let validated = DateComponents(year: date.year, month: date.month, day: day)
        guard date.year != nil, date.month != nil, day != nil, validated.isValidDate(in: Self.gregorian) else {
            throw ThinQError.invalidArgument("\(rawValue) energy dates need a real year, month\(self == .daily ? " and day" : "")")
        }
        return validated
    }

    private func queryValue(_ date: DateComponents) -> String {
        let yearMonth = String(format: "%04d%02d", date.year ?? 0, date.month ?? 0)
        return self == .daily ? yearMonth + String(format: "%02d", date.day ?? 0) : yearMonth
    }

    /// UTC so whole-day arithmetic never meets a DST gap.
    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}

/// One `dataList` entry of the energy usage response.
public struct EnergyUsageEntry: Sendable, Equatable {
    /// Gregorian year and month, plus the day for `.daily`. LG's dates are in the user's local
    /// time, so these are calendar days/months, not instants.
    public var date: DateComponents
    public var energy: Measurement<UnitEnergy>

    public init(date: DateComponents, energy: Measurement<UnitEnergy>) {
        self.date = date
        self.energy = energy
    }
}

/// Parses the `response` payloads of the two Energy API endpoints. Public so the CLI can print
/// the raw payload and the parsed result from a single request.
public enum EnergyResponse {
    /// The spec documents `useAmount`, but real responses use the key named after the property
    /// (`energyUsage`, verified on a real unit); kept as a fallback.
    static let documentedValueKey = "useAmount"

    /// `result.property` of the energy profile, e.g. `["energyUsage"]`. Empty when absent.
    public static func properties(json: JSONValue?) throws(ThinQError) -> [String] {
        try resultList(json, key: "property", path: "energy/profile").compactMap(\.stringValue)
    }

    /// `result.dataList` of the usage response. Values are Wh (Home Assistant's unit).
    public static func entries(json: JSONValue?, property: String) throws(ThinQError) -> [EnergyUsageEntry] {
        var entries: [EnergyUsageEntry] = []
        for (index, item) in try resultList(json, key: "dataList", path: "energy/usage").enumerated() {
            let path = "energy/usage.result.dataList[\(index)]"
            guard let usedDate = item["usedDate"]?.stringValue, let date = parseDate(usedDate) else {
                throw ThinQError.decoding(path: path, underlying: JSONShapeError("missing or malformed usedDate"))
            }
            guard let wattHours = item[property]?.doubleValue ?? item[documentedValueKey]?.doubleValue else {
                throw ThinQError.decoding(
                    path: path,
                    underlying: JSONShapeError("no numeric '\(property)' or '\(documentedValueKey)'")
                )
            }
            entries.append(EnergyUsageEntry(date: date, energy: Measurement(value: wattHours / 1000, unit: .kilowattHours)))
        }
        return entries
    }

    /// `result[key]` as an array, empty when absent. Both endpoints answer HTTP 200 with their own
    /// `resultCode` (`0000` = OK; 1212, 1220, 1221, 1307, 2214 otherwise), so a non-`0000` code
    /// is turned into the matching API error.
    private static func resultList(_ json: JSONValue?, key: String, path: String) throws(ThinQError) -> [JSONValue] {
        if let code = json?["resultCode"]?.stringValue, code != "0000" {
            throw ThinQError.api(code: ThinQErrorCode(rawValue: code), message: "\(path) resultCode")
        }
        guard let value = json?["result"]?[key] else { return [] }
        guard let items = value.arrayValue else {
            throw ThinQError.decoding(path: "\(path).result.\(key)", underlying: JSONShapeError("not an array"))
        }
        return items
    }

    /// `yyyyMMdd` → year/month/day, `yyyyMM` → year/month; nil unless it is a real date.
    private static func parseDate(_ text: String) -> DateComponents? {
        guard text.count == 8 || text.count == 6, text.allSatisfy({ $0.isASCII && $0.isNumber }),
              let year = Int(text.prefix(4)), let month = Int(text.dropFirst(4).prefix(2)) else { return nil }
        let day = text.count == 8 ? Int(text.suffix(2)) : nil
        let isValid = DateComponents(year: year, month: month, day: day ?? 1).isValidDate(in: EnergyPeriod.gregorian)
        return isValid ? DateComponents(year: year, month: month, day: day) : nil
    }
}
