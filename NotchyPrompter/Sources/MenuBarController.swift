import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let onSettings: () -> Void
    private let onToggle: () -> Void
    private let onQuit: () -> Void
    private let onSelectMode: (UUID) -> Void
    private let onSummarizeLast: () -> Void
    private let onOpenSessionsFolder: () -> Void
    private let onEditModes: () -> Void
    private weak var vm: OverlayViewModel?
    private let modeStore: ModeStore
    private let settingsStore: SettingsStore
    private let sessionRecorder: SessionRecorder

    init(vm: OverlayViewModel,
         modeStore: ModeStore,
         settingsStore: SettingsStore,
         sessionRecorder: SessionRecorder,
         onSettings: @escaping () -> Void,
         onToggle: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onSelectMode: @escaping (UUID) -> Void,
         onSummarizeLast: @escaping () -> Void,
         onOpenSessionsFolder: @escaping () -> Void,
         onEditModes: @escaping () -> Void) {
        self.vm = vm
        self.modeStore = modeStore
        self.settingsStore = settingsStore
        self.sessionRecorder = sessionRecorder
        self.onSettings = onSettings
        self.onToggle = onToggle
        self.onQuit = onQuit
        self.onSelectMode = onSelectMode
        self.onSummarizeLast = onSummarizeLast
        self.onOpenSessionsFolder = onOpenSessionsFolder
        self.onEditModes = onEditModes
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.circle",
                                   accessibilityDescription: "NotchyPrompter")
            button.image?.isTemplate = true
        }
        rebuildMenu(running: false)
    }

    func rebuildMenu(running: Bool) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggle = NSMenuItem(title: running ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleSel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Mode submenu
        let activeID = settingsStore.activeModeID
        let activeName = modeStore.modes.first(where: { $0.id == activeID })?.name ?? "?"
        let modeItem = NSMenuItem(title: "Mode: \(activeName)",
                                  action: nil, keyEquivalent: "")
        let modeSub = NSMenu()
        let builtIns = modeStore.modes.filter { $0.isBuiltIn }
        let customs = modeStore.modes.filter { !$0.isBuiltIn }

        for m in builtIns {
            modeSub.addItem(modeMenuItem(m, activeID: activeID))
        }
        if !customs.isEmpty {
            modeSub.addItem(.separator())
            for m in customs {
                modeSub.addItem(modeMenuItem(m, activeID: activeID))
            }
        }
        modeSub.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Modes…", action: #selector(editModesSel), keyEquivalent: "")
        edit.target = self
        modeSub.addItem(edit)
        modeItem.submenu = modeSub
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let summarize = NSMenuItem(title: "Summarize Last Session…",
                                   action: #selector(summarizeSel), keyEquivalent: "")
        summarize.target = self
        summarize.isEnabled = !sessionRecorder.listSessions().isEmpty
        menu.addItem(summarize)

        let openFolder = NSMenuItem(title: "Open Sessions Folder",
                                    action: #selector(openFolderSel), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(settingsSel), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit NotchyPrompter",
                              action: #selector(quitSel), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    private func modeMenuItem(_ mode: Mode, activeID: UUID?) -> NSMenuItem {
        let i = NSMenuItem(title: mode.name,
                           action: #selector(selectModeSel(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = mode.id.uuidString
        i.state = (mode.id == activeID) ? .on : .off
        return i
    }

    @objc private func toggleSel() { onToggle() }
    @objc private func settingsSel() { onSettings() }
    @objc private func quitSel() { onQuit() }
    @objc private func summarizeSel() { onSummarizeLast() }
    @objc private func openFolderSel() { onOpenSessionsFolder() }
    @objc private func editModesSel() { onEditModes() }
    @objc private func selectModeSel(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String,
              let id = UUID(uuidString: s) else { return }
        onSelectMode(id)
    }
}
