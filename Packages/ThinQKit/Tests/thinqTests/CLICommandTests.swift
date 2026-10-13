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
        #expect(try parse("set dev fan auto") == .set(deviceID: "dev", command: .fan(.auto)))
        #expect(try parse("set dev fan AUTO") == .set(deviceID: "dev", command: .fan(.auto)))
        #expect(try parse("set dev fan 3") == .set(deviceID: "dev", command: .fan(.level(3))))
        #expect(try parse("set dev temp 22.5") == .set(deviceID: "dev", command: .targetTemperature(22.5)))
        #expect(try parse("set dev eco 1") == .set(deviceID: "dev", command: .powerSave(true)))
        #expect(try parse("set dev swing on") == .set(deviceID: "dev", command: .verticalSwing(true)))
        #expect(try parse("set dev swing OFF") == .set(deviceID: "dev", command: .verticalSwing(false)))
        #expect(try parse("set dev light on") == .set(deviceID: "dev", command: .displayLight(true)))
        #expect(try parse("set dev light off") == .set(deviceID: "dev", command: .displayLight(false)))
        #expect(try parse("set dev sleep 30") == .set(deviceID: "dev", command: .sleepTimer(minutes: 30)))
        #expect(try parse("set dev sleep 120") == .set(deviceID: "dev", command: .sleepTimer(minutes: 120)))
        #expect(try parse("set dev sleep off") == .set(deviceID: "dev", command: .sleepTimer(minutes: nil)))
        #expect(try parse("set dev sleep 90") == .set(deviceID: "dev", command: .sleepTimer(minutes: 90)), "ThinQKit validates the value")
    }

    @Test(arguments: [
        ["set", "dev", "temp", "warm"],
        ["set", "dev", "temp", "nan"],
        ["set", "dev", "temp", "inf"],
        ["set", "dev", "power", "maybe"],
        ["set", "dev", "power"],
        ["set", "dev", "fan", "high"],
        ["set", "dev", "fan", "NATURE"],
        ["set", "dev", "fan", "0"],
        ["set", "dev", "fan", "-1"],
        ["set", "dev", "fan", "2.5"],
        ["set", "dev", "swing", "left"],
        ["set", "dev", "light", "dim"],
        ["set", "dev", "sleep", "0"],
        ["set", "dev", "sleep", "-30"],
        ["set", "dev", "sleep", "1h"],
        ["set", "dev", "step", "4"],
    ])
    func invalidSetIsRejected(arguments: [String]) {
        #expect(usageError(arguments) != nil)
    }

    @Test func setRawTakesTheJSONAsOneArgument() throws {
        let body = #"{"airFlow":{"windStrengthDetail":"MID_HIGH"}, "sleepTimer": {"relativeHourToStop": 1}}"#
        #expect(try CLICommand.parse(["set", "dev", "raw", body]) == .setRaw(
            deviceID: "dev",
            body: ["airFlow": ["windStrengthDetail": "MID_HIGH"], "sleepTimer": ["relativeHourToStop": 1]]
        ))
        #expect(try CLICommand.parse(["set", "dev", "RAW", #"{"airFlow":{"windStep":4}}"#])
            == .setRaw(deviceID: "dev", body: ["airFlow": ["windStep": 4]]))
    }

    @Test(arguments: [
        #"[{"airFlow":{}}]"#, "{}", " { } ", "", "{airFlow:1}", #"{"airFlow":"#, #""AUTO""#, "42", "null",
    ])
    func setRawRejectsAnythingButANonEmptyObject(body: String) {
        #expect(usageError(["set", "dev", "raw", body])?.contains("raw body") == true)
    }

    @Test func setRawNeedsExactlyOneJSONArgument() {
        // Unquoted JSON with spaces arrives as several arguments.
        #expect(usageError(["set", "dev", "raw", #"{"airFlow":"#, #"{"windStep":4}}"#]) != nil)
        #expect(usageError(["set", "dev", "raw"]) != nil)
        #expect(usageError(["set", "", "raw", #"{"a":1}"#]) == "<deviceId> must not be empty")
    }

    @Test func energyTakesOneDeviceID() throws {
        #expect(try parse("energy dev") == .energy(deviceID: "dev"))
        #expect(usageError(["energy"]) == "'energy' needs exactly one <deviceId>")
        #expect(usageError(["energy", "dev", "other"]) == "'energy' needs exactly one <deviceId>")
        #expect(usageError(["energy", " "]) == "<deviceId> must not be empty")
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
