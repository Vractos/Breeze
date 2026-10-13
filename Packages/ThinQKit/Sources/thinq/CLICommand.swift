import Foundation
import ThinQKit

/// A parsed `thinq` invocation. Hand-parsed to keep the package dependency-free.
enum CLICommand: Equatable {
    case help
    case devices
    case profile(deviceID: String, raw: Bool)
    case state(deviceID: String, raw: Bool)
    case set(deviceID: String, command: ACCommand)
    /// A control body POSTed as-is, without capability checks; for probing the real unit.
    case setRaw(deviceID: String, body: JSONObject)
    case energy(deviceID: String)
    case watch(deviceID: String, everySeconds: Int)

    static let defaultWatchInterval = 120
    static let minimumWatchInterval = 10
    /// One day. Bounds the backoff arithmetic and `Duration.seconds` in `watch`.
    static let maximumWatchInterval = 86_400

    static let usage = """
        usage: thinq <command> [arguments]

        commands:
          devices                          list devices: id, type, model, alias
          profile <deviceId> [--raw]       parsed capabilities, or the raw profile JSON
          state <deviceId> [--raw]         current state, or the raw state JSON
          set <deviceId> power on|off
          set <deviceId> mode <MODE>       e.g. COOL, AIR_DRY, FAN (see `profile`)
          set <deviceId> fan AUTO|<level>  level 1…n, slowest first (see `profile`)
          set <deviceId> temp <degrees>    e.g. 22 or 22.5
          set <deviceId> eco on|off
          set <deviceId> swing on|off      up/down swing
          set <deviceId> light on|off      display light
          set <deviceId> sleep <minutes>|off
                                           30, or whole hours 60…720
          set <deviceId> raw '<json>'      POST a control body as-is, without checks, e.g.
                                           '{"airFlow":{"windStrength":"AUTO"}}'
          energy <deviceId>                raw energy profile and usage (this month, last 7 days)
          watch <deviceId> [--every N]     poll every N seconds (default 120) and print changes
          help                             show this text

        environment:
          THINQ_PAT       personal access token from https://connect-pat.lgthinq.com (required)
          THINQ_COUNTRY   ISO country of the ThinQ account (default BR)

        The CLI keeps its client id in ~/Library/Application Support/Breeze/thinq-cli-client-id.
        """

    /// - Parameter arguments: `CommandLine.arguments` without the program name.
    static func parse(_ arguments: [String]) throws(CLIFailure) -> CLICommand {
        guard let name = arguments.first else {
            throw .usage("missing command")
        }
        let rest = Array(arguments.dropFirst())
        switch name {
        case "help", "-h", "--help":
            return .help
        case "devices":
            try expectNoExtraArguments(rest, command: name)
            return .devices
        case "profile":
            let (deviceID, raw) = try parseDeviceAndRawFlag(rest, command: name)
            return .profile(deviceID: deviceID, raw: raw)
        case "state":
            let (deviceID, raw) = try parseDeviceAndRawFlag(rest, command: name)
            return .state(deviceID: deviceID, raw: raw)
        case "set":
            return try parseSet(rest)
        case "watch":
            return try parseWatch(rest)
        case "energy":
            return .energy(deviceID: try singleDeviceID(rest, command: name))
        default:
            throw .usage("unknown command '\(name)'")
        }
    }

    private static func expectNoExtraArguments(_ arguments: [String], command: String) throws(CLIFailure) {
        guard arguments.isEmpty else {
            throw .usage("'\(command)' takes no arguments, got: \(arguments.joined(separator: " "))")
        }
    }

    private static func parseDeviceAndRawFlag(_ arguments: [String], command: String) throws(CLIFailure) -> (String, Bool) {
        var raw = false
        var positional: [String] = []
        for argument in arguments {
            if argument == "--raw" {
                raw = true
            } else if argument.hasPrefix("--") {
                throw .usage("unknown option '\(argument)' for '\(command)'")
            } else {
                positional.append(argument)
            }
        }
        return (try singleDeviceID(positional, command: command), raw)
    }

