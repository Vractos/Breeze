import Foundation
import ThinQKit

/// A country the ThinQ account can be registered in, for the Account tab's picker.
nonisolated struct CountryOption: Identifiable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, as sent in `x-country`.
    let code: String
    /// Localized name ("Brazil"), or the code when the system has no name for it.
    let name: String

    var id: String { code }

    init(code: String, locale: Locale = .current) {
        self.code = code
        self.name = locale.localizedString(forRegionCode: code) ?? code
    }

    /// Every country in LG's supported-country table, by localized name. `current` is included
    /// even if it is not in the table, so the picker always shows the saved value.
    static func all(including current: String, locale: Locale = .current) -> [CountryOption] {
        var codes = Set(
            Locale.Region.isoRegions
                .map(\.identifier)
                .filter { $0.count == 2 && ThinQRegion.isSupportedCountry($0) }
        )
        codes.insert(current.uppercased())
        return codes
            .map { CountryOption(code: $0, locale: locale) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
