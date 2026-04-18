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
                         modeStore: modeStore, contextStore: contextStore)
        self.pipeline = p

        if store.activeModeID == nil {
            store.activeModeID = modeStore.watchingBuiltIn.id
        }

        // Menu bar
        let mb = MenuBarController(
            vm: vm,
            onSettings: { [weak self] in self?.openSettings() },
            onToggle: { [weak self] in self?.togglePipeline() },
            onQuit: { NSApp.terminate(nil) }
        )
        self.menuBar = mb

        // React to running state
        vm.$isRunning.sink { [weak self] running in
            self?.menuBar?.rebuildMenu(running: running)
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
            let view = SettingsView(
                store: store,
                vm: vm,
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
}
