import Foundation
import Observation
import os
import ThinQKit

/// The single source of truth for the panel, the menu bar label and Settings.
///
/// Lifecycle: `start()` once at launch → loads devices, profile and the first state, then polls.
/// `reconfigure()` after the token, country or device changes. Views read the observable
/// properties and call `send(_:)`, `refresh()`, `panelDidAppear()`; they never see raw errors.
///
/// Concurrency model: everything runs on the main actor. Network calls suspend; after every
/// suspension the code checks `isCurrent(session)` so work started before a `stop()` /
/// `reconfigure()` can never write into the new session.
@Observable
@MainActor
final class ACStore {
    typealias ClientFactory = (ThinQConfiguration) -> any ThinQAPI

    /// LG/Home Assistant: at most one control POST per device every 3 s.
    static let minimumCommandSpacing: Duration = .seconds(3)
    /// After an implicit POWER_ON the AC needs ~2 s before it accepts mode/temperature.
    static let powerOnSettleTime: Duration = .seconds(2)
    /// Fetch the state this long after the last command of a burst, to reconcile.
    static let postBurstRefreshDelay: Duration = .seconds(4)
    /// Opening the panel refreshes only if the last sync is older than this (protects the quota).
    static let panelRefreshThreshold: Duration = .seconds(15)
    /// 2209 DEVICE_RESPONSE_DELAY: fetch once more after this long.
    static let deviceResponseDelayRetry: Duration = .seconds(3)
    /// Opening Settings › Energy fetches only if the last energy fetch is older than this. LG's
    /// numbers move slowly (Home Assistant refreshes "today" hourly), and each fetch costs two
    /// requests of the shared quota.
    static let energyRefreshThreshold: Duration = .seconds(3600)

    // MARK: - Observable state

    private(set) var phase: Phase = .loadingProfile
    private(set) var device: DeviceSummary?
    private(set) var capabilities: AirConditionerCapabilities?
    /// The fetched state with any not-yet-confirmed commands applied on top (optimistic UI).
    private(set) var snapshot: AirConditionerSnapshot?
    /// When the last fetch *succeeded* (the footer's "Synced … ago").
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    /// Commands sent with `send(_:)` that are queued or in flight.
    private(set) var pendingCommands = 0
    /// Air conditioners on the account of the *saved* token, for the Settings device picker.
    private(set) var availableDevices: [DeviceSummary] = []
    /// Whether a token is saved (as of the last `start()` / `saveToken(_:)`).
    private(set) var hasToken = false
    /// The last command failure that did not change `phase` (e.g. LG rejected the value).
    /// Cleared by the next `send(_:)` or `dismissCommandFailure()`.
    private(set) var commandFailureMessage: String?
    /// The selected AC's energy use for Settings › Energy; `nil` until fetched. Kept while a
    /// refresh runs or fails; dropped when the device changes.
    private(set) var energy: EnergySummary?
    private(set) var isLoadingEnergy = false
    /// Why the last energy fetch failed; cleared by the next successful one. Energy failures
    /// never change `phase`.
    private(set) var energyFailureMessage: String?
    /// ACs whose energy profile said they report no energy, remembered for this run of the app.
    private(set) var energyUnsupportedDeviceIDs: Set<String> = []

    // MARK: - Dependencies

    @ObservationIgnored private let makeClient: ClientFactory
    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let clock: any StoreClock
    /// LG's energy dates are Gregorian days and months in the user's time zone
    /// (`EnergySummary.calendar()`).
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let logger = Logger(subsystem: "com.vinicius.Breeze", category: "store")

    // MARK: - Session (reset by stop())

    /// Bumped by `stop()`; async work compares it to the value it started with.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var client: (any ThinQAPI)?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var commandContinuation: AsyncStream<QueuedCommand>.Continuation?
    @ObservationIgnored private var postBurstRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var deviceDelayRetryTask: Task<Void, Never>?
    @ObservationIgnored private var energyTask: Task<Void, Never>?
    /// Set when polling must wait for the user (token invalid, no AC, unsupported profile/country).
    /// Observed (like `rateLimitedUntil`) so `canRefreshEnergy` updates the Energy tab.
    private var isPollingHalted = false
    @ObservationIgnored private var schedule = PollSchedule()
    /// End of the current 1306 back-off. No automatic request goes out before it.
    private var rateLimitedUntil: Date?
    /// When the last fetch finished, successfully or not (limits panel-open refreshes).
    @ObservationIgnored private var lastSyncAttempt: Date?
    /// When the last energy fetch for the selected device finished, successfully or not (the
    /// 1 h gate, so a failing Energy API isn't asked again on every tab switch).
    @ObservationIgnored private var lastEnergyAttempt: Date?
    /// The energy property to request per device (`energyUsage` on ACs), so the energy profile
    /// is asked once per device and run of the app.
    @ObservationIgnored private var energyPropertyByDevice: [String: String] = [:]

    // MARK: - Device state model

    /// The last state LG returned.
    @ObservationIgnored private var fetchedState: DeviceState?
    /// Commands applied on top of `fetchedState`, in send order, until a fetch reconciles them.
    @ObservationIgnored private var optimisticCommands: [OptimisticCommand] = []
    /// Source of `OptimisticCommand.id`.
    @ObservationIgnored private var nextOptimisticID = 0
    /// `.targetTemperature` / `.sleepTimer` commands still queued per slot, for coalescing slider
    /// spam and repeated sleep picks.
    @ObservationIgnored private var queuedSetpoints: [SetpointSlot: Int] = [:]
    /// The last sleep-timer write LG accepted, applied under `optimisticCommands` until the
    /// lagging state catches up (`HeldSleepTimer`).
    @ObservationIgnored private var heldSleepTimer: HeldSleepTimer?
    @ObservationIgnored private var lastPostAt: Date?

