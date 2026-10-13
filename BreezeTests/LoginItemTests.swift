import Foundation
import Testing
@testable import Breeze

@Suite("LoginItem")
@MainActor
struct LoginItemTests {
    private struct RegistrationFailure: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    @Test func initialStatusIsRead() {
        let loginItem = LoginItem(service: FakeLoginItemService(status: .enabled))

        #expect(loginItem.isEnabled)
    }

    @Test func enablingRegisters() throws {
        let service = FakeLoginItemService(status: .notRegistered)
        let loginItem = LoginItem(service: service)

        try loginItem.setEnabled(true)

        #expect(service.registerCount == 1)
        #expect(loginItem.status == .enabled)
    }

    @Test func approvalRequiredCountsAsEnabledAndOffersSystemSettings() throws {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let loginItem = LoginItem(service: service)

        try loginItem.setEnabled(true)
        loginItem.openSystemSettings()

        #expect(loginItem.isEnabled)
        #expect(loginItem.requiresApproval)
        #expect(service.openedSystemSettings)
    }

    @Test func failedRegistrationThrowsAndLeavesItOff() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = RegistrationFailure()
        let loginItem = LoginItem(service: service)

        #expect(throws: LoginItemError.registrationFailed("Operation not permitted")) {
            try loginItem.setEnabled(true)
        }
        #expect(!loginItem.isEnabled)
    }

    @Test func disablingUnregistersAndRedundantCallsDoNothing() throws {
        let service = FakeLoginItemService(status: .enabled)
        let loginItem = LoginItem(service: service)

        try loginItem.setEnabled(true)
        #expect(service.registerCount == 0)

        try loginItem.setEnabled(false)
        #expect(service.unregisterCount == 1)
        #expect(loginItem.status == .notRegistered)
    }

    @Test func refreshPicksUpChangesMadeInSystemSettings() {
        let service = FakeLoginItemService(status: .enabled)
        let loginItem = LoginItem(service: service)

        service.status = .notRegistered
        loginItem.refreshStatus()

        #expect(!loginItem.isEnabled)
    }
}
