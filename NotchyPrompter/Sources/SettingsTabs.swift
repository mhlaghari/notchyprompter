// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

enum SettingsTab: String, Hashable {
    case backend, modes, contexts, about
}

struct SettingsTabs: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var vm: OverlayViewModel
    @ObservedObject var modeStore: ModeStore
    @ObservedObject var contextStore: ContextStore
    @State private var tab: SettingsTab = .backend

    var onStart: () -> Void
    var onStop: () -> Void

    var body: some View {
        TabView(selection: $tab) {
            BackendSettingsView(store: store, vm: vm, onStart: onStart, onStop: onStop)
                .tabItem { Label("Backend", systemImage: "cpu") }
                .tag(SettingsTab.backend)

            ModesSettingsView(store: store, modeStore: modeStore, contextStore: contextStore)
                .tabItem { Label("Modes", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.modes)

            ContextsSettingsView(contextStore: contextStore)
                .tabItem { Label("Contexts", systemImage: "doc.text") }
                .tag(SettingsTab.contexts)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 640, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenModesTab"))) { _ in
            tab = .modes
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NotchyPrompter").font(.title2)
            Text("Silent meeting copilot.").foregroundStyle(.secondary)
            Text("Licensed under AGPL-3.0-or-later.")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
