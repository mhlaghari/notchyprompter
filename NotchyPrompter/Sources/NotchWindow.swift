import AppKit
import SwiftUI

final class NotchWindow: NSWindow {
    private let vm: OverlayViewModel

    init(viewModel: OverlayViewModel) {
        self.vm = viewModel
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = true
        // Best-effort: hides from legacy CGWindowList* capture.
        // ScreenCaptureKit (modern Zoom/Teams/Meet/QuickTime) still sees it.
        sharingType = .none

        let hosting = NSHostingView(rootView: OverlayView(vm: vm))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting

        positionAtNotch()
    }

    func positionAtNotch() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.frame
        let topInset: CGFloat
        if #available(macOS 12.0, *) {
            topInset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32
        } else {
            topInset = 32
        }
        let w: CGFloat = 560
        let h: CGFloat = 280
        // Cocoa origin is bottom-left.
        let x = visible.minX + (visible.width - w) / 2
        let y = visible.maxY - topInset - h - 6
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    // Required so a borderless window can still host content correctly.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
