import Testing
import ThinQKit
@testable import thinq

@Suite("CLI argument parsing")
struct CLICommandTests {
    private func parse(_ line: String) throws(CLIFailure) -> CLICommand {
        try CLICommand.parse(line.split(separator: " ").map(String.init))
    }

    /// The usage message of a rejected invocation, or `nil` if it parsed.
    private func usageError(_ arguments: [String]) -> String? {
        do {
            _ = try CLICommand.parse(arguments)
            return nil
        } catch {
            guard case .usage(let message) = error else { return "not a usage error: \(error)" }
            return message
        }
    }

    @Test func watchIntervalForms() throws {
        #expect(try parse("watch dev") == .watch(deviceID: "dev", everySeconds: CLICommand.defaultWatchInterval))
        #expect(try parse("watch dev --every 30") == .watch(deviceID: "dev", everySeconds: 30))
        #expect(try parse("watch --every=45 dev") == .watch(deviceID: "dev", everySeconds: 45))
        #expect(try parse("watch dev --every 86400") == .watch(deviceID: "dev", everySeconds: 86_400))
    }

    @Test(arguments: ["9", "0", "-5", "abc", "1.5", "86401", "9223372036854775807", "99999999999999999999"])
    func watchIntervalOutOfBoundsIsRejected(value: String) {
        #expect(usageError(["watch", "dev", "--every", value])?.contains("--every must be") == true)
        #expect(usageError(["watch", "dev", "--every=\(value)"])?.contains("--every must be") == true)
    }

    @Test func watchNeedsTheIntervalValue() {
        #expect(usageError(["watch", "dev", "--every"]) != nil)
    }

    @Test func setParsesEverySetting() throws {
        #expect(try parse("set dev power on") == .set(deviceID: "dev", command: .power(.on)))
        #expect(try parse("set dev power OFF") == .set(deviceID: "dev", command: .power(.off)))
        #expect(try parse("set dev mode cool") == .set(deviceID: "dev", command: .mode(.cool)))
        #expect(try parse("set dev fan high") == .set(deviceID: "dev", command: .fanSpeed(.high)))
        #expect(try parse("set dev temp 22.5") == .set(deviceID: "dev", command: .targetTemperature(22.5)))
        #expect(try parse("set dev eco 1") == .set(deviceID: "dev", command: .powerSave(true)))
    }

    @Test(arguments: [
        ["set", "dev", "temp", "warm"],
        ["set", "dev", "temp", "nan"],
        ["set", "dev", "temp", "inf"],
        ["set", "dev", "power", "maybe"],
        ["set", "dev", "swing", "on"],
        ["set", "dev", "power"],
    ])
    func invalidSetIsRejected(arguments: [String]) {
        #expect(usageError(arguments) != nil)
    }

    @Test(arguments: [
        ["state", ""], ["profile", " "], ["set", "", "power", "on"], ["watch", ""],
    ])
    func emptyDeviceIDIsRejected(arguments: [String]) {
        #expect(usageError(arguments) == "<deviceId> must not be empty")
    }

    @Test func helpAndUnknownCommands() throws {
        #expect(try parse("help") == .help)
        #expect(try parse("--help") == .help)
        #expect(usageError(["frobnicate"]) != nil)
        #expect(usageError([]) != nil)
        #expect(usageError(["devices", "extra"]) != nil)
    }
}
