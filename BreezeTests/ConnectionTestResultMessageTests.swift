import Foundation
import Testing
@testable import Breeze

/// The plural variants come from Localizable.xcstrings in the (host) app bundle.
@Suite("Connection test messages")
@MainActor
struct ConnectionTestResultMessageTests {
    @Test(arguments: [
        (1, "Connected. 1 air conditioner found."),
        (2, "Connected. 2 air conditioners found."),
    ])
    func successUsesThePluralRules(count: Int, expected: String) {
        var message = ACStore.ConnectionTestResult.success(airConditioners: count).message
        message.locale = Locale(identifier: "en_US")
        #expect(String(localized: message) == expected)
    }
}
