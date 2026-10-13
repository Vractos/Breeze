import Foundation
import ThinQKit

/// Executes a parsed command against a client.
struct CLIRunner {
    let client: ThinQClient

    /// Upper bound for the watch interval after repeated rate limiting (15 min, like the app).
    static let maximumBackoffSeconds = 900

    func run(_ command: CLICommand) async throws(CLIFailure) {
        switch command {
        case .help:
            break // Handled in main.swift, before a token or client exists.
        case .devices:
            try await listDevices()
        case .profile(let deviceID, let raw):
            try await showProfile(deviceID: deviceID, raw: raw)
        case .state(let deviceID, let raw):
            try await showState(deviceID: deviceID, raw: raw)
        case .set(let deviceID, let command):
            try await set(deviceID: deviceID, command: command)
        case .setRaw(let deviceID, let body):
            try await setRaw(deviceID: deviceID, body: body)
        case .energy(let deviceID):
            try await showEnergy(deviceID: deviceID)
        case .watch(let deviceID, let everySeconds):
            try await watch(deviceID: deviceID, everySeconds: everySeconds)
        }
    }

    // MARK: - Commands

    private func listDevices() async throws(CLIFailure) {
        let devices = try await call { () async throws(ThinQError) in try await client.devices() }
        guard !devices.isEmpty else {
            CLIOutput.line("No devices on this account.")
            return
        }
        let rows = devices.map { device in
            [device.id, Self.shortType(device.deviceType), device.modelName, device.alias]
        }
        CLIOutput.line(CLIOutput.table(rows, header: ["ID", "TYPE", "MODEL", "ALIAS"]))
    }

    private func showProfile(deviceID: String, raw: Bool) async throws(CLIFailure) {
        let profile = try await call { () async throws(ThinQError) in try await client.profile(deviceID: deviceID) }
        if raw {
            CLIOutput.line(try CLIOutput.json(profile.raw))
            return
        }
        do throws(ACModelError) {
            let caps = try AirConditionerCapabilities(profile: profile)
            CLIOutput.line("Air conditioner capabilities")
            CLIOutput.describe(caps).forEach { CLIOutput.line("  \($0)") }
        } catch {
            CLIOutput.line("Not usable as an air conditioner: \(error)")
        }
        CLIOutput.line()
        CLIOutput.line("Properties")
        var rows: [[String]] = []
        for (resource, specs) in profile.resources.sorted(by: { $0.key < $1.key }) {
            for (key, spec) in specs.sorted(by: { $0.key < $1.key }) {
                rows.append(["\(resource).\(key)", CLIOutput.describe(spec)])
            }
        }
        for entry in profile.temperatureInUnits ?? [] {
            for (key, spec) in entry.properties.sorted(by: { $0.key < $1.key }) {
                rows.append(["temperatureInUnits[\(entry.unit)].\(key)", CLIOutput.describe(spec)])
            }
        }
        CLIOutput.line(CLIOutput.table(rows, header: ["PROPERTY", "ACCESS / VALUES"]))
    }

    private func showState(deviceID: String, raw: Bool) async throws(CLIFailure) {
        if raw {
            let state = try await call { () async throws(ThinQError) in try await client.state(deviceID: deviceID) }
            CLIOutput.line(try CLIOutput.json(.object(state.values)))
            return
        }
        let caps = try await capabilities(deviceID: deviceID)
        let state = try await call { () async throws(ThinQError) in try await client.state(deviceID: deviceID) }
        CLIOutput.describe(AirConditionerSnapshot(state: state, capabilities: caps)).forEach { CLIOutput.line($0) }
    }

    private func set(deviceID: String, command: ACCommand) async throws(CLIFailure) {
        let caps = try await capabilities(deviceID: deviceID)
        let currentMode = try await currentModeIfNeeded(for: command, deviceID: deviceID, caps: caps)
        let body: JSONObject
        do {
            body = try command.payload(for: caps, currentMode: currentMode)
        } catch {
            throw .model(error)
        }
        CLIOutput.note("POST devices/…/control \(JSONValue.object(body).compactDescription)")
        do {
            try await client.control(deviceID: deviceID, body: body)
            CLIOutput.line("OK")
        } catch where command.isRedundant(error) {
            CLIOutput.line("Already in that state (\(error.apiCode?.description ?? "")); nothing to do.")
        } catch {
            throw .api(error)
        }
    }

    /// No capability checks and no redundancy handling: the point is to see what LG answers.
    private func setRaw(deviceID: String, body: JSONObject) async throws(CLIFailure) {
        CLIOutput.note("POST devices/…/control \(JSONValue.object(body).compactDescription)")
        try await call { () async throws(ThinQError) in try await client.control(deviceID: deviceID, body: body) }
        CLIOutput.line("OK")
    }

