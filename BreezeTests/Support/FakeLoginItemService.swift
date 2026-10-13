import Foundation
@testable import Breeze

@MainActor
final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    /// Status after a successful `register()`; `.requiresApproval` simulates the first time.
    var statusAfterRegister: LoginItemStatus = .enabled
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openedSystemSettings = false

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openedSystemSettings = true
    }
}
