import AppKit

/// An invisible `NSView` that calls back when it moves into (or out of) a window.
final class WindowReportingView: NSView {
    var onWindowChange: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let window = self.window
        let callback = onWindowChange
        // Deferred: this runs inside SwiftUI's view update, and the callback mutates observable
        // state, which must not happen during an update.
        Task { @MainActor in
            callback?(window)
        }
    }
}
