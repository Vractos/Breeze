#if DEBUG
/// A login item for previews; never registers anything with the system.
final class PreviewLoginItemService: LoginItemService {
    private(set) var status: LoginItemStatus = .notRegistered

    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }
    func openSystemSettings() {}
}
#endif
