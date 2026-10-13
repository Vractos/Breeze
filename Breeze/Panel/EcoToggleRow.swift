import SwiftUI

/// "Eco Mode" (`powerSave.powerSaveEnabled`), shown only when the profile allows writing it.
struct EcoToggleRow: View {
    let isOn: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { setEnabled($0) })) {
            Label {
                Text("Eco Mode")
            } icon: {
                Image(systemName: "leaf")
                    .foregroundStyle(isOn ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 4)
        .accessibilityHint(Text("Limits the compressor to save energy."))
    }
}
