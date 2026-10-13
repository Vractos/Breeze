import SwiftUI
import ThinQKit

/// Picks which air conditioner on the account Breeze controls, names them locally and shows
/// what each reports right now, so same-named ACs can be told apart.
struct DeviceSettingsView: View {
    @Environment(ACStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var isLoading = false
    @State private var loadResult: ACStore.ConnectionTestResult?
    /// By device id; a missing entry is still loading.
    @State private var previews: [String: ACStore.DevicePreview] = [:]

    var body: some View {
        Form {
            Section {
                if store.availableDevices.isEmpty {
                    Text(emptyListMessage)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.deviceLabels) { label in
                        DeviceSettingsRow(
                            label: label,
                            preview: previews[label.id],
                            isSelected: label.id == settings.selectedDeviceID,
                            nickname: nicknameBinding(for: label.id),
                            select: { select(label.id) }
                        )
                    }
                }
            } header: {
                Text("Air Conditioners")
            } footer: {
                if !store.availableDevices.isEmpty {
                    Text("Names stay on this Mac and are never sent to LG. Leave a name empty to use the one from the LG ThinQ app.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("Refresh List", action: loadDevices)
                        .disabled(isLoading || !store.hasToken)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                if let loadResult, !loadResult.isSuccess {
                    ConnectionTestResultLabel(result: loadResult)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // The store fills the list while loading; only ask LG when it is still empty.
            if store.availableDevices.isEmpty, store.hasToken {
                loadDevices()
            }
        }
        // Once per tab appearance (and when the list changes): one state GET per AC, cancelled
        // when the tab goes away.
        .task(id: store.availableDevices.map(\.id)) {
            await loadPreviews()
        }
    }

    private var emptyListMessage: LocalizedStringResource {
        store.hasToken
            ? "No air conditioners loaded yet."
            : "Save a token in the Account tab to see your air conditioners."
    }

    private func nicknameBinding(for deviceID: String) -> Binding<String> {
        Binding(
            get: { settings.nickname(for: deviceID) },
            set: { settings.setNickname($0, for: deviceID) }
        )
    }

    private func select(_ deviceID: String) {
        Task { await store.selectDevice(id: deviceID) }
    }

    /// One AC at a time, so a 1306 on the first stops the rest (`statePreview` skips requests
    /// inside the back-off).
    private func loadPreviews() async {
        previews = [:]
        for device in store.availableDevices {
            let preview = await store.statePreview(for: device.id)
            guard !Task.isCancelled else { return }
            previews[device.id] = preview
        }
    }

    private func loadDevices() {
        isLoading = true
        Task {
            loadResult = await store.loadDevices()
            isLoading = false
        }
    }
}

#if DEBUG
#Preview("Device", traits: .modifier(PreviewScenarioModifier(.ready))) {
    DeviceSettingsView()
        .frame(width: SettingsView.size.width, height: SettingsView.size.height)
}
#endif
