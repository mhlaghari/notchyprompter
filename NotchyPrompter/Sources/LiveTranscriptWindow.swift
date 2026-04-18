// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

@MainActor
final class LiveTranscriptWindowController: NSWindowController {
    init(logURLProvider: @escaping () -> URL?) {
        let view = LiveTranscriptView(logURLProvider: logURLProvider)
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Live Transcript"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 640, height: 420))
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
