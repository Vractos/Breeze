import AppKit
import SwiftUI
import ThinQKit

/// The MenuBarExtra panel: setup, loading/error messages, or the AC's controls, with
/// the status footer underneath.
///
/// Panel open/close is detected through the hosting window (`PanelVisibility`), not
/// `onAppear`/`onDisappear`, which are not guaranteed to fire on every MenuBarExtra open.
/// Visibility drives `panelDidAppear()` (refresh on open), keyboard focus for ↑/↓, the footer's
/// ticking "Synced … ago" and every symbol effect, so nothing runs while the panel is closed.
struct PanelView: View {
    static let width: CGFloat = 320

    @Environment(ACStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visibility = PanelVisibility()
    @State private var editor = TemperatureEditor()
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        content
            .padding(16)
            .frame(width: Self.width)
            // The panel itself takes focus so ↑/↓ and ⌘-shortcuts reach `onKeyPress` even when no
            // control is focused; key presses from a focused control bubble up to here too.
            // Gotcha: `.edit` (not the default `.activate`) — on macOS an `.activate`-only view is
            // focusable only with Full Keyboard Access turned on.
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($hasKeyboardFocus)
            .onKeyPress(phases: [.down, .repeat]) { press in handleKeyPress(press) }
            // One switch for every symbol effect in the panel: removed with Reduce Motion and
            // while the panel is closed, so nothing animates off screen.
            .symbolEffectsRemoved(reduceMotion || !visibility.isVisible)
            .background(WindowReader { window in visibility.track(window) })
            .onChange(of: visibility.isVisible, initial: true) { _, isVisible in
                panelVisibilityChanged(isVisible)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.phase == .needsSetup {
            VStack(spacing: 16) {
                SetupView(openSettings: { openSettingsInFront() })
                footer
            }
        } else {
            // Gotcha: deliberately NOT wrapped in one outer GlassEffectContainer. Tried (the
            // recommended setup for performance): the container renders the glass shapes itself,
            // so the `.opacity(0.45)` that PanelControlsView applies while the AC is off no longer
            // dims the hero card and the −/+ buttons (checked in the "Off" preview). The gain for
            // ~6 static glass views in a small popover isn't worth losing the disabled look;
            // the setting cards keep their own container (`ControlCardGrid`) so they blend.
            controlsContent
        }
    }

    private var controlsContent: some View {
        VStack(spacing: 14) {
            if let snapshot = store.snapshot, let capabilities = store.capabilities {
                PanelControlsView(
                    snapshot: snapshot,
                    capabilities: capabilities,
                    draft: editor.draft,
                    acceptsCommands: acceptsCommands,
                    isVisible: visibility.isVisible,
                    onEditTarget: { value in editTarget(value) },
                    onSliderEditingChanged: { isEditing in sliderEditingChanged(isEditing) }
                )
            } else {
                if let device = switchableDeviceWithoutState {
                    HStack {
                        PanelDeviceSwitcher(
                            device: device,
                            devices: store.deviceLabels,
                            selectDevice: selectDevice
                        )
                        Spacer(minLength: 0)
                    }
                }
                PanelMessageView(
                    phase: store.phase,
                    retry: { retry() },
                    openSettings: { openSettingsInFront() }
                )
            }
            if let message = store.commandFailureMessage {
                CommandFailureBanner(message: message, dismiss: { store.dismissCommandFailure() })
            }
            footer
        }
    }

    private var footer: some View {
        PanelFooter(
            status: PanelStatus(
                phase: store.phase,
                isSyncing: store.isSyncing,
                lastSync: store.lastSync,
                hasSnapshot: store.snapshot != nil
            ),
            isVisible: visibility.isVisible,
            refresh: { refresh() },
            openSettings: { openSettingsInFront() },
            quit: { quit() }
        )
    }

    /// The header (and its device menu) needs a snapshot. Without one — e.g. the saved AC was
    /// offline at load — the device switch stands on its own above the message, so another AC
    /// stays one click away instead of only in Settings › Device. Not while setup or a new
    /// token is what is needed.
    private var switchableDeviceWithoutState: DeviceLabel? {
        guard store.deviceLabels.count > 1, let device = store.deviceLabel else { return nil }
        switch store.phase {
        case .ready, .rateLimited, .error, .loadingProfile, .offline: return device
        case .needsSetup, .tokenInvalid: return nil
        }
    }

    /// Commands make sense while connected; offline / token-invalid / loading show the last state
    /// read-only.
    private var acceptsCommands: Bool {
        switch store.phase {
        case .ready, .rateLimited, .error: true
        case .needsSetup, .loadingProfile, .offline, .tokenInvalid: false
        }
    }

    // MARK: - Actions

    private func editTarget(_ value: Double) {
        editor.edit(to: value, commit: commitTarget)
    }

    /// While the slider is dragged nothing is committed (however long the pointer rests); the
    /// value is sent once when the drag ends.
    private func sliderEditingChanged(_ isEditing: Bool) {
        if isEditing {
            editor.beginHolding()
        } else {
            editor.endHolding(commit: commitTarget)
        }
    }

    /// `ACStore.send(_:)` ignores a setpoint equal to the current target, so an edit that ends
    /// where it started costs no request.
    private func commitTarget(_ value: Double) {
        store.send(.targetTemperature(value))
    }

    private func refresh() {
        Task { await store.refresh() }
    }

    private func selectDevice(_ id: String) {
        Task { await store.selectDevice(id: id) }
    }

    /// From a message view (no snapshot yet): restart the whole load, which also clears a halt
    /// such as "no air conditioner found".
    private func retry() {
        Task { await store.reconfigure() }
    }

    private func openSettingsInFront() {
        openSettings.openInFront()
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func panelVisibilityChanged(_ isVisible: Bool) {
        if isVisible {
            hasKeyboardFocus = true
            Task { await store.panelDidAppear() }
        } else {
            store.panelDidDisappear()
        }
    }

    // MARK: - Keyboard

    /// ⌘R refresh, ⌘, Settings, ⌘Q quit, ↑/↓ one setpoint step. The footer menu items carry the
    /// same shortcuts for discoverability; whichever sees the key first handles it, never both.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.intersection([.command, .option, .control, .shift])
        if modifiers == .command {
            return handleCommandShortcut(press.characters.lowercased())
        }
        guard modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .upArrow: return stepTargetTemperature(up: true) ? .handled : .ignored
        case .downArrow: return stepTargetTemperature(up: false) ? .handled : .ignored
        default: return .ignored
        }
    }

