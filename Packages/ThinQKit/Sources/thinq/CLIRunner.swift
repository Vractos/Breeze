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

    private static func shortType(_ type: String) -> String {
        type.hasPrefix("DEVICE_") ? String(type.dropFirst("DEVICE_".count)) : type
    }
}
