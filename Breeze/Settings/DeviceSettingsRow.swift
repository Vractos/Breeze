import SwiftUI

/// One air conditioner in Settings › Device: pick it, give it a local
/// name, and see what it reports right now to tell it apart from the others.
struct DeviceSettingsRow: View {
    let label: DeviceLabel
    /// `nil` while loading.
    let preview: ACStore.DevicePreview?
    let isSelected: Bool
    /// The nickname as typed; empty uses the LG name (the placeholder).
    @Binding var nickname: String
    let select: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            selectButton
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: $nickname, prompt: Text(label.lgName))
                    .labelsHidden()
                    // In a grouped Form the default style draws no border, so the name read as a
                    // plain label rather than something to edit.
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityLabel(Text("Name for \(label.fullName)"))
                if !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            DevicePreviewLabel(preview: preview)
        }
    }

    /// A radio-style button: a `Picker` row can't hold the name field.
    private var selectButton: some View {
        Button(action: select) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(isSelected ? Text("Breeze controls this air conditioner.") : Text("Control this air conditioner"))
        .accessibilityLabel(Text(label.fullName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text("Makes Breeze control this air conditioner."))
    }

    /// The LG name a nickname hides, the model (unless it already is the name) and, when another
    /// AC has the same name, the end of the device id: "Ar-condicionado · RAC_056905_WW · …a3f2".
    private var details: String {
        var parts: [String] = []
        if label.hasNickname {
            parts.append(label.lgName)
        }
        if !label.modelName.isEmpty, label.modelName != label.lgName {
            parts.append(label.modelName)
        }
        if label.isAmbiguous {
            parts.append(label.idSuffix)
        }
        return parts.joined(separator: " · ")
    }
}