    init(
        makeClient: @escaping ClientFactory,
        tokenStore: any TokenStore,
        settings: AppSettings,
        clock: any StoreClock,
        calendar: Calendar = EnergySummary.calendar()
    ) {
        self.makeClient = makeClient
        self.tokenStore = tokenStore
        self.settings = settings
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: - Lifecycle

    /// Loads the token; without one the phase becomes `.needsSetup`. Otherwise loads devices,
    /// profile and state (returns when that first sync finished, successfully or not) and starts
    /// the poll loop and the command queue. Does nothing if already started.
    func start() async {
        guard client == nil else { return }
        guard let token = loadToken() else { return }

        client = makeClient(configuration(token: token))
        phase = .loadingProfile
        openCommandQueue()

        // The first sync runs as `refreshTask`, so ⌘R or a panel open meanwhile joins it.
        let session = self.session
        await refresh()
        guard isCurrent(session) else { return }
        startPolling(session: session)
    }

    /// Cancels polling, the command queue and in-flight fetches. Keeps the last snapshot.
    func stop() {
        session += 1
        pollTask?.cancel()
        refreshTask?.cancel()
        cancelPostBurstRefresh()
        deviceDelayRetryTask?.cancel()
        energyTask?.cancel()
        commandTask?.cancel()
        commandContinuation?.finish()
        pollTask = nil
        refreshTask = nil
        deviceDelayRetryTask = nil
        energyTask = nil
        isLoadingEnergy = false
        commandTask = nil
        commandContinuation = nil
        client = nil
        isPollingHalted = false
        isSyncing = false
        pendingCommands = 0
        queuedSetpoints.removeAll()
        optimisticCommands.removeAll()
        heldSleepTimer = nil
        recomputeSnapshot()
    }

    /// Call after the token, country or selected device changed: stops everything, forgets the
    /// device, rebuilds the client from the current settings and starts again.
    func reconfigure() async {
        stop()
        device = nil
        capabilities = nil
        fetchedState = nil
        snapshot = nil
        lastSync = nil
        lastSyncAttempt = nil
        rateLimitedUntil = nil
        commandFailureMessage = nil
        energy = nil
        energyFailureMessage = nil
        lastEnergyAttempt = nil
        schedule.recordSuccess()
        // No phase reset needed: `start()` sets the phase before its first suspension.
        await start()
    }

    // MARK: - Refreshing

    /// Fetches the state once (or retries the initial load if it failed). Concurrent calls
    /// share one request; this also runs the first load started by `start()`, so ⌘R or a panel
    /// open during start-up joins that load. This is also the user's ⌘R, so it is allowed inside
    /// a rate-limit window; automatic callers check `isInsideRateLimitWindow` first. A 1306
    /// inside the window does not extend the back-off (`applyPhaseAffectingFailure`).
    func refresh() async {
        await fetch(isDeviceDelayRetry: false)
    }

    /// The body of `refresh()`. Concurrent calls share one request, and a call that joins one
    /// ignores `isDeviceDelayRetry`.
    private func fetch(isDeviceDelayRetry: Bool) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        guard client != nil, !isPollingHalted else { return }

        let session = self.session
        let task = Task {
            await self.sync(session: session, isDeviceDelayRetry: isDeviceDelayRetry)
            if self.isCurrent(session) {
                self.refreshTask = nil
            }
        }
        refreshTask = task
        await task.value
    }

    /// Refreshes when the last sync is older than 15 s, so opening the panel shows fresh state
    /// without spending quota on every click.
    func panelDidAppear() async {
        guard shouldRefreshOnPanelOpen else { return }
        await refresh()
    }

    /// Nothing to do: polling keeps its own pace and costs nothing between polls.
    func panelDidDisappear() {}

    /// Call after `AppSettings.pollIntervalSeconds` changed. The poll loop may be in a sleep of up
    /// to 10 minutes on the old interval; this replaces it with a wait for what is left of the
    /// new interval since the last fetch. A rate-limit back-off stays in place.
    func pollIntervalDidChange() {
        // Not polling yet (first sync running) or halted: start()/reconfigure() start the loop.
        guard pollTask != nil else { return }
        restartPolling(session: session, firstDelay: remainingPollDelay())
    }

    // MARK: - Commands

    /// Applies `command` to the snapshot immediately and queues it for the AC. Invalid commands
    /// (e.g. a temperature outside the model's range) are rejected here without touching state;
    /// a setpoint equal to the current one, or a sleep-timer cancel while the AC is off, is
    /// ignored (it would only spend quota).
    func send(_ command: ACCommand) {
        guard let caps = capabilities, let current = snapshot, let continuation = commandContinuation, !isPollingHalted else {
            logger.debug("Ignoring command \(String(describing: command), privacy: .public): store not ready")
            return
        }
        do {
            _ = try command.payload(for: caps, currentMode: current.mode)
        } catch {
            logger.error("Rejected command \(String(describing: command), privacy: .public): \(error.description, privacy: .public)")
            commandFailureMessage = Self.unsupportedSettingMessage
            return
        }
        if Self.isNoOpSetpoint(command, current: current, caps: caps) {
            logger.debug("Ignoring command \(String(describing: command), privacy: .public): already the target")
            return
        }
        if Self.isSkippedSleepTimerCancel(command, power: current.power) {
            logger.debug("Ignoring command \(String(describing: command), privacy: .public): the AC is off")
            return
        }

        commandFailureMessage = nil
        pendingCommands += 1
        cancelPostBurstRefresh()

        if Self.requiresPowerOn(command), current.power == .off {
            // The queue will turn the AC on first; show it on right away.
            appendOptimistic(.power(.on), isImplicitPowerOn: true)
        }
        // The implicit power-on does not change the mode, so `current.mode` is still the mode
        // this command runs in.
        let slot = Self.setpointSlot(for: command, caps: caps, mode: current.mode)
        if let slot {
            queuedSetpoints[slot, default: 0] += 1
        }
        let id = appendOptimistic(command, isImplicitPowerOn: false)
        recomputeSnapshot()
        continuation.yield(QueuedCommand(
            id: id,
            command: command,
            mode: current.mode,
            setpointSlot: slot
        ))
    }