    private func handleCommandShortcut(_ character: String) -> KeyPress.Result {
        switch character {
        case "r":
            refresh()
        case ",":
            openSettingsInFront()
        case "q":
            quit()
        default:
            return .ignored
        }
        return .handled
    }

    /// Moves the setpoint one step through the same debounced path as the −/+ buttons. At the
    /// range's limit there is nowhere to go: the key is ignored instead of re-sending the limit.
    private func stepTargetTemperature(up: Bool) -> Bool {
        guard acceptsCommands,
              let snapshot = store.snapshot,
              snapshot.power == .on,
              let capabilities = store.capabilities,
              let setpoint = TemperatureSetpoint(snapshot: snapshot, capabilities: capabilities, draft: editor.draft)
        else { return false }
        let next = setpoint.range.value(steppingFrom: setpoint.value, up: up)
        guard abs(next - setpoint.value) >= Self.stepTolerance else { return false }
        editTarget(next)
        return true
    }

    private static let stepTolerance = 1e-6
}

#if DEBUG
#Preview("Ready", traits: .modifier(PreviewScenarioModifier(.ready))) {
    PanelView()
}

#Preview("Off", traits: .modifier(PreviewScenarioModifier(.off))) {
    PanelView()
}

#Preview("Fan Auto, swing and light off", traits: .modifier(PreviewScenarioModifier(.fanAuto))) {
    PanelView()
}

#Preview("Fan level 3", traits: .modifier(PreviewScenarioModifier(.fanLevel3))) {
    PanelView()
}

#Preview("Sleep timer running", traits: .modifier(PreviewScenarioModifier(.sleepSet))) {
    PanelView()
}

#Preview("Needs setup", traits: .modifier(PreviewScenarioModifier(.needsSetup))) {
    PanelView()
}

#Preview("Offline", traits: .modifier(PreviewScenarioModifier(.offline))) {
    PanelView()
}

#Preview("Offline at load, two devices", traits: .modifier(PreviewScenarioModifier(.offlineAtLoad))) {
    PanelView()
}

#Preview("Token invalid", traits: .modifier(PreviewScenarioModifier(.tokenInvalid))) {
    PanelView()
}

#Preview("Loading", traits: .modifier(PreviewScenarioModifier(.loading))) {
    PanelView()
}
#endif
