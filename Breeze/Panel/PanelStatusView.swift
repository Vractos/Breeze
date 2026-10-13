import SwiftUI

/// The footer's status line. Timers and animations run only while the panel is visible: the
/// relative "Synced … ago" ticks through a `TimelineView` that exists only then, and the syncing
/// arrow rotates only then (the panel also removes all symbol effects while closed).
struct PanelStatusView: View {
    let status: PanelStatus
    let isVisible: Bool
    let openSettings: () -> Void

    var body: some View {
        content
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .hidden:
            EmptyView()
        case .syncing:
            Label {
                Text("Syncing…")
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: isVisible)
            }
        case .synced(let date):
            if isVisible {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    syncedLabel(date, now: context.date)
                }
            } else {
                syncedLabel(date, now: .now)
            }
        case .offline:
            Label("AC offline", systemImage: "wifi.slash")
        case .rateLimited(let until):
            Label {
                Text("Rate limited, retrying at \(until, format: .dateTime.hour().minute())")
            } icon: {
                Image(systemName: "hourglass")
            }
        case .tokenInvalid:
            Button(action: openSettings) {
                Label("Token invalid — open Settings", systemImage: "key.slash")
            }
            .buttonStyle(.link)
        case .error(let message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        }
    }

    private func syncedLabel(_ date: Date, now: Date) -> some View {
        // Clamped so a sync stamped a moment "in the future" never reads "in 0 sec.".
        let relative = min(date, now).formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return Label {
            Text("Synced \(relative)")
        } icon: {
            Image(systemName: "checkmark.circle")
        }
    }
}