    func dismissCommandFailure() {
        commandFailureMessage = nil
    }

    // MARK: - Settings support

    /// Calls `devices()` with `token` (or the saved token when `nil` / blank) without saving
    /// anything. Only a test of the *saved* token refreshes `availableDevices`; a typed token
    /// just reports the result, so the Device tab never lists another account's devices.
    func testConnection(token candidate: String? = nil) async -> ConnectionTestResult {
        let trimmedCandidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let usesSavedToken = trimmedCandidate.isEmpty
        let token: String
        if usesSavedToken {
            do {
                guard let stored = try tokenStore.token(), !stored.isEmpty else { return .missingToken }
                token = stored
            } catch {
                logger.error("Keychain read failed: \(error.description, privacy: .public)")
                return .failed(Self.keychainMessage(for: error))
            }
        } else {
            token = trimmedCandidate
        }

        let session = self.session
        let client = makeClient(configuration(token: token))
        do throws(ThinQError) {
            let airConditioners = try await client.devices().filter(\.isAirConditioner)
            // A slow answer that lands after `reconfigure()` must not overwrite the list the new
            // session loaded.
            if usesSavedToken, isCurrent(session) {
                availableDevices = airConditioners
            }
            return airConditioners.isEmpty ? .noAirConditioners : .success(airConditioners: airConditioners.count)
        } catch {
            logger.error("Connection test failed: \(error.description, privacy: .public)")
            return Self.connectionTestResult(for: error)
        }
    }

    /// Refreshes `availableDevices` with the saved token (Settings › Device).
    @discardableResult
    func loadDevices() async -> ConnectionTestResult {
        await testConnection(token: nil)
    }

    /// `availableDevices` as the UI names them: local nicknames first, colliding names marked.
    /// Reads `AppSettings.deviceNicknames`, so views using it update
    /// when a nickname changes.
    var deviceLabels: [DeviceLabel] {
        DeviceLabel.labels(for: availableDevices, nicknames: settings.deviceNicknames)
    }

    /// The selected device's label; `nil` before a device is chosen.
    var deviceLabel: DeviceLabel? {
        guard let device else { return nil }
        if let label = deviceLabels.first(where: { $0.id == device.id }) {
            return label
        }
        // `availableDevices` no longer lists it (e.g. a list refresh dropped it); name it alone.
        return DeviceLabel.labels(for: [device], nicknames: settings.deviceNicknames).first
    }

    /// What `deviceID` reports right now, for Settings › Device's "which one is this?" preview.
    /// Never touches the selected device's snapshot. The selected device answers from that
    /// snapshot (no request); any other AC costs one state GET. Nothing is sent without a
    /// client, with a rejected token or inside a 1306 back-off; a 1306 here opens the back-off
    /// like any other request (the quota is per account), other failures leave `phase` alone.
    /// An answer that lands after a device switch is still returned: it never touches the
    /// store, and the Device tab doesn't ask again (its task is keyed on the unchanged list).
    func statePreview(for deviceID: String) async -> DevicePreview {
        if deviceID == device?.id, let snapshot {
            return phase == .offline
                ? .offline
                : .reported(power: snapshot.power, roomTemperature: snapshot.currentTemperature)
        }
        guard let client, phase != .tokenInvalid, !isInsideRateLimitWindow else { return .unavailable }

        let session = self.session
        do throws(ThinQError) {
            let state = try await client.state(deviceID: deviceID)
            return DevicePreview(state: state)
        } catch {
            // After a session change or a closed tab (cancelled task) the error is still shown
            // as is, but it must not open a back-off in the new session.
            if isCurrent(session), !Task.isCancelled {
                logger.error("State preview failed: \(error.description, privacy: .public)")
                if error.isRateLimited, !isPollingHalted {
                    recordRateLimit()
                }
            }
            return error.isDeviceOffline ? .offline : .unavailable
        }
    }

    // MARK: - Energy

    /// Whether the selected AC's energy profile said it reports no energy.
    var isEnergyUnsupported: Bool {
        guard let device else { return false }
        return energyUnsupportedDeviceIDs.contains(device.id)
    }

    /// Whether `refreshEnergy()` would ask LG now (Settings › Energy's Refresh button).
    var canRefreshEnergy: Bool {
        client != nil && device != nil && !isPollingHalted && !isEnergyUnsupported && !isInsideRateLimitWindow
    }

    /// Settings › Energy appeared: fetches when the last energy fetch for this device is older
    /// than `energyRefreshThreshold`, or the summary is from an earlier day (its "Today" and,
    /// on the 1st, its month tiles would show the previous period). The only automatic energy
    /// fetch — never at launch or in the poll loop.
    func energyTabDidAppear() async {
        let now = clock.now
        let isSummaryFromToday = energy.map { calendar.isDate($0.fetchedAt, inSameDayAs: now) } ?? true
        if let lastEnergyAttempt, isSummaryFromToday,
           now.timeIntervalSince(lastEnergyAttempt) < Self.energyRefreshThreshold.timeInterval {
            return
        }
        await refreshEnergy()
    }

    /// Fetches the selected AC's energy use now: the energy profile (once per device), then
    /// MONTHLY for the last 12 months and DAILY for the last 30 days. Concurrent calls share one
    /// fetch, which keeps running when the tab closes (its result is cached). Nothing is sent
    /// without a device, with a halted store, for an unsupported device or inside a 1306
    /// back-off. Failures, a 1306 included, only set `energyFailureMessage`: they never change
    /// `phase`.
    func refreshEnergy() async {
        if let energyTask {
            await energyTask.value
            return
        }
        guard canRefreshEnergy, let client, let device else { return }

        let session = self.session
        let task = Task {
            await self.loadEnergy(client: client, deviceID: device.id, session: session)
            if self.isCurrent(session) {
                self.energyTask = nil
            }
        }
        energyTask = task
        await task.value
    }

