import Foundation
import Testing
@testable import Breeze

@Suite("LoginItem")
@MainActor
struct LoginItemTests {
    private struct RegistrationFailure: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    private nonisolated static let installedApp = URL(filePath: "/Applications/Breeze.app", directoryHint: .isDirectory)
    private nonisolated static let xcodeBuild = URL(
        filePath: "/Users/someone/Library/Developer/Xcode/DerivedData/Breeze-abc/Build/Products/Debug/Breeze.app",
        directoryHint: .isDirectory
    )

    private let suiteName = "BreezeTests.LoginItem.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func makeLoginItem(
        _ service: FakeLoginItemService,
        defaults: UserDefaults,
        appURL: URL = Self.xcodeBuild
    ) -> LoginItem {
        LoginItem(service: service, defaults: defaults, appURL: appURL)
    }

    // MARK: - Toggle

    @Test func initialStatusIsRead() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let loginItem = makeLoginItem(FakeLoginItemService(status: .enabled), defaults: defaults)

        #expect(loginItem.isEnabled)
    }

    @Test func enablingRegisters() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notRegistered)
        let loginItem = makeLoginItem(service, defaults: defaults)

        try loginItem.setEnabled(true)

        #expect(service.registerCount == 1)
        #expect(loginItem.status == .enabled)
    }

    @Test func approvalRequiredCountsAsEnabledAndOffersSystemSettings() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let loginItem = makeLoginItem(service, defaults: defaults)

        try loginItem.setEnabled(true)
        loginItem.openSystemSettings()

        #expect(loginItem.isEnabled)
        #expect(loginItem.requiresApproval)
        #expect(service.openedSystemSettings)
    }

    @Test func failedRegistrationThrowsAndLeavesItOff() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = RegistrationFailure()
        let loginItem = makeLoginItem(service, defaults: defaults)

        #expect(throws: LoginItemError.registrationFailed("Operation not permitted")) {
            try loginItem.setEnabled(true)
        }
        #expect(!loginItem.isEnabled)
    }

    @Test func disablingUnregistersAndRedundantCallsDoNothing() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .enabled)
        let loginItem = makeLoginItem(service, defaults: defaults)

        try loginItem.setEnabled(true)
        #expect(service.registerCount == 0)

        try loginItem.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(loginItem.status == .notRegistered)
    }

    @Test func refreshPicksUpChangesMadeInSystemSettings() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .enabled)
        let loginItem = makeLoginItem(service, defaults: defaults)

        service.status = .notRegistered
        loginItem.refreshStatus()

        #expect(!loginItem.isEnabled)
    }

    // MARK: - Installed copy takes over the registration

    @Test func installedCopyReRegistersAnItemAnXcodeBuildRegistered() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notRegistered)
        try makeLoginItem(service, defaults: defaults, appURL: Self.xcodeBuild).setEnabled(true)

        let installed = makeLoginItem(service, defaults: defaults, appURL: Self.installedApp)
        try installed.claimRegistrationIfInstalled()

        #expect(service.unregisterCount == 1)
        #expect(service.registerCount == 2)
        #expect(installed.status == .enabled)
    }

    @Test func installedCopyReRegistersAnItemWithNoRecordedOwnerOnce() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .enabled)

        try makeLoginItem(service, defaults: defaults, appURL: Self.installedApp).claimRegistrationIfInstalled()
        try makeLoginItem(service, defaults: defaults, appURL: Self.installedApp).claimRegistrationIfInstalled()

        #expect(service.unregisterCount == 1)
        #expect(service.registerCount == 1)
    }

    @Test func installedCopyThatRegisteredItselfDoesNothing() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notRegistered)
        try makeLoginItem(service, defaults: defaults, appURL: Self.installedApp).setEnabled(true)

        try makeLoginItem(service, defaults: defaults, appURL: Self.installedApp).claimRegistrationIfInstalled()

        #expect(service.unregisterCount == 0)
        #expect(service.registerCount == 1)
    }

    @Test(arguments: [LoginItemStatus.notRegistered, .requiresApproval, .notFound])
    func installedCopyLeavesAnItemThatIsNotEnabledAlone(status: LoginItemStatus) throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: status)

        try makeLoginItem(service, defaults: defaults, appURL: Self.installedApp).claimRegistrationIfInstalled()

        #expect(service.unregisterCount == 0)
        #expect(service.registerCount == 0)
    }

    @Test(arguments: [
        xcodeBuild,
        URL(filePath: "/tmp/breeze-install-test/Breeze.app", directoryHint: .isDirectory),
        URL(filePath: "/Applications/Utilities/Breeze.app", directoryHint: .isDirectory),
    ])
    func copiesOutsideApplicationsNeverClaim(appURL: URL) throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .enabled)

        try makeLoginItem(service, defaults: defaults, appURL: appURL).claimRegistrationIfInstalled()

        #expect(service.unregisterCount == 0)
        #expect(service.registerCount == 0)
    }

    @Test func failedClaimThrowsAndShowsTheRealStatus() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .enabled)
        service.registerError = RegistrationFailure()
        let installed = makeLoginItem(service, defaults: defaults, appURL: Self.installedApp)

        #expect(throws: LoginItemError.registrationFailed("Operation not permitted")) {
            try installed.claimRegistrationIfInstalled()
        }
        #expect(installed.status == .notRegistered)
        #expect(!installed.isEnabled)
    }

    @Test func failedUnregisterDuringClaimIsReportedAsUnregistration() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .enabled)
        service.unregisterError = RegistrationFailure()
        let installed = makeLoginItem(service, defaults: defaults, appURL: Self.installedApp)

        #expect(throws: LoginItemError.unregistrationFailed("Operation not permitted")) {
            try installed.claimRegistrationIfInstalled()
        }
        #expect(service.registerCount == 0)
        #expect(defaults.string(forKey: "loginItemRegisteredAppPath") == nil)
        #expect(installed.status == .enabled)
    }

    @Test func turningItOffForgetsTheOwnerSoTheNextEnableIsClaimedAgain() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FakeLoginItemService(status: .notRegistered)
        let installed = makeLoginItem(service, defaults: defaults, appURL: Self.installedApp)
        try installed.setEnabled(true)
        try installed.setEnabled(false)

        // Re-enabled from an Xcode build: the installed copy takes it back on its next launch.
        try makeLoginItem(service, defaults: defaults, appURL: Self.xcodeBuild).setEnabled(true)
        try makeLoginItem(service, defaults: defaults, appURL: Self.installedApp).claimRegistrationIfInstalled()

        #expect(service.registerCount == 3)
        #expect(service.unregisterCount == 2)
    }
}
