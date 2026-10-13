import Foundation

extension ACStore.ConnectionTestResult {
    /// What Settings shows after "Test connection".
    var message: LocalizedStringResource {
        switch self {
        case .success(let count):
            // Plural variants (one/other) live in Localizable.xcstrings.
            "Connected. \(count) air conditioners found."
        case .noAirConditioners:
            "Connected, but this account has no air conditioner."
        case .missingToken:
            "Paste a token first."
        case .tokenInvalid:
            "LG rejected this token."
        case .rateLimited:
            "LG is rate limiting this account. Try again later."
        case .unsupportedCountry:
            "This account isn't registered in the selected country."
        case .failed(let text):
            "\(text)"
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var symbolName: String {
        isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
}