    private func loadEnergy(client: any ThinQAPI, deviceID: String, session: Int) async {
        // Gotcha: this task starts after `refreshEnergy()` created it, so a `stop()` may already
        // have run; setting the flag then would leave it stuck for the new session.
        guard isCurrent(session) else { return }
        isLoadingEnergy = true
        defer {
            if isCurrent(session) {
                isLoadingEnergy = false
                lastEnergyAttempt = clock.now
            }
        }

        do throws(ThinQError) {
            guard let property = try await energyProperty(client: client, deviceID: deviceID, session: session) else { return }
            let now = clock.now
            let monthRange = EnergySummary.monthRange(endingAt: now, calendar: calendar)
            let months = try await client.energyUsage(
                deviceID: deviceID, property: property, period: .monthly, from: monthRange.from, to: monthRange.to
            )
            guard isCurrent(session) else { return }
            let dayRange = EnergySummary.dayRange(endingAt: now, calendar: calendar)
            let days = try await client.energyUsage(
                deviceID: deviceID, property: property, period: .daily, from: dayRange.from, to: dayRange.to
            )
            guard isCurrent(session) else { return }
            energy = EnergySummary(months: months, days: days, fetchedAt: now, calendar: calendar)
            energyFailureMessage = nil
        } catch {
            guard isCurrent(session) else { return }
            logger.error("Energy fetch failed: \(error.description, privacy: .public)")
            if Self.meansEnergyUnsupported(error) {
                energyUnsupportedDeviceIDs.insert(deviceID)
            } else {
                energyFailureMessage = Self.energyFailureMessage(for: error)
            }
        }
    }

    /// The cached property, else the one the energy profile lists. `nil` (after remembering the
    /// device as unsupported) when the list is empty, or when the session ended meanwhile.
    private func energyProperty(client: any ThinQAPI, deviceID: String, session: Int) async throws(ThinQError) -> String? {
        if let cached = energyPropertyByDevice[deviceID] {
            return cached
        }
        let properties = try await client.energyProperties(deviceID: deviceID)
        guard isCurrent(session) else { return nil }
        guard let property = EnergySummary.usageProperty(from: properties) else {
            logger.notice("The energy profile lists no property; energy is unsupported on this device")
            energyUnsupportedDeviceIDs.insert(deviceID)
            return nil
        }
        energyPropertyByDevice[deviceID] = property
        return property
    }

    /// 1220 property / 1221 product not supported, and 1307: the account's country works for
    /// control (or polling would have halted), so here it means energy isn't offered there.
    private static func meansEnergyUnsupported(_ error: ThinQError) -> Bool {
        switch error.apiCode {
        case .notSupportedFeature?, .notSupportedProduct?, .notSupportedCountry?: true
        default: false
        }
    }

    private static func energyFailureMessage(for error: ThinQError) -> String {
        if error.isRateLimited {
            return String(localized: "LG ThinQ is limiting requests right now. Try again later.")
        }
        return error.userMessage
    }

    /// Persists the choice and restarts with that device.
    func selectDevice(id: String) async {
        guard id != device?.id || settings.selectedDeviceID != id else { return }
        settings.selectedDeviceID = id
        await reconfigure()
    }

