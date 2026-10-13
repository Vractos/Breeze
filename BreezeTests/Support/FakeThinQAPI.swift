import Foundation
@testable import Breeze
import ThinQKit

/// A scripted `ThinQAPI`. Records every call with the `ManualClock` time it arrived at.
/// Queued results are consumed first; when a queue is empty the default answer is used.
actor FakeThinQAPI: ThinQAPI {
    enum Call: Equatable, Sendable {
        case devices
        case profile(String)
        case state(String)
        case control(String, JSONObject)
        case energyProperties(String)
        case energyUsage(String, property: String, period: EnergyPeriod, from: DateComponents, to: DateComponents)
    }

    struct RecordedCall: Sendable {
        let call: Call
        let at: Date
    }

    private let clock: ManualClock
    private(set) var calls: [RecordedCall] = []

    var devices: [DeviceSummary]
    let profile: DeviceProfile
    /// Answered when no state result is queued; `setDefaultState(_:)` changes it.
    private(set) var defaultState: DeviceState
    private var queuedDevicesResults: [Result<[DeviceSummary], ThinQError>] = []
    private var queuedStateResults: [Result<DeviceState, ThinQError>] = []
    /// Fixed answers for specific devices, ahead of the queue (other ACs on the account).
    private var stateResultsByDevice: [String: Result<DeviceState, ThinQError>] = [:]
    private var queuedControlErrors: [ThinQError?] = []
    /// Energy answers; by default the canned data of the previews (`PreviewEnergy`).
    private var energyPropertiesResult: Result<[String], ThinQError> = .success(PreviewEnergy.properties)
    private var energyUsageResults: [EnergyPeriod: Result<[EnergyUsageEntry], ThinQError>] = [:]

    private var holdsStateRequests = false
    private var heldStateRequests: [CheckedContinuation<Void, Never>] = []

    init(clock: ManualClock, devices: [DeviceSummary], profile: DeviceProfile, state: DeviceState) {
        self.clock = clock
        self.devices = devices
        self.profile = profile
        defaultState = state
    }

    // MARK: Scripting

    func setDevices(_ devices: [DeviceSummary]) { self.devices = devices }
    func enqueueDevices(_ result: Result<[DeviceSummary], ThinQError>) { queuedDevicesResults.append(result) }
    func enqueueState(_ result: Result<DeviceState, ThinQError>) { queuedStateResults.append(result) }
    func setDefaultState(_ state: DeviceState) { defaultState = state }
    func setState(_ result: Result<DeviceState, ThinQError>, forDevice deviceID: String) { stateResultsByDevice[deviceID] = result }
    func enqueueControl(error: ThinQError?) { queuedControlErrors.append(error) }
    func setEnergyProperties(_ result: Result<[String], ThinQError>) { energyPropertiesResult = result }
    /// `nil` restores the canned data for `period`.
    func setEnergyUsage(_ result: Result<[EnergyUsageEntry], ThinQError>?, for period: EnergyPeriod) {
        energyUsageResults[period] = result
    }

    /// While on, `state()` suspends until `releaseHeldStateRequests()`.
    func holdStateRequests() { holdsStateRequests = true }

    func releaseHeldStateRequests() {
        holdsStateRequests = false
        let held = heldStateRequests
        heldStateRequests.removeAll()
        held.forEach { $0.resume() }
    }

    var heldStateRequestCount: Int { heldStateRequests.count }

    // MARK: Inspection

    var stateCallCount: Int {
        calls.filter { if case .state = $0.call { true } else { false } }.count
    }

    var controlCalls: [RecordedCall] {
        calls.filter { if case .control = $0.call { true } else { false } }
    }

    var energyCalls: [Call] {
        calls.map(\.call).filter {
            switch $0 {
            case .energyProperties, .energyUsage: true
            default: false
            }
        }
    }

    var controlBodies: [JSONObject] {
        controlCalls.compactMap { if case .control(_, let body) = $0.call { body } else { nil } }
    }

    // MARK: ThinQAPI

    func devices() async throws(ThinQError) -> [DeviceSummary] {
        record(.devices)
        if !queuedDevicesResults.isEmpty {
            return try queuedDevicesResults.removeFirst().get()
        }
        return devices
    }

    func profile(deviceID: String) async throws(ThinQError) -> DeviceProfile {
        record(.profile(deviceID))
        return profile
    }

    func state(deviceID: String) async throws(ThinQError) -> DeviceState {
        record(.state(deviceID))
        if holdsStateRequests {
            await withCheckedContinuation { heldStateRequests.append($0) }
        }
        if let fixed = stateResultsByDevice[deviceID] {
            return try fixed.get()
        }
        if !queuedStateResults.isEmpty {
            return try queuedStateResults.removeFirst().get()
        }
        return defaultState
    }

    func control(deviceID: String, body: JSONObject) async throws(ThinQError) {
        record(.control(deviceID, body))
        if !queuedControlErrors.isEmpty, let error = queuedControlErrors.removeFirst() {
            throw error
        }
    }

    func energyProperties(deviceID: String) async throws(ThinQError) -> [String] {
        record(.energyProperties(deviceID))
        return try energyPropertiesResult.get()
    }

    func energyUsage(
        deviceID: String,
        property: String,
        period: EnergyPeriod,
        from: DateComponents,
        to: DateComponents
    ) async throws(ThinQError) -> [EnergyUsageEntry] {
        record(.energyUsage(deviceID, property: property, period: period, from: from, to: to))
        if let result = energyUsageResults[period] {
            return try result.get()
        }
        return PreviewEnergy.usage(period: period, from: from, to: to)
    }

    private func record(_ call: Call) {
        calls.append(RecordedCall(call: call, at: clock.now))
    }
}
