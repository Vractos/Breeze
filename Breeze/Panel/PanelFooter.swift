import SwiftUI

/// Sync status on the left; a menu with Refresh, Settings… and Quit Breeze on the right.
struct PanelFooter: View {
    let status: PanelStatus
    let isVisible: Bool
    let refresh: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PanelStatusView(status: status, isVisible: isVisible, openSettings: openSettings)
            Spacer(minLength: 8)
            menu
        }
    }

    private var menu: some View {
        Menu {
            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                .keyboardShortcut("r")
            Button("Settings…", systemImage: "gearshape", action: openSettings)
                .keyboardShortcut(",")
            Divider()
            Button("Quit Breeze", systemImage: "power", action: quit)
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More"))
        .help(Text("Refresh, Settings and Quit"))
    }
}
