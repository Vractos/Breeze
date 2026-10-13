import SwiftUI

/// First launch, no token saved: a short explanation and a button to Settings.
struct SetupView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.tint)
                .padding(.top, 8)
                .accessibilityHidden(true)
            Text("Set up Breeze")
                .font(.title3.weight(.semibold))
            Text("Breeze controls your LG air conditioner through LG ThinQ. Create a personal access token, then paste it in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openSettings) {
                Text("Open Settings…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}
