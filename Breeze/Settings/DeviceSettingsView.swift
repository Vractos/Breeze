import SwiftUI
import ThinQKit

/// Picks which air conditioner on the account Breeze controls.
struct DeviceSettingsView: View {
    @Environment(ACStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var isLoading = false
    @State private var loadResult: ACStore.ConnectionTestResult?

    var body: some View {
        Form {
            Section {
                if store.availableDevices.isEmpty {
                    Text(emptyListMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Air conditioner", selection: selectionBinding) {
                        ForEach(store.availableDevices) { device in
                            deviceRow(device)
                                .tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } header: {
                Text("Air Conditioner")
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
    }

    private var emptyListMessage: LocalizedStringResource {
        store.hasToken
            ? "No air conditioners loaded yet."
            : "Save a token in the Account tab to see your air conditioners."
    }

    private func deviceRow(_ device: DeviceSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(device.alias.isEmpty ? device.modelName : device.alias)
            if !device.alias.isEmpty, !device.modelName.isEmpty {
                Text(device.modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { settings.selectedDeviceID },
            set: { newValue in
                guard let newValue else { return }
                Task { await store.selectDevice(id: newValue) }
            }
        )
    }

    private func loadDevices() {
        isLoading = true
        Task {
            loadResult = await store.loadDevices()
            isLoading = false
        }
    }
}
