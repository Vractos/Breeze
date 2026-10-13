import AppKit
import Observation

/// Whether the menu bar panel is on screen, so the panel can refresh on open and run timers and
/// symbol effects only while someone can see them, so the app stays idle otherwise.
///
/// Why not `onAppear` / `onDisappear` / `.task`: `MenuBarExtra(.window)` orders the same panel in
/// and out and may keep its content view alive between openings; Apple does not document that
/// those modifiers fire on every open, and they have been reported to fire only around the first
/// display. The hosting `NSWindow` is unambiguous: it becomes key when the panel opens and resigns
/// key / changes occlusion when it closes, every time.
@Observable
@MainActor
final class PanelVisibility {
    private(set) var isVisible = false

    @ObservationIgnored private weak var window: NSWindow?
    /// Dropping a token ends its observation, so replacing the array unsubscribes.
    @ObservationIgnored private var observations: [NotificationCenter.ObservationToken] = []

    /// Starts following `window` (the panel's), or stops when it is `nil`.
    func track(_ window: NSWindow?) {
        guard window !== self.window else { return }
        self.window = window
        observations.removeAll()
        if let window {
            let center = NotificationCenter.default
            observations = [
                center.addObserver(of: window, for: NSWindow.DidBecomeKeyMessage.self) { [weak self] _ in
                    self?.update()
                },
                center.addObserver(of: window, for: NSWindow.DidResignKeyMessage.self) { [weak self] _ in
                    self?.update()
                },
                center.addObserver(of: window, for: NSWindow.DidChangeOcclusionStateMessage.self) { [weak self] _ in
                    self?.update()
                },
            ]
        }
        update()
    }

    /// Visible while key (the user is interacting) or ordered in and not fully covered; not
    /// visible without a window.
    private func update() {
        var visible = false
        if let window {
            let isOnScreen = window.isVisible && window.occlusionState.contains(.visible)
            visible = window.isKeyWindow || isOnScreen
        }
        if visible != isVisible {
            isVisible = visible
        }
    }
}
