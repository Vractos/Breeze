import SwiftUI
import ThinQKit

/// "On · 24 °C" / "Off · 27 °C" / "Offline": what an AC reports right now, so the user can match
/// a Settings row with the room they are in. A spinner while the request is out.
struct DevicePreviewLabel: View {
    /// `nil` while loading.
    let preview: ACStore.DevicePreview?

    var body: some View {
        content
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch preview {
        case nil:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(Text("Loading"))
        case .reported(let power, let room?):
            if power == .on {
                Text("On · \(room, format: .acTemperature)")
                    .accessibilityLabel(Text("On, room temperature \(room, format: .acTemperature)"))
            } else {
                Text("Off · \(room, format: .acTemperature)")
                    .accessibilityLabel(Text("Off, room temperature \(room, format: .acTemperature)"))
            }
        case .reported(let power, nil):
            power == .on ? Text("On") : Text("Off")
        case .offline:
            Text("Offline")
        case .unavailable:
            Text("Unavailable")
        }
    }
}
