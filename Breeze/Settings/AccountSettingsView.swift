import SwiftUI

/// Token, country and connection test.
struct AccountSettingsView: View {
    private static let tokenPortal = URL(string: "https://connect-pat.lgthinq.com")

    @Environment(ACStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var tokenDraft = ""
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var isConfirmingRemoval = false
    @State private var isTesting = false
    @State private var testResult: ACStore.ConnectionTestResult?

    var body: some View {
        Form {
            tokenSection
            countrySection
            testSection
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove the saved token?", isPresented: $isConfirmingRemoval) {
            Button("Remove Token", role: .destructive, action: removeToken)
        } message: {
            Text("Breeze stops talking to your air conditioner until you save a new token.")
        }
    }

    // MARK: - Sections

    private var tokenSection: some View {
        Section {
            SecureField(text: $tokenDraft, prompt: tokenPrompt) {
                Text("Personal access token")
            }
            .onSubmit(saveToken)
            HStack {
                Button("Save", action: saveToken)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedDraft.isEmpty || isSaving)
                if store.hasToken {
                    Button("Remove Token…", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                    .disabled(isSaving)
                }
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            if saveFailed {
                Label("Breeze couldn't save the token to the Keychain.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let url = Self.tokenPortal {
                Link(destination: url) {
                    Label("Create a token at connect-pat.lgthinq.com", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("LG ThinQ Token")
        } footer: {
            Text(store.hasToken ? "A token is saved in your Keychain." : "The token is stored in your Keychain.")
                .foregroundStyle(.secondary)
        }
    }

    private var countrySection: some View {
        Section {
            Picker("Country", selection: countryBinding) {
                ForEach(CountryOption.all(including: settings.countryCode)) { country in
                    Text(country.name).tag(country.code)
                }
            }
        } footer: {
            Text("The country your ThinQ account is registered in. It selects LG's regional server.")
                .foregroundStyle(.secondary)
        }
    }

    private var testSection: some View {
        Section {
            HStack {
                Button("Test Connection", action: testConnection)
                    .disabled(isTesting)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
            }
            if let testResult {
                ConnectionTestResultLabel(result: testResult)
            }
        } footer: {
            Text("Uses the token typed above, or the saved one. Nothing is saved.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var trimmedDraft: String {
        tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tokenPrompt: Text {
        store.hasToken ? Text("Paste a new token to replace the saved one") : Text("Paste your token")
    }

    /// Changing the country rebuilds the client (it picks the regional server).
    private var countryBinding: Binding<String> {
        Binding(
            get: { settings.countryCode },
            set: { newValue in
                guard newValue != settings.countryCode else { return }
                settings.countryCode = newValue
                testResult = nil
                if store.hasToken {
                    Task { await store.reconfigure() }
                }
            }
        )
    }

    // MARK: - Actions

    private func saveToken() {
        guard !trimmedDraft.isEmpty, !isSaving else { return }
        let token = trimmedDraft
        isSaving = true
        saveFailed = false
        Task {
            let saved = await store.saveToken(token)
            isSaving = false
            saveFailed = !saved
            if saved {
                tokenDraft = ""
                testResult = nil
            }
        }
    }

    private func removeToken() {
        isSaving = true
        saveFailed = false
        Task {
            let removed = await store.removeToken()
            isSaving = false
            saveFailed = !removed
            testResult = nil
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let candidate = trimmedDraft.isEmpty ? nil : trimmedDraft
        Task {
            testResult = await store.testConnection(token: candidate)
            isTesting = false
        }
    }
}
