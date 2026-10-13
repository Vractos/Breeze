import SwiftUI

/// A glass card that toggles a setting on tap (Airflow's swing): symbol, title and the current
/// value, styled like `SettingMenuCard` so the two sit side by side in the grid.
struct SettingToggleCard: View {
    let title: LocalizedStringResource
    let symbolName: String
    /// "Swing" / "Fixed"; "Unknown" while the AC hasn't reported it.
    let value: LocalizedStringResource
    let isOn: Bool
    /// False while the panel is closed: the symbol stops animating.
    let isAnimating: Bool
    let accessibilityHint: LocalizedStringResource
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.title3)
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 24)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.5)), isActive: isOn && isAnimating && !reduceMotion)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(accessibilityHint))
        .accessibilityAddTraits([.isButton, .isToggle])
    }
}
