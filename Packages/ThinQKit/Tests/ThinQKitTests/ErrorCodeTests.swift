import Foundation
import Testing
@testable import ThinQKit

@Suite("Error codes")
struct ErrorCodeTests {
    @Test func everyNamedCodeRoundTrips() {
        #expect(ThinQErrorCode.allNamed.count == 59)
        for code in ThinQErrorCode.allNamed {
            #expect(ThinQErrorCode(rawValue: code.rawValue) == code)
            #expect(code.name != "UNKNOWN")
        }
        #expect(Set(ThinQErrorCode.allNamed.map(\.rawValue)).count == ThinQErrorCode.allNamed.count)
    }

    @Test(arguments: [
        ("1103", "INVALID_TOKEN"), ("1218", "INVALID_TOKEN_AGAIN"), ("1302", "NOT_FOUND_TOKEN"),
        ("1306", "EXCEEDED_API_CALLS"), ("1307", "NOT_SUPPORTED_COUNTRY"), ("1222", "NOT_CONNECTED_DEVICE"),
        ("1207", "ALREADY_SUBSCRIBED_PUSH"), ("1309", "NOT_ALLOWED_API_AGAIN"),
        ("2302", "COMMAND_NOT_SUPPORTED_IN_STATE"), ("2304", "COMMAND_NOT_SUPPORTED_IN_POWER_OFF"),
        ("2209", "DEVICE_RESPONSE_DELAY"), ("2210", "RETRY_REQUEST"), ("1214", "NOT_SUBSCRIBABLE_DEVICE"),
    ])
    func namedCodes(raw: String, name: String) {
        #expect(ThinQErrorCode(rawValue: raw).name == name)
    }

    @Test func classificationFlags() {
        func api(_ raw: String) -> ThinQError { .api(code: ThinQErrorCode(rawValue: raw), message: "") }
        #expect(api("1103").isTokenInvalid)
        #expect(api("1218").isTokenInvalid)
        #expect(api("1302").isTokenInvalid)
        #expect(!api("1306").isTokenInvalid)
        #expect(api("1306").isRateLimited)
        #expect(api("1222").isDeviceOffline)
        #expect(!ThinQError.httpStatus(500).isTokenInvalid)
        #expect(ThinQError.httpStatus(500).apiCode == nil)
    }

    private static let inState = ThinQError.api(code: .commandNotSupportedInState, message: "")
    private static let inPowerOff = ThinQError.api(code: .commandNotSupportedInPowerOff, message: "")

    @Test func onlyRepeatedPowerCommandsAreRedundant() {
        #expect(ACCommand.power(.on).isRedundant(Self.inState))
        #expect(ACCommand.power(.off).isRedundant(Self.inPowerOff))
        #expect(!ACCommand.power(.on).isRedundant(Self.inPowerOff))
        #expect(!ACCommand.power(.off).isRedundant(Self.inState))
        #expect(!ACCommand.power(.on).isRedundant(.api(code: .commandNotSupportedInMode, message: "")))
        #expect(!ACCommand.power(.on).isRedundant(.httpStatus(400)))
    }

    @Test(arguments: [
        ACCommand.mode(.cool), .targetTemperature(22), .fanSpeed(.low), .powerSave(true), .powerSave(false),
    ])
    func nonPowerCommandsAreNeverRedundant(command: ACCommand) {
        // 2304 on these means "the AC is off; turn it on first".
        #expect(!command.isRedundant(Self.inState))
        #expect(!command.isRedundant(Self.inPowerOff))
    }
}
