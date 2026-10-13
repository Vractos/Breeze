import SwiftUI

/// The Settings window: Account, Device and General tabs at a fixed size.
struct SettingsView: View {
    static let size = CGSize(width: 500, height: 440)

    var body: some View {
        TabView {
            Tab("Account", systemImage: "person.crop.circle") {
                AccountSettingsView()
            }
            Tab("Device", systemImage: "air.conditioner.horizontal") {
                DeviceSettingsView()
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

#if DEBUG
#Preview("Settings", traits: .modifier(PreviewScenarioModifier(.ready))) {
    SettingsView()
}
#endif
