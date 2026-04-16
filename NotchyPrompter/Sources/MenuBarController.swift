import AppKit

/// Menu-bar status item — the app has no Dock icon (`LSUIElement=YES`),
/// so this is the only chrome the user sees.
@MainActor
final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let onSettings: () -> Void
    private let onToggle: () -> Void
    private let onQuit: () -> Void
    private weak var vm: OverlayViewModel?

    init(vm: OverlayViewModel,
         onSettings: @escaping () -> Void,
         onToggle: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.vm = vm
        self.onSettings = onSettings
        self.onToggle = onToggle
        self.onQuit = onQuit
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "NotchyPrompter")
            button.image?.isTemplate = true
        }
        rebuildMenu(running: false)
    }

    func rebuildMenu(running: Bool) {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: running ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleSel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(settingsSel), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit NotchyPrompter",
                              action: #selector(quitSel), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func toggleSel() { onToggle() }
    @objc private func settingsSel() { onSettings() }
    @objc private func quitSel() { onQuit() }
}
