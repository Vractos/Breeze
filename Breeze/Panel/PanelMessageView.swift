import SwiftUI

/// Shown instead of the controls while there is no state to show yet: loading, or why loading
/// failed, with the one action that helps.
struct PanelMessageView: View {
    let phase: ACStore.Phase
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch phase {
            case .needsSetup, .loadingProfile, .ready:
                ProgressView()
                    .controlSize(.regular)
                Text("Connecting to LG ThinQ…")
                    .foregroundStyle(.secondary)
            case .offline:
                message(
                    symbol: "wifi.slash",
                    title: "AC offline",
                    detail: "Check that the air conditioner is plugged in and connected to Wi-Fi."
                )
                retryButton
            case .rateLimited(let until):
                message(
                    symbol: "hourglass",
                    title: "Rate limited",
                    detail: "LG limits how often Breeze may ask. Retrying at \(until.formatted(date: .omitted, time: .shortened))."
                )
            case .tokenInvalid:
                message(
                    symbol: "key.slash",
                    title: "Token invalid",
                    detail: "LG rejected the saved token. Create a new one and paste it in Settings."
                )
                Button("Open Settings…", action: openSettings)
                    .buttonStyle(.glassProminent)
            case .error(let text):
                message(symbol: "exclamationmark.triangle", title: "Something went wrong", detail: "\(text)")
                retryButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var retryButton: some View {
        Button("Try Again", action: retry)
            .buttonStyle(.glass)
    }

    private func message(symbol: String, title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
