import Foundation

/// The three ThinQ Connect API regions.
public enum ThinQRegion: String, Sendable, CaseIterable {
    /// Americas.
    case aic
    /// Asia-Pacific.
    case kic
    /// Europe, Middle East, Africa.
    case eic

    /// The region used for country codes missing from the table. Breeze's default country is BR,
    /// which lives in `aic`.
    public static let fallback: ThinQRegion = .aic

    /// `https://api-<region>.lgthinq.com/`
    public var baseURL: URL {
        // The string is always a valid URL; the fallback only avoids a force unwrap.
        URL(string: "https://api-\(rawValue).lgthinq.com/") ?? URL(fileURLWithPath: "/")
    }

    /// Maps an ISO 3166-1 alpha-2 code (case-insensitive) to its region using the table from
    /// `thinqconnect/country.py` (SDK 1.0.14). Unknown codes map to `fallback` instead of failing,
    /// because LG answers a wrong region with a clear `1307` anyway.
    public static func forCountry(_ code: String) -> ThinQRegion {
        listedRegion(for: code) ?? fallback
    }

    /// Whether `code` appears in LG's supported-country table.
    public static func isSupportedCountry(_ code: String) -> Bool {
        listedRegion(for: code) != nil
    }

    private static func listedRegion(for code: String) -> ThinQRegion? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if kicCountries.contains(normalized) { return .kic }
        if aicCountries.contains(normalized) { return .aic }
        if eicCountries.contains(normalized) { return .eic }
        return nil
    }

    private static let kicCountries: Set<String> = [
        "AU", "BD", "CN", "HK", "ID", "IN", "JP", "KH", "KR", "LA", "LK", "MM", "MY", "NP", "NZ",
        "PH", "SG", "TH", "TW", "VN",
    ]

    private static let aicCountries: Set<String> = [
        "AG", "AR", "AW", "BB", "BO", "BR", "BS", "BZ", "CA", "CL", "CO", "CR", "CU", "DM", "DO",
        "EC", "GD", "GT", "GY", "HN", "HT", "JM", "KN", "LC", "MX", "NI", "PA", "PE", "PR", "PY",
        "SR", "SV", "TT", "US", "UY", "VC", "VE",
    ]

    private static let eicCountries: Set<String> = [
        "AE", "AF", "AL", "AM", "AO", "AT", "AZ", "BA", "BE", "BF", "BG", "BH", "BJ", "BY", "CD",
        "CF", "CG", "CH", "CI", "CM", "CV", "CY", "CZ", "DE", "DJ", "DK", "DZ", "EE", "EG", "ES",
        "ET", "FI", "FR", "GA", "GB", "GE", "GH", "GM", "GN", "GQ", "GR", "HR", "HU", "IE", "IL",
        "IQ", "IR", "IS", "IT", "JO", "KE", "KG", "KW", "KZ", "LB", "LR", "LT", "LU", "LV", "LY",
        "MA", "MD", "ME", "MK", "ML", "MR", "MT", "MU", "MW", "NE", "NG", "NL", "NO", "OM", "PK",
        "PL", "PS", "PT", "QA", "RO", "RS", "RU", "RW", "SA", "SD", "SE", "SI", "SK", "SL", "SN",
        "SO", "ST", "SY", "TD", "TG", "TN", "TR", "TZ", "UA", "UG", "UZ", "XK", "YE", "ZA", "ZM",
    ]
}
