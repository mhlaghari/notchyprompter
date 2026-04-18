import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow?
    private var settingsWC: SettingsWindowController?
    private var menuBar: MenuBarController?
    private var pipeline: Pipeline?
    private let vm = OverlayViewModel()
    private let store = SettingsStore.shared
    private let modeStore = ModeStore()
    private let contextStore = ContextStore()
    private let sessionRecorder = SessionRecorder()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Overlay window
        let w = NotchWindow(viewModel: vm)
        w.orderFrontRegardless()
        self.window = w

        // Reposition on display changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.window?.positionAtNotch() }
        }

        // Pipeline
        let p = Pipeline(store: store, vm: vm,
                         modeStore: modeStore, contextStore: contextStore,
                         sessionRecorder: sessionRecorder)
        self.pipeline = p

        let s = self.store
        let r = self.sessionRecorder
        p.postSessionHook = { session in
            guard s.autoSummarizeOnStop else { return }
            guard let client = s.buildClient() else { return }
            let gen = SummaryGenerator(client: client)
            do {
                let text = try await gen.run(prompt: s.summaryPrompt, session: session)
                try r.appendSummary(sessionID: session.id,
                                    prompt: s.summaryPrompt, text: text)
            } catch {
                NSLog("summary error: \(error.localizedDescription)")
            }
        }

        if store.activeModeID == nil {
            store.activeModeID = modeStore.noteTakerBuiltIn.id
        }

        // Menu bar
        let mb = MenuBarController(
            vm: vm,
            modeStore: modeStore,
            settingsStore: store,
            sessionRecorder: sessionRecorder,
            onSettings: { [weak self] in self?.openSettings() },
            onToggle: { [weak self] in self?.togglePipeline() },
            onQuit: { NSApp.terminate(nil) },
            onSelectMode: { [weak self] id in self?.selectMode(id: id) },
            onSummarizeLast: { [weak self] in self?.summarizeLast() },
            onOpenSessionsFolder: {
                NSWorkspace.shared.selectFile(nil,
                                              inFileViewerRootedAtPath: Paths.sessionsDir.path)
            },
            onEditModes: { [weak self] in self?.openSettingsToModesTab() },
            onShowTranscript: { [weak self] in self?.openLiveTranscript() }
        )
        self.menuBar = mb

        // React to running state
        vm.$isRunning.sink { [weak self] running in
            self?.menuBar?.rebuildMenu(running: running)
        }.store(in: &cancellables)

        modeStore.$modes.sink { [weak self] _ in
            self?.menuBar?.rebuildMenu(running: self?.vm.isRunning ?? false)
        }.store(in: &cancellables)

        // Always open Settings on launch — it's the user's primary UI since
        // there's no Dock icon and the menu-bar icon can hide behind the notch.
        openSettings()

        // If the user had the pipeline running before macOS killed the app
        // (e.g. after granting Screen Recording permission), auto-resume.
        if store.autoStartOnLaunch && store.isRunnable {
            pipeline?.start()
        }
    }

    // Called when user double-clicks the .app while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    private func openSettings() {
        if settingsWC == nil {
            let view = SettingsTabs(
                store: store,
                vm: vm,
                modeStore: modeStore,
                contextStore: contextStore,
                onStart: { [weak self] in
                    self?.pipeline?.start()
                    self?.store.autoStartOnLaunch = true
                },
                onStop: { [weak self] in
                    self?.pipeline?.stop()
                    self?.store.autoStartOnLaunch = false
                }
            )
            settingsWC = SettingsWindowController(rootView: view)
        }
        settingsWC?.show()
    }

    private func togglePipeline() {
        if vm.isRunning {
            pipeline?.stop()
            store.autoStartOnLaunch = false
        } else if store.isRunnable {
            pipeline?.start()
            store.autoStartOnLaunch = true
        } else {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline?.stop()
    }

    private var summaryWC: NSWindowController?
    private var transcriptWC: LiveTranscriptWindowController?

    private func openLiveTranscript() {
        if transcriptWC == nil {
            let r = sessionRecorder
            transcriptWC = LiveTranscriptWindowController(logURLProvider: { r.currentLogURL })
        }
        transcriptWC?.show()
    }

    private func selectMode(id: UUID) {
        store.activeModeID = id
        if let mode = modeStore.mode(by: id) {
            pipeline?.recordModeChangeIfRunning(mode)
        }
        menuBar?.rebuildMenu(running: vm.isRunning)
    }

    private func summarizeLast() {
        guard let latest = sessionRecorder.listSessions().first else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: latest.fileURL)
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                let s = try dec.decode(Session.self, from: data)
                if let summary = s.summaries.last?.text {
                    self.showSummaryWindow(text: summary, sessionID: s.id)
                } else if let client = self.store.buildClient() {
                    let gen = SummaryGenerator(client: client)
                    let text = try await gen.run(prompt: self.store.summaryPrompt, session: s)
                    try self.sessionRecorder.appendSummary(
                        sessionID: s.id, prompt: self.store.summaryPrompt, text: text)
                    self.showSummaryWindow(text: text, sessionID: s.id)
                }
            } catch {
                NSLog("summarizeLast error: \(error.localizedDescription)")
            }
        }
    }

    private func showSummaryWindow(text: String, sessionID: String) {
        let scroll = NSScrollView()
        let tv = NSTextView()
        tv.isEditable = false
        tv.string = text
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Summary — \(sessionID)"
        win.contentView = scroll
        win.center()
        let wc = NSWindowController(window: win)
        summaryWC = wc
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
    }

    private func openSettingsToModesTab() {
        openSettings()
        NotificationCenter.default.post(name: .init("OpenModesTab"), object: nil)
    }
}
