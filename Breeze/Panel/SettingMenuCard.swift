import SwiftUI

/// A glass card that opens a menu of options (mode, fan level, sleep timer): symbol, title and
/// the current value; the menu marks the current value with a checkmark. Picking the checked
/// option does nothing; with a `nil` selection every option can be picked.
struct SettingMenuCard<Option: Hashable>: View {
    let title: LocalizedStringResource
    let selection: Option?
    let options: [Option]
    let name: (Option) -> LocalizedStringResource
    let symbolName: (Option) -> String
    /// Shown when the AC hasn't reported a value yet (or, for Sleep, while a timer runs).
    let fallbackSymbol: String
    /// Replaces the card's value, `name(selection)` (e.g. the sleep timer's time left).
    var value: LocalizedStringResource?
    /// Replaces the card's VoiceOver value, which is otherwise the card's value (e.g. "Level 3"
    /// for the fan card's "3").
    var accessibilityValue: LocalizedStringResource?
    let select: (Option) -> Void

    var body: some View {
        Menu {
            Picker(selection: selectionBinding) {
                ForEach(options, id: \.self) { option in
                    Label {
                        Text(name(option))
                    } icon: {
                        Image(systemName: symbolName(option))
                    }
                    .tag(Optional(option))
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.inline)
        } label: {
            cardLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue ?? displayedValue))
    }

    private var displayedValue: LocalizedStringResource {
        value ?? selection.map(name) ?? "Unknown"
    }

    private var cardLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: selection.map(symbolName) ?? fallbackSymbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(displayedValue)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    private var selectionBinding: Binding<Option?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue, newValue != selection {
                    select(newValue)
                }
            }
        )
    }
}
