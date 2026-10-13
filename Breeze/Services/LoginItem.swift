import Foundation
import Observation

/// "Launch at login", backed by `SMAppService.mainApp`.
///
/// The service's `status` is the only source of truth (the user can remove the item in System
/// Settings at any time), so nothing is stored in preferences. Call `refreshStatus()` when the
/// Settings tab appears and whenever the app becomes active again (the user approves the item in
/// System Settings, another app).
@Observable
@MainActor
final class LoginItem {
    private(set) var status: LoginItemStatus

    @ObservationIgnored private let service: any LoginItemService

    init(service: any LoginItemService) {
        self.service = service
        status = service.status
    }

    /// On for the toggle: registered, even if still waiting for the user's approval.
    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    /// Show a button that calls `openSystemSettings()`.
    var requiresApproval: Bool { status == .requiresApproval }

    func refreshStatus() {
        status = service.status
    }

    /// Registers or unregisters. On failure the status is re-read so the toggle snaps back.
    func setEnabled(_ enabled: Bool) throws(LoginItemError) {
        guard enabled != isEnabled else { return }
        defer { refreshStatus() }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let reason = error.localizedDescription
            throw enabled ? .registrationFailed(reason) : .unregistrationFailed(reason)
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
