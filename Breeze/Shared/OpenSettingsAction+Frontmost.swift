import AppKit
import SwiftUI

extension OpenSettingsAction {
    /// Opens Settings and brings it in front of other apps' windows.
    ///
    /// Gotcha: Breeze is an `LSUIElement` agent app, so clicking the menu bar panel does not make
    /// it the active app the way clicking a regular app's window does. `openSettings()` alone then
    /// opens the window *behind* the frontmost app. Requesting activation first (cooperative
    /// activation, `NSApplication.activate()`, macOS 14+) lets the new window come to the front;
    /// the system may still decline, which is harmless.
    func openInFront() {
        NSApplication.shared.activate()
        callAsFunction()
    }
}
