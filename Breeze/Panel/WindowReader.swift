import AppKit
import SwiftUI

/// Reports the `NSWindow` hosting this view whenever it changes. Used as a zero-size background
/// so `PanelVisibility` can observe the MenuBarExtra panel's window.
struct WindowReader: NSViewRepresentable {
    let onChange: @MainActor (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindowChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindowChange = onChange
    }
}
