import Foundation
import ThinQKit

/// Text rendering for the CLI. stdout carries results (pipeable); stderr carries notes/errors.
enum CLIOutput {
    /// Writes straight to fd 1. `print` goes through C stdio, which is fully buffered when stdout
    /// is a pipe or file, and Ctrl-C ends `watch` without flushing it: `thinq watch … | tee log`
    /// would show nothing for hours and lose the buffered lines. This also keeps results in order
    /// with the (unbuffered) notes on stderr.
    static func line(_ text: String = "") {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func note(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    static func error(_ text: String) {
        note("error: \(text)")
    }

    /// Pretty, key-sorted JSON (stable, so it can become a test fixture).
    static func json(_ value: JSONValue) throws(CLIFailure) -> String {
        do {
            let data = try value.jsonData(pretty: true)
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw .api(error)
        }
    }

    static func table(_ rows: [[String]], header: [String]) -> String {
        let all = [header] + rows
        let widths = header.indices.map { column in
            all.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
        }
        return all.map { row in
            row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
        }
        .joined(separator: "\n")
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func temperature(_ value: Measurement<UnitTemperature>?) -> String {
        guard let value else { return "—" }
        let symbol = value.unit == .fahrenheit ? "°F" : "°C"
        return "\(number(value.value)) \(symbol)"
    }

    static func range(_ range: PropertySpec.NumericRange) -> String {
        var text = "\(number(range.min))–\(number(range.max))"
        if let step = range.step { text += " step \(number(step))" }
        if !range.except.isEmpty { text += " except \(range.except.map(number).joined(separator: ","))" }
        return text
    }

    static func describe(_ spec: PropertySpec) -> String {
        let access = (spec.isReadable ? "r" : "-") + (spec.isWritable ? "w" : "-")
        let detail: String
        switch spec.kind {
        case .enum(let readable, let writable):
            detail = "enum  r=[\(readable.joined(separator: ","))] w=[\(writable.joined(separator: ","))]"
        case .range(let readable, let writable):
            detail = "range r=\(readable.map(range) ?? "—") w=\(writable.map(range) ?? "—")"
        case .boolean:
            detail = "boolean"
        case .number:
            detail = "number"
        case .string:
            detail = "string"
        case .list:
            detail = "list"
        case .unknown:
            detail = "unknown"
        }
        return "\(access)  \(detail)"
    }

    static func describe(_ caps: AirConditionerCapabilities) -> [String] {
        let modes = caps.modes.map { "\($0.rawValue) (\(String(localized: $0.displayName)))" }
        let temperature = caps.temperature
        let setpoints = temperature.writableTargets.keys.sorted().compactMap { key in
            temperature.writableTargets[key].map { "\(key) \(range($0)) °\(temperature.unitCode)" }
        }
        let target = setpoints.isEmpty ? "not writable" : setpoints.joined(separator: "; ")
        return [
            "Power:        \(caps.powerOptions.map(\.rawValue).joined(separator: ", "))",
            "Modes:        \(modes.isEmpty ? "not writable" : modes.joined(separator: ", "))",
            "Fan:          \(describe(caps.fan))",
            "Temperature:  shape \(temperature.shape.rawValue), unit °\(temperature.unitCode), current \(temperature.currentReadable ? "readable" : "not readable")",
            "Target:       \(target)",
            "Eco:          \(caps.hasPowerSave ? "yes" : "no")",
            "Swing:        vertical \(yesNo(caps.hasVerticalSwing)), horizontal \(yesNo(caps.hasHorizontalSwing))",
            "Light:        \(yesNo(caps.hasDisplayLight))",
            "Sleep timer:  \(caps.hasSleepTimer ? "yes (30 min, or whole hours 1–12)" : "no")",
        ]
    }

    /// `Auto, levels 1–5 [AUTO via airFlow.windStrength; levels via airFlow.windStrengthDetail: LOW, …]`.
    static func describe(_ fan: FanCapability) -> String {
        guard !fan.options.isEmpty else { return "not writable" }
        var offered: [String] = []
        var keys: [String] = []
        if let autoKey = fan.autoKey {
            offered.append("Auto")
            keys.append("AUTO via airFlow.\(autoKey)")
        }
        if !fan.levelValues.isEmpty {
            offered.append(fan.levelValues.count == 1 ? "level 1" : "levels 1–\(fan.levelValues.count)")
            keys.append("levels via airFlow.\(fan.levelKey): \(fan.levelValues.joined(separator: ", "))")
        }
        return "\(offered.joined(separator: ", ")) [\(keys.joined(separator: "; "))]"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func onOff(_ value: Bool?) -> String {
        value.map { $0 ? "on" : "off" } ?? "—"
    }

    static func describe(_ snapshot: AirConditionerSnapshot) -> [String] {
        let mode = snapshot.mode.map { "\(String(localized: $0.displayName)) (\($0.rawValue))" } ?? "—"
        let fan = snapshot.fan.map { $0 == .auto ? "Auto" : $0.description } ?? "—"
        return [
            "Power:   \(snapshot.power == .on ? "on" : "off")",
            "Mode:    \(mode)",
            "Fan:     \(fan)",
            "Room:    \(temperature(snapshot.currentTemperature))",
            "Target:  \(temperature(snapshot.targetTemperature))",
            "Eco:     \(onOff(snapshot.powerSave))",
            "Swing:   vertical \(onOff(snapshot.verticalSwing)), horizontal \(onOff(snapshot.horizontalSwing))",
            "Light:   \(onOff(snapshot.displayLight))",
            "Sleep:   \(sleepTimer(snapshot.sleepTimer))",
        ]
    }

    static func sleepTimer(_ state: SleepTimerState?) -> String {
        switch state {
        case nil: "—"
        case .off?: "off"
        case .set(let remaining)?:
            remaining.map { "\($0.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) left" } ?? "on"
        }
    }

    /// Flattens a state tree into `path → compact JSON` leaves, for diffing in `watch`.
    /// Unit-tagged list entries are addressed by unit (`temperatureInUnits[C].targetTemperature`).
    static func leaves(of value: JSONValue, prefix: String = "") -> [String: String] {
        switch value {
        case .object(let object):
            var result: [String: String] = [:]
            for (key, child) in object {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                result.merge(leaves(of: child, prefix: path)) { _, new in new }
            }
            return result
        case .array(let items):
            var result: [String: String] = [:]
            for (index, child) in items.enumerated() {
                let tag = child["unit"]?.stringValue ?? String(index)
                result.merge(leaves(of: child, prefix: "\(prefix)[\(tag)]")) { _, new in new }
            }
            return result
        default:
            return [prefix: value.compactDescription]
        }
    }
}
