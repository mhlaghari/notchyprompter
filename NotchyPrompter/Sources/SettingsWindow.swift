import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(rootView: some View) {
        let hosting = NSHostingController(rootView: AnyView(rootView))
        let win = NSWindow(contentViewController: hosting)
        win.title = "NotchyPrompter Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }
}
