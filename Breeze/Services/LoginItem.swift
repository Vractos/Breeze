import Foundation
import Observation

/// "Launch at login", backed by `SMAppService.mainApp`.
///
/// The service's `status` is the only source of truth for on/off (the user can remove the item in
/// System Settings at any time). Call `refreshStatus()` when the Settings tab appears and whenever
/// the app becomes active again (the user approves the item in System Settings, another app).
///
/// Preferences only remember which copy of the app registered the item, so the installed copy can
/// take it over from an Xcode build (see `claimRegistrationIfInstalled()`).
@Observable
@MainActor
final class LoginItem {
    private static let registeredAppPathKey = "loginItemRegisteredAppPath"

    private(set) var status: LoginItemStatus

    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let appURL: URL

    /// - Parameter appURL: the running app's bundle (`Bundle.main.bundleURL`).
    init(service: any LoginItemService, defaults: UserDefaults, appURL: URL) {
        self.service = service
        self.defaults = defaults
        self.appURL = appURL
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
                recordRegistrationByThisCopy()
            } else {
                try service.unregister()
                defaults.removeObject(forKey: Self.registeredAppPathKey)
            }
        } catch {
            let reason = error.localizedDescription
            throw enabled ? .registrationFailed(reason) : .unregistrationFailed(reason)
        }
    }

    /// Makes the installed copy own an enabled login item. Call once at launch.
    ///
    /// Gotcha: `SMAppService.mainApp` registers the copy that calls `register()`, so an item turned
    /// on from an Xcode build would start that build at login. When this is the installed copy
    /// and another copy (or an unrecorded one) registered an `.enabled` item, register again from
    /// here; unregister first, because `register()` fails on an already registered item.
    ///
    /// `.requiresApproval` is left alone: it also means the user turned the item off in System
    /// Settings. Registering can post a "login item added" notification, hence once per copy.
    func claimRegistrationIfInstalled() throws(LoginItemError) {
        refreshStatus()
        guard status == .enabled,
              isInstalledCopy,
              defaults.string(forKey: Self.registeredAppPathKey) != appPath
        else { return }

        defer { refreshStatus() }
        do {
            try service.unregister()
        } catch {
            throw .unregistrationFailed(error.localizedDescription)
        }
        do {
            try service.register()
        } catch {
            throw .registrationFailed(error.localizedDescription)
        }
        recordRegistrationByThisCopy()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }

    /// True when this copy runs from `/Applications`, where the install script puts it.
    private var isInstalledCopy: Bool {
        Array(appURL.standardizedFileURL.pathComponents.dropLast()) == ["/", "Applications"]
    }

    private var appPath: String {
        appURL.standardizedFileURL.path(percentEncoded: false)
    }

    private func recordRegistrationByThisCopy() {
        defaults.set(appPath, forKey: Self.registeredAppPathKey)
    }
}
