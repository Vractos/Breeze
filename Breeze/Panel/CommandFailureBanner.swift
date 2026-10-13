import SwiftUI

/// A dismissible note when a command failed without changing the phase (e.g. LG rejected it).
struct CommandFailureBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(10)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 12))
    }
}