    /// Prints each raw payload, then what ThinQKit parses from it, so a probe shows both the
    /// response shape and whether the parser agrees. A non-`0000` `resultCode` is an answer
    /// ("not supported"), not a failure. An HTTP error on the profile ends the run; on one usage
    /// range it is printed and the next range still runs (except a bad token or 1306).
    private func showEnergy(deviceID: String) async throws(CLIFailure) {
        let profile = try await call { () async throws(ThinQError) in try await client.energyProfileJSON(deviceID: deviceID) }
        CLIOutput.line("Energy profile (raw)")
        CLIOutput.line(try CLIOutput.json(profile ?? .null))
        var property = "energyUsage"
        do {
            let properties = try EnergyResponse.properties(json: profile)
            CLIOutput.line("Properties: \(properties.isEmpty ? "none" : properties.joined(separator: ", "))")
            property = properties.first ?? property
        } catch {
            CLIOutput.line("Energy profile not usable: \(error)")
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        let weekAgo = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: -6, to: now) ?? now)
        for (title, period, from) in [("This month", EnergyPeriod.monthly, today), ("Last 7 days", EnergyPeriod.daily, weekAgo)] {
            CLIOutput.line()
            let usage: JSONValue?
            do {
                usage = try await client.energyUsageJSON(deviceID: deviceID, property: property, period: period, from: from, to: today)
            } catch {
                // The two ranges are independent probes: report this one and still try the next.
                if error.isTokenInvalid || error.isRateLimited { throw .api(error) }
                CLIOutput.line("\(title): \(period.rawValue) \(property) failed: \(CLIFailure.api(error))")
                continue
            }
            CLIOutput.line("\(title): \(period.rawValue) \(property) (raw)")
            CLIOutput.line(try CLIOutput.json(usage ?? .null))
            do {
                let entries = try EnergyResponse.entries(json: usage, property: property)
                if entries.isEmpty { CLIOutput.line("Parsed: no entries") }
                for entry in entries {
                    CLIOutput.line("Parsed: \(Self.describe(entry.date))  \(entry.energy.value.formatted(.number.precision(.fractionLength(3)))) kWh")
                }
            } catch {
                CLIOutput.line("Usage not usable: \(error)")
            }
        }
    }

    /// The setpoint key depends on the job mode (`TemperatureCapability.writeKey(for:)`), so a
    /// temperature command costs one extra state fetch; other commands skip it.
    private func currentModeIfNeeded(
        for command: ACCommand,
        deviceID: String,
        caps: AirConditionerCapabilities
    ) async throws(CLIFailure) -> ACMode? {
        guard case .targetTemperature = command else { return nil }
        let state = try await call { () async throws(ThinQError) in try await client.state(deviceID: deviceID) }
        let mode = AirConditionerSnapshot(state: state, capabilities: caps).mode
        CLIOutput.note("Current mode: \(mode?.rawValue ?? "unknown")")
        return mode
    }

    private func watch(deviceID: String, everySeconds: Int) async throws(CLIFailure) {
        let caps = try await capabilities(deviceID: deviceID)
        var interval = everySeconds
        var previous: [String: String]?
        CLIOutput.note("Polling every \(interval) s; Ctrl-C to stop.")
        while !Task.isCancelled {
            do {
                let state = try await client.state(deviceID: deviceID)
                let leaves = CLIOutput.leaves(of: .object(state.values))
                printChanges(from: previous, to: leaves, snapshot: AirConditionerSnapshot(state: state, capabilities: caps))
                previous = leaves
                interval = everySeconds
            } catch {
                if error.isTokenInvalid { throw .api(error) }
                CLIOutput.error("\(Self.timestamp()) \(CLIFailure.api(error))")
                if error.isRateLimited {
                    interval = Self.backoffInterval(after: interval, everySeconds: everySeconds)
                    CLIOutput.note("Backing off to \(interval) s.")
                }
            }
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return // Cancelled.
            }
        }
    }

    /// The next poll interval after a `1306`: doubles up to 15 min, but never drops below the
    /// configured `--every` (a 30 min poll must not speed up when LG says the quota is used up).
    static func backoffInterval(after current: Int, everySeconds: Int) -> Int {
        let cap = max(everySeconds, maximumBackoffSeconds)
        return min(current * 2, cap)
    }

    // MARK: - Helpers

    private func capabilities(deviceID: String) async throws(CLIFailure) -> AirConditionerCapabilities {
        let profile = try await call { () async throws(ThinQError) in try await client.profile(deviceID: deviceID) }
        do {
            return try AirConditionerCapabilities(profile: profile)
        } catch {
            throw .model(error)
        }
    }

    private func call<T>(_ operation: () async throws(ThinQError) -> T) async throws(CLIFailure) -> T {
        do {
            return try await operation()
        } catch {
            throw .api(error)
        }
    }

    private func printChanges(from previous: [String: String]?, to current: [String: String], snapshot: AirConditionerSnapshot) {
        let time = Self.timestamp()
        guard let previous else {
            CLIOutput.line("[\(time)] initial state")
            CLIOutput.describe(snapshot).forEach { CLIOutput.line("  \($0)") }
            return
        }
        let paths = Set(previous.keys).union(current.keys).sorted()
        let changes = paths.compactMap { path -> String? in
            let old = previous[path]
            let new = current[path]
            guard old != new else { return nil }
            return "  \(path): \(old ?? "∅") → \(new ?? "∅")"
        }
        guard !changes.isEmpty else { return }
        CLIOutput.line("[\(time)] \(changes.count) change\(changes.count == 1 ? "" : "s")")
        changes.forEach { CLIOutput.line($0) }
    }

    private static func timestamp() -> String {
        Date.now.formatted(date: .omitted, time: .standard)
    }

    private static func describe(_ date: DateComponents) -> String {
        let yearMonth = String(format: "%04d-%02d", date.year ?? 0, date.month ?? 0)
        return date.day.map { yearMonth + String(format: "-%02d", $0) } ?? yearMonth
    }

    private static func shortType(_ type: String) -> String {
        type.hasPrefix("DEVICE_") ? String(type.dropFirst("DEVICE_".count)) : type
    }
}
