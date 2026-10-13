/// The slice of `SMAppService.mainApp` that `LoginItem` needs; tests inject a fake.
@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}
