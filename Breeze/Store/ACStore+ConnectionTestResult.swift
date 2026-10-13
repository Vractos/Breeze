extension ACStore {
    /// Outcome of Settings' "Test connection" (and of `loadDevices()`).
    nonisolated enum ConnectionTestResult: Equatable, Sendable {
        /// The token works; the account has this many air conditioners.
        case success(airConditioners: Int)
        /// The token works but the account has no air conditioner.
        case noAirConditioners
        case missingToken
        case tokenInvalid
        case rateLimited
        /// 1307: the account is not registered in the selected country.
        case unsupportedCountry
        /// Anything else, with a localized message.
        case failed(String)
    }
}
