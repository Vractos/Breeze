import AppKit
import os
import SwiftUI

/// Launch at login, poll interval, menu bar temperature.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LoginItem.self) private var loginItem
    @Environment(ACStore.self) private var store

    @State private var loginItemError: LocalizedStringResource?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if loginItem.requiresApproval {
                    HStack {
                        Text("Allow Breeze in System Settings to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items Settings") {
                            loginItem.openSystemSettings()
                        }
                    }
                }
                if let loginItemError {
                    Label {
                        Text(loginItemError)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Stepper(value: $settings.pollIntervalSeconds, in: AppSettings.pollIntervalRange, step: 30) {
                    LabeledContent {
                        Text(.seconds(settings.pollIntervalSeconds), format: .units(allowed: [.minutes, .seconds], width: .abbreviated))
                            .monospacedDigit()
                    } label: {
                        Text("Check the AC every")
                    }
                }
                .accessibilityValue(Text(.seconds(settings.pollIntervalSeconds), format: .units(allowed: [.minutes, .seconds], width: .wide)))
                Toggle("Show temperature in menu bar", isOn: $settings.showTemperatureInMenuBar)
            } footer: {
                Text("LG limits how many requests an account may make per hour. Longer intervals leave more room for your commands.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refreshStatus() }
        // Gotcha: approval happens in System Settings (another app) while this tab stays on
        // screen, so onAppear won't fire again. Re-read the status whenever Breeze becomes
        // active; the task ends when the tab disappears.
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                loginItem.refreshStatus()
            }
        }
        // The poll loop may be asleep for up to 10 minutes on the old interval.
        .onChange(of: settings.pollIntervalSeconds) {
            store.pollIntervalDidChange()
        }
    }

    /// The toggle shows `LoginItem`'s real status; a failed (un)registration snaps it back and
    /// shows why.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { enabled in
                do throws(LoginItemError) {
                    try loginItem.setEnabled(enabled)
                    loginItemError = nil
                } catch {
                    Logger.ui.error("Login item change failed: \(String(describing: error), privacy: .public)")
                    loginItemError = error.message
                }
            }
        )
    }
}