    private static func parseSet(_ arguments: [String]) throws(CLIFailure) -> CLICommand {
        guard arguments.count == 3 else {
            throw .usage("'set' needs <deviceId> <power|mode|fan|temp|eco|swing|light|sleep|raw> <value> (quote raw JSON)")
        }
        let deviceID = arguments[0]
        try expectDeviceID(deviceID)
        let value = arguments[2]
        if arguments[1].lowercased() == "raw" {
            return .setRaw(deviceID: deviceID, body: try parseRawBody(value))
        }
        let command: ACCommand
        switch arguments[1].lowercased() {
        case "power":
            command = .power(try parseOnOff(value, setting: "power") ? .on : .off)
        case "mode":
            command = .mode(ACMode(rawValue: value.uppercased()))
        case "fan":
            command = .fan(try parseFan(value))
        case "temp", "temperature":
            guard let degrees = Double(value), degrees.isFinite else {
                throw .usage("temperature must be a number, got '\(value)'")
            }
            command = .targetTemperature(degrees)
        case "eco":
            command = .powerSave(try parseOnOff(value, setting: "eco"))
        case "swing":
            command = .verticalSwing(try parseOnOff(value, setting: "swing"))
        case "light":
            command = .displayLight(try parseOnOff(value, setting: "light"))
        case "sleep":
            command = .sleepTimer(minutes: try parseSleep(value))
        default:
            throw .usage("unknown setting '\(arguments[1])'; expected power, mode, fan, temp, eco, swing, light, sleep or raw")
        }
        return .set(deviceID: deviceID, command: command)
    }

    /// `AUTO` or a level ≥ 1; the upper bound comes from the profile when the command is sent.
    private static func parseFan(_ value: String) throws(CLIFailure) -> ACFanSetting {
        if value.uppercased() == "AUTO" { return .auto }
        guard let level = Int(value), level >= 1 else {
            throw .usage("fan must be AUTO or a level from 1 (slowest), got '\(value)'")
        }
        return .level(level)
    }

    /// `off` cancels; otherwise minutes, validated against what LG accepts when sent.
    private static func parseSleep(_ value: String) throws(CLIFailure) -> Int? {
        if value.lowercased() == "off" { return nil }
        guard let minutes = Int(value), minutes > 0 else {
            throw .usage("sleep must be off or a number of minutes (30, 60, 120, … 720), got '\(value)'")
        }
        return minutes
    }

    private static func parseRawBody(_ text: String) throws(CLIFailure) -> JSONObject {
        let json: JSONValue
        do {
            json = try JSONValue(jsonData: Data(text.utf8))
        } catch {
            throw .usage("raw body is not valid JSON: \(error)")
        }
        guard let body = json.objectValue, !body.isEmpty else {
            throw .usage("raw body must be a non-empty JSON object, e.g. '{\"airFlow\":{\"windStrength\":\"AUTO\"}}'")
        }
        return body
    }

    private static func parseOnOff(_ value: String, setting: String) throws(CLIFailure) -> Bool {
        switch value.lowercased() {
        case "on", "true", "1": return true
        case "off", "false", "0": return false
        default: throw .usage("\(setting) must be on or off, got '\(value)'")
        }
    }

    private static func parseWatch(_ arguments: [String]) throws(CLIFailure) -> CLICommand {
        var interval = defaultWatchInterval
        var positional: [String] = []
        var remaining = arguments.makeIterator()
        while let argument = remaining.next() {
            if argument == "--every" {
                guard let value = remaining.next() else { throw .usage("--every needs a number of seconds") }
                interval = try parseInterval(value)
            } else if argument.hasPrefix("--every=") {
                interval = try parseInterval(String(argument.dropFirst("--every=".count)))
            } else if argument.hasPrefix("--") {
                throw .usage("unknown option '\(argument)' for 'watch'")
            } else {
                positional.append(argument)
            }
        }
        let deviceID = try singleDeviceID(positional, command: "watch")
        return .watch(deviceID: deviceID, everySeconds: interval)
    }

    private static func parseInterval(_ text: String) throws(CLIFailure) -> Int {
        guard let seconds = Int(text), (minimumWatchInterval...maximumWatchInterval).contains(seconds) else {
            throw .usage(
                "--every must be a whole number of seconds between \(minimumWatchInterval) and \(maximumWatchInterval), got '\(text)'"
            )
        }
        return seconds
    }

    private static func singleDeviceID(_ positional: [String], command: String) throws(CLIFailure) -> String {
        guard positional.count == 1, let deviceID = positional.first else {
            throw .usage("'\(command)' needs exactly one <deviceId>")
        }
        try expectDeviceID(deviceID)
        return deviceID
    }

    /// ThinQKit also rejects these, but a usage error is clearer than an API error.
    private static func expectDeviceID(_ deviceID: String) throws(CLIFailure) {
        guard !deviceID.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw .usage("<deviceId> must not be empty")
        }
    }
}