    /// Saves the PAT (trimmed) to the Keychain and restarts. An empty token removes it.
    /// Returns `false` when the Keychain write failed.
    @discardableResult
    func saveToken(_ token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try tokenStore.deleteToken()
            } else {
                try tokenStore.setToken(trimmed)
            }
        } catch {
            logger.error("Keychain write failed: \(error.description, privacy: .public)")
            return false
        }
        await reconfigure()
        return true
    }

    /// Deletes the PAT and returns to `.needsSetup`.
    @discardableResult
    func removeToken() async -> Bool {
        await saveToken("")
    }

    // MARK: - Session plumbing

    private func isCurrent(_ session: Int) -> Bool {
        session == self.session
    }

    /// Reads the PAT. Sets `.needsSetup` (no token) or `.error` (Keychain failure) and returns nil.
    /// Either way the device list of the previous token is dropped.
    private func loadToken() -> String? {
        let token: String?
        do {
            token = try tokenStore.token()
        } catch {
            logger.error("Keychain read failed: \(error.description, privacy: .public)")
            hasToken = false
            availableDevices = []
            phase = .error(Self.keychainMessage(for: error))
            return nil
        }
        guard let token, !token.isEmpty else {
            hasToken = false
            availableDevices = []
            phase = .needsSetup
            return nil
        }
        hasToken = true
        return token
    }

    private func configuration(token: String) -> ThinQConfiguration {
        ThinQConfiguration(accessToken: token, countryCode: settings.countryCode, clientID: settings.clientID)
    }

    /// Stops polling until `reconfigure()`, e.g. when the token was rejected.
    private func halt(with phase: Phase) {
        self.phase = phase
        isPollingHalted = true
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Polling

    /// `firstDelay` replaces the first sleep (used when the interval changes mid-wait).
    private func startPolling(session: Int, firstDelay: Duration? = nil) {
        guard !isPollingHalted, pollTask == nil else { return }
        pollTask = Task { await self.pollLoop(session: session, firstDelay: firstDelay) }
    }

    /// Ends the current loop and starts a new one. Safe even while the old loop awaits
    /// `refresh()`: awaiting a task's `value` doesn't forward cancellation to the shared refresh,
    /// and the old loop checks `Task.isCancelled` before sleeping again, so only one loop remains.
    private func restartPolling(session: Int, firstDelay: Duration?) {
        pollTask?.cancel()
        pollTask = nil
        startPolling(session: session, firstDelay: firstDelay)
    }

    /// One loop for the whole session: sleep the current interval (re-read from settings each
    /// time, doubled while rate limited), then refresh. No Timer, no RunLoop source.
    private func pollLoop(session: Int, firstDelay: Duration?) async {
        var delay = firstDelay
        while isCurrent(session), !isPollingHalted, !Task.isCancelled {
            do {
                try await clock.sleep(for: delay ?? currentPollInterval)
                delay = nil
                try await sleepThroughRateLimitWindow()
            } catch {
                return  // cancelled by stop() / halt / restartPolling
            }
            guard !Task.isCancelled, isCurrent(session), !isPollingHalted else { return }
            await refresh()
        }
    }

    /// Gotcha: a 1306 from another request (a command, a panel-open refresh) opens the window
    /// while this loop is already asleep on the old interval. Waking inside the window would
    /// spend quota LG just refused, so keep sleeping until `rateLimitedUntil`; polling then
    /// resumes exactly at the time the footer shows.
    private func sleepThroughRateLimitWindow() async throws {
        while let until = rateLimitedUntil, clock.now < until {
            try await clock.sleep(for: .seconds(until.timeIntervalSince(clock.now)))
        }
    }

    /// The configured interval (re-read from settings), or the 1306 back-off while one is active.
    private var currentPollInterval: Duration {
        schedule.interval(base: settings.pollInterval)
    }

    /// What is left of the current interval since the last fetch attempt (0 when overdue).
    private func remainingPollDelay() -> Duration {
        let interval = currentPollInterval
        guard let reference = lastSyncAttempt else { return interval }
        let remaining = interval.timeInterval - clock.now.timeIntervalSince(reference)
        return .seconds(max(0, remaining))
    }

    private var isInsideRateLimitWindow: Bool {
        guard let rateLimitedUntil else { return false }
        return clock.now < rateLimitedUntil
    }

    /// Compares with the last *attempt*, not the last success: while the AC is offline or the
    /// network is down, `lastSync` stays old and every panel open would otherwise send a request.
    private var shouldRefreshOnPanelOpen: Bool {
        guard client != nil, !isPollingHalted, !isInsideRateLimitWindow else { return false }
        guard let reference = lastSyncAttempt else { return true }
        return clock.now.timeIntervalSince(reference) >= Self.panelRefreshThreshold.timeInterval
    }

    // MARK: - Syncing

    /// Loads the device and profile if not loaded yet, then fetches the state.
    /// `isDeviceDelayRetry`: this is the 2209 retry, so a second 2209 is reported, not retried.
    private func sync(session: Int, isDeviceDelayRetry: Bool) async {
        guard let client else { return }
        isSyncing = true
        defer {
            if isCurrent(session) {
                isSyncing = false
                lastSyncAttempt = clock.now
            }
        }

        do throws(ThinQError) {
            if capabilities == nil {
                guard try await loadDeviceAndProfile(client: client, session: session) else { return }
            }
            guard let device else { return }
            let state = try await client.state(deviceID: device.id)
            guard isCurrent(session) else { return }
            didFetch(state)
        } catch {
            guard isCurrent(session) else { return }
            logger.error("Sync failed: \(error.description, privacy: .public)")
            // A command POST may have halted the store (1103 / 1307) while this request was in
            // flight; keep the halt phase so the panel shows why nothing works.
            guard !isPollingHalted else { return }
            if error.apiCode == .deviceResponseDelay, !isDeviceDelayRetry {
                // 2209: the AC was slow to answer LG (typical right after a command). Keep what
                // the panel shows and try once more shortly.
                scheduleDeviceDelayRetry(session: session)
                return
            }
            if !applyPhaseAffectingFailure(error) {
                phase = .error(error.userMessage)
            }
        }
    }

    /// Picks the device and derives capabilities. Returns false (after setting the phase) when
    /// there is nothing usable, or when the session ended meanwhile.
    private func loadDeviceAndProfile(client: any ThinQAPI, session: Int) async throws(ThinQError) -> Bool {
        let devices = try await client.devices()
        guard isCurrent(session) else { return false }
        availableDevices = devices.filter(\.isAirConditioner)
        guard let device = chooseDevice(from: availableDevices) else {
            logger.error("No air conditioner on this account")
            halt(with: .error(String(localized: "No air conditioner was found in this ThinQ account.")))
            return false
        }
        self.device = device

        let profile = try await client.profile(deviceID: device.id)
        guard isCurrent(session) else { return false }
        do {
            capabilities = try AirConditionerCapabilities(profile: profile)
            return true
        } catch {
            logger.error("Unsupported profile: \(error.description, privacy: .public)")
            halt(with: .error(String(localized: "This air conditioner's profile isn't supported by Breeze.")))
            return false
        }
    }

    /// The saved device if it is still on the account, else the first air conditioner (which
    /// is then persisted so the choice is stable).
    private func chooseDevice(from airConditioners: [DeviceSummary]) -> DeviceSummary? {
        if let savedID = settings.selectedDeviceID, let saved = airConditioners.first(where: { $0.id == savedID }) {
            return saved
        }
        guard let first = airConditioners.first else { return nil }
        if settings.selectedDeviceID != nil {
            logger.error("The selected device is not on this account; falling back to the first air conditioner")
        }
        settings.selectedDeviceID = first.id
        return first
    }

    /// Stores a fetched state. Optimistic commands are dropped (the fetched state wins) only
    /// when no command is queued or in flight and no post-burst refresh is pending; otherwise
    /// they stay applied on top, so the UI does not flicker back to the old values while LG
    /// catches up. Gotcha: this also covers a send *during* this fetch, because every fetch runs
    /// as `refreshTask`, and such a send keeps `pendingCommands > 0` or `postBurstRefreshTask`
    /// set until this fetch has landed (`schedulePostBurstRefresh` waits for `refreshTask`).
    /// A held sleep timer outlives quiet fetches until the state agrees or it expires.
    private func didFetch(_ state: DeviceState) {
        fetchedState = state
        let isQuiet = pendingCommands == 0 && postBurstRefreshTask == nil
        if isQuiet {
            optimisticCommands.removeAll()
        }
        releaseHeldSleepTimerIfSettled(by: state)
        recomputeSnapshot()
        lastSync = clock.now
        rateLimitedUntil = nil
        schedule.recordSuccess()
        // A command POST may have halted the store (1103 / 1307) while this GET was in flight;
        // keep the halt phase so the panel shows why nothing works.
        guard !isPollingHalted else { return }
        phase = .ready
    }

    private func recomputeSnapshot() {
        let updated = projectedSnapshot(applying: optimisticCommands)
        if updated != snapshot {
            snapshot = updated
        }
    }

    /// `fetchedState` with the held sleep timer and then `entries` applied; nil before the first
    /// fetch.
    private func projectedSnapshot(applying entries: some Sequence<OptimisticCommand>) -> AirConditionerSnapshot? {
        guard let caps = capabilities, var state = fetchedState else { return nil }
        heldSleepTimer?.command.apply(to: &state, caps: caps)
        for entry in entries {
            entry.command.apply(to: &state, caps: caps)
        }
        return AirConditionerSnapshot(state: state, capabilities: caps)
    }

    /// Drops the held sleep timer once `state` shows it or it has waited `HeldSleepTimer.stateLag`.
    private func releaseHeldSleepTimerIfSettled(by state: DeviceState) {
        guard let held = heldSleepTimer, let caps = capabilities else { return }
        let reported = AirConditionerSnapshot(state: state, capabilities: caps).sleepTimer
        if held.hasExpired(at: clock.now) || held.isReflected(by: reported, at: clock.now) {
            heldSleepTimer = nil
        }
    }

    /// Token / quota / offline errors change the phase whatever request hit them. Returns
    /// whether `error` was one of those.
    private func applyPhaseAffectingFailure(_ error: ThinQError) -> Bool {
        if error.isTokenInvalid {
            halt(with: .tokenInvalid)
        } else if error.isRateLimited {
            recordRateLimit()
        } else if error.isDeviceOffline {
            phase = .offline
        } else if error.apiCode == .notSupportedCountry {
            halt(with: .error(error.userMessage))
        } else {
            return false
        }
        return true
    }

    /// Doubles the back-off once per quota event: another 1306 inside the open window (⌘R, a
    /// command already queued) keeps the deadline instead of doubling again.
    private func recordRateLimit() {
        if let until = rateLimitedUntil, clock.now < until {
            phase = .rateLimited(until: until)
            return
        }
        let interval = schedule.recordRateLimit(base: settings.pollInterval)
        let until = clock.now.addingTimeInterval(interval.timeInterval)
        rateLimitedUntil = until
        phase = .rateLimited(until: until)
    }

    /// Fetches once more `deviceResponseDelayRetry` after a 2209. The retry's own 2209 is
    /// reported (`fetch(isDeviceDelayRetry: true)`), so a device that keeps timing out costs one
    /// extra request, not a loop. Joining a fetch that was already running leaves that fetch's
    /// own 2209 retryable.
    private func scheduleDeviceDelayRetry(session: Int) {
        guard deviceDelayRetryTask == nil else { return }
        deviceDelayRetryTask = Task {
            guard await self.sleepUnlessStopped(for: Self.deviceResponseDelayRetry, session: session) else { return }
            self.deviceDelayRetryTask = nil
            guard !self.isInsideRateLimitWindow else { return }
            await self.fetch(isDeviceDelayRetry: true)
        }
    }

    /// Sleeps on the store clock; false when cancelled or the session ended meanwhile, so the
    /// caller never touches a newer session or task. Gotcha: a cancelled task can still wake
    /// from a sleep that already finished, hence the explicit `isCancelled` check.
    private func sleepUnlessStopped(for duration: Duration, session: Int) async -> Bool {
        do {
            try await clock.sleep(for: duration)
        } catch {
            return false
        }
        return !Task.isCancelled && isCurrent(session)
    }

    // MARK: - Command queue

    /// One consumer task per session drains the stream in order.
    private func openCommandQueue() {
        let (stream, continuation) = AsyncStream.makeStream(of: QueuedCommand.self)
        commandContinuation = continuation
        let session = self.session
        commandTask = Task {
            for await queued in stream {
                guard self.isCurrent(session) else { return }
                await self.execute(queued, session: session)
                guard self.isCurrent(session) else { return }
                self.pendingCommands -= 1
                if self.pendingCommands == 0 {
                    self.schedulePostBurstRefresh(session: session)
                }
            }
        }
    }

    private func execute(_ queued: QueuedCommand, session: Int) async {
        if let slot = queued.setpointSlot {
            releaseSetpoint(slot)
        }
        // After a token-invalid / unsupported-country failure every further POST would fail the
        // same way; drop what is still queued instead of spending requests on it.
        guard !isPollingHalted else {
            discard(queued)
            return
        }
        guard await waitForCommandSlot(spacing: Self.minimumCommandSpacing, session: session) else { return }

        // Checked after the wait: setpoints for the same slot queued meanwhile supersede this
        // one, so a slider drag costs one POST every 3 s at most, always with the latest value.
        // Its implicit power-on entry stays (no flicker); the next executed command resolves it.
        if let slot = queued.setpointSlot, queuedSetpoints[slot, default: 0] > 0 {
            removeOptimistic(id: queued.id)
            return
        }
        // The AC may have been switched off after the cancel was sent (a superseded sleep pick
        // took its display-only power-on with it, or a fetch reported it off).
        if Self.isSkippedSleepTimerCancel(queued.command, power: expectedPower(before: queued)) {
            discard(queued)
            return
        }

        if Self.requiresPowerOn(queued.command), expectedPower(before: queued) == .off {
            let poweredOn = await post(.power(.on), mode: queued.mode, entryID: nil, session: session)
            guard isCurrent(session) else { return }
            guard poweredOn else {
                discard(queued)
                return
            }
            resolveImplicitPowerOns(through: queued, poweredOn: true)
            let settle = max(Self.minimumCommandSpacing, Self.powerOnSettleTime)
            guard await waitForCommandSlot(spacing: settle, session: session) else { return }
        } else {
            // No POWER_ON needed (the AC is on, or this is a power command): any display-only
            // power-on up to here is redundant or, for a power command, superseded.
            resolveImplicitPowerOns(through: queued, poweredOn: false)
            recomputeSnapshot()
        }
        await post(queued.command, mode: queued.mode, entryID: queued.id, session: session)
    }

    /// Drops a queued command that will not be POSTed, together with the display-only
    /// power-ons before it.
    private func discard(_ queued: QueuedCommand) {
        resolveImplicitPowerOns(through: queued, poweredOn: false)
        removeOptimistic(id: queued.id)
        recomputeSnapshot()
    }

    /// The AC's power just before `queued`, as the queue knows it: the fetched state plus the
    /// optimistic commands sent earlier, except display-only implicit power-ons (nothing was
    /// POSTed for them). The same source of truth as the snapshot `send(_:)` decided from, so a
    /// fetch reporting POWER_OFF mid-burst makes the queue send POWER_ON too. `nil` if unknown.
    private func expectedPower(before queued: QueuedCommand) -> ACPower? {
        let earlier = optimisticCommands
            .prefix { $0.id != queued.id }
            .filter { !$0.isImplicitPowerOn }
        return projectedSnapshot(applying: earlier)?.power
    }

    /// Settles every display-only power-on up to and including `queued`'s: they are dropped,
    /// and when a POWER_ON was just POSTed successfully a real `.power(.on)` entry takes their
    /// place right before the command. A failed or skipped POWER_ON therefore never leaves the
    /// panel showing the AC on.
    private func resolveImplicitPowerOns(through queued: QueuedCommand, poweredOn: Bool) {
        let end = optimisticCommands.firstIndex { $0.id == queued.id } ?? optimisticCommands.endIndex
        let implicitIDs = optimisticCommands[..<end].filter(\.isImplicitPowerOn).map(\.id)
        optimisticCommands.removeAll { implicitIDs.contains($0.id) }
        guard poweredOn else { return }
        let entry = OptimisticCommand(id: makeOptimisticID(), command: .power(.on), isImplicitPowerOn: false)
        if let index = optimisticCommands.firstIndex(where: { $0.id == queued.id }) {
            optimisticCommands.insert(entry, at: index)
        } else {
            optimisticCommands.append(entry)
        }
    }

    /// Sleeps until `spacing` has passed since the previous POST. False if the session ended.
    private func waitForCommandSlot(spacing: Duration, session: Int) async -> Bool {
        guard let lastPostAt else { return true }
        let remaining = spacing.timeInterval - clock.now.timeIntervalSince(lastPostAt)
        guard remaining > 0 else { return true }
        return await sleepUnlessStopped(for: .seconds(remaining), session: session)
    }

    /// POSTs one command, built for `mode` (the mode in effect when it was sent). Redundant
    /// power errors (2302/2304) count as success. On failure the optimistic entry `entryID` is
    /// removed and the error is surfaced. Returns success.
    @discardableResult
    private func post(_ command: ACCommand, mode: ACMode?, entryID: Int?, session: Int) async -> Bool {
        guard let client, let device, let caps = capabilities else { return false }

        let body: JSONObject
        do {
            body = try command.payload(for: caps, currentMode: mode)
        } catch {
            logger.error("Cannot build \(String(describing: command), privacy: .public): \(error.description, privacy: .public)")
            if let entryID { removeOptimistic(id: entryID) }
            commandFailureMessage = Self.unsupportedSettingMessage
            recomputeSnapshot()
            return false
        }

        let failure = await control(body, client: client, deviceID: device.id, session: session)
        guard isCurrent(session) else { return false }
        lastPostAt = clock.now

        if let failure, !command.isRedundant(failure) {
            logger.error("Command \(String(describing: command), privacy: .public) failed: \(failure.description, privacy: .public)")
            if let entryID {
                rollBack(entryID: entryID, of: command, after: failure)
            }
            if !applyPhaseAffectingFailure(failure) {
                commandFailureMessage = failure.userMessage
            }
            recomputeSnapshot()
            return false
        }
        if case .sleepTimer(let minutes) = command {
            // Replaces an earlier hold: LG's newest sleep write is the one that counts.
            heldSleepTimer = HeldSleepTimer(minutes: minutes, postedAt: clock.now)
        }
        return true
    }

    /// Removes a failed command's optimistic entry. A 2304 on a command that needs power means
    /// LG says the AC is off right now: record that in its place, so the panel shows it off and
    /// the next command sends POWER_ON first.
    private func rollBack(entryID: Int, of command: ACCommand, after failure: ThinQError) {
        guard Self.requiresPowerOn(command), failure.apiCode == .commandNotSupportedInPowerOff,
              let index = optimisticCommands.firstIndex(where: { $0.id == entryID })
        else {
            removeOptimistic(id: entryID)
            return
        }
        optimisticCommands[index] = OptimisticCommand(id: entryID, command: .power(.off), isImplicitPowerOn: false)
    }

    /// One control call, retried once after the 3 s spacing when LG answers 2210 RETRY_REQUEST.
    /// Returns the failure that counts, or nil on success.
    private func control(_ body: JSONObject, client: any ThinQAPI, deviceID: String, session: Int) async -> ThinQError? {
        let first = await attemptControl(body, client: client, deviceID: deviceID)
        guard let first, first.apiCode == .retryRequest, isCurrent(session) else { return first }
        logger.notice("LG asked to retry the command (2210); retrying once")
        lastPostAt = clock.now
        guard await waitForCommandSlot(spacing: Self.minimumCommandSpacing, session: session) else { return first }
        return await attemptControl(body, client: client, deviceID: deviceID)
    }

    private func attemptControl(_ body: JSONObject, client: any ThinQAPI, deviceID: String) async -> ThinQError? {
        do throws(ThinQError) {
            try await client.control(deviceID: deviceID, body: body)
            return nil
        } catch {
            return error
        }
    }

    /// Fetches the state `postBurstRefreshDelay` after the queue drained, to reconcile.
    private func schedulePostBurstRefresh(session: Int) {
        cancelPostBurstRefresh()
        postBurstRefreshTask = Task {
            guard await self.sleepUnlessStopped(for: Self.postBurstRefreshDelay, session: session) else { return }
            // Keep postBurstRefreshTask set while an in-flight fetch lands: send()/stop() can
            // still cancel us, and that fetch's didFetch is not treated as quiet (it may predate
            // the last POST). This wait is what keeps a fetch that overlapped a send from
            // counting as quiet (`didFetch`); dropping it brings the flicker back. Awaiting an
            // unstructured task does not observe our cancellation, hence the second check.
            if let inFlight = self.refreshTask {
                await inFlight.value
            }
            guard !Task.isCancelled, self.isCurrent(session) else { return }
            self.postBurstRefreshTask = nil
            // Inside a 1306 window the poll at `rateLimitedUntil` reconciles instead.
            guard !self.isInsideRateLimitWindow else { return }
            await self.refresh()
        }
    }

    private func cancelPostBurstRefresh() {
        postBurstRefreshTask?.cancel()
        postBurstRefreshTask = nil
    }

    // MARK: - Optimistic entries

    @discardableResult
    private func appendOptimistic(_ command: ACCommand, isImplicitPowerOn: Bool) -> Int {
        let id = makeOptimisticID()
        optimisticCommands.append(OptimisticCommand(id: id, command: command, isImplicitPowerOn: isImplicitPowerOn))
        return id
    }

    private func makeOptimisticID() -> Int {
        nextOptimisticID += 1
        return nextOptimisticID
    }

    private func removeOptimistic(id: Int) {
        optimisticCommands.removeAll { $0.id == id }
    }

    private func releaseSetpoint(_ slot: SetpointSlot) {
        let remaining = queuedSetpoints[slot, default: 0] - 1
        queuedSetpoints[slot] = remaining > 0 ? remaining : nil
    }

    // MARK: - Helpers

    private static func requiresPowerOn(_ command: ACCommand) -> Bool {
        switch command {
        // A cancel never turns the AC on: LG accepts it while off.
        case .power, .sleepTimer(minutes: nil): false
        case .mode, .fan, .targetTemperature, .powerSave, .verticalSwing, .horizontalSwing, .displayLight, .sleepTimer: true
        }
    }

    /// The setpoint a `.targetTemperature` writes in `mode`, or the one slot every `.sleepTimer`
    /// shares (a later pick, cancel included, replaces a queued one); `nil` for other commands.
    private static func setpointSlot(for command: ACCommand, caps: AirConditionerCapabilities, mode: ACMode?) -> SetpointSlot? {
        switch command {
        case .targetTemperature:
            guard let key = caps.temperature.writeKey(for: mode)?.key else { return nil }
            return SetpointSlot(key: key, mode: mode)
        case .sleepTimer:
            return SetpointSlot(key: "sleepTimer", mode: nil)
        case .power, .mode, .fan, .powerSave, .verticalSwing, .horizontalSwing, .displayLight:
            return nil
        }
    }

    /// A setpoint equal to the (optimistic) target while the AC is on: e.g. ↑ at the range's
    /// maximum, or a slider drag that ends where it started. Compared with the unclamped state
    /// value, so a target reported outside the range (31 with a maximum of 30) is still fixed.
    private static func isNoOpSetpoint(_ command: ACCommand, current: AirConditionerSnapshot, caps: AirConditionerCapabilities) -> Bool {
        guard case .targetTemperature(let value) = command,
              current.power == .on,
              let target = current.targetTemperature?.converted(to: caps.temperature.unit).value
        else { return false }
        return abs(target - value) < setpointTolerance
    }

    private static let setpointTolerance = 1e-6

    /// A sleep-timer cancel while the AC is off: an off AC runs no timer worth cancelling, and a
    /// cancel never powers the AC on, so the POST is skipped.
    private static func isSkippedSleepTimerCancel(_ command: ACCommand, power: ACPower?) -> Bool {
        guard case .sleepTimer(minutes: nil) = command else { return false }
        return power == .off
    }

    private static func connectionTestResult(for error: ThinQError) -> ConnectionTestResult {
        if error.isTokenInvalid { return .tokenInvalid }
        if error.isRateLimited { return .rateLimited }
        if error.apiCode == .notSupportedCountry { return .unsupportedCountry }
        return .failed(error.userMessage)
    }

    private static func keychainMessage(for error: KeychainError) -> String {
        switch error {
        case .accessDenied:
            String(localized: "Breeze isn't allowed to read its Keychain item. Allow access when prompted, or delete the “com.vinicius.Breeze” item in Keychain Access and save the token again.")
        case .unexpectedStatus, .invalidData:
            String(localized: "Breeze couldn't read the token from the Keychain.")
        }
    }

    private static var unsupportedSettingMessage: String {
        String(localized: "This air conditioner doesn't support that setting.")
    }
}
