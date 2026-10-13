import SwiftUI

/// The AC's display light (`display.light`), shown only when the profile allows writing both ON
/// and OFF.
struct DisplayLightToggleRow: View {
    let isOn: Bool
    let setOn: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { setOn($0) })) {
            Label {
                Text("Display Light")
            } icon: {
                Image(systemName: isOn ? "lightbulb" : "lightbulb.slash")
                    .foregroundStyle(isOn ? Color.yellow : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 4)
        .accessibilityHint(Text("Turns the lights on the air conditioner's front on or off."))
    }
}
