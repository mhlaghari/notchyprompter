// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ModesSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var modeStore: ModeStore
    @ObservedObject var contextStore: ContextStore
    @State private var selected: UUID?

    private var selectedMode: Binding<Mode>? {
        guard let id = selected,
              let idx = modeStore.modes.firstIndex(where: { $0.id == id })
        else { return nil }
        return Binding(
            get: { modeStore.modes[idx] },
            set: { new in try? modeStore.upsert(new) }
        )
    }

    var body: some View {
        HSplitView {
            modeList
                .frame(minWidth: 180, idealWidth: 200)
            Group {
                if let bind = selectedMode {
                    ModeEditor(mode: bind,
                               contextStore: contextStore,
                               store: store,
                               modeStore: modeStore)
                        .padding()
                } else {
                    Text("Select a mode").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selected == nil { selected = modeStore.noteTakerBuiltIn.id }
        }
    }

    private var modeList: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                Section("Built-in") {
                    ForEach(modeStore.modes.filter { $0.isBuiltIn }) { m in
                        row(m).tag(m.id)
                    }
                }
                Section("Custom") {
                    ForEach(modeStore.modes.filter { !$0.isBuiltIn }) { m in
                        row(m).tag(m.id)
                    }
                }
            }
            HStack {
                Button {
                    let new = Mode(
                        id: UUID(), name: "New mode", systemPrompt: "",
                        attachedContextIDs: [], modelOverride: nil,
                        maxTokens: nil, isBuiltIn: false, defaults: nil
                    )
                    try? modeStore.upsert(new)
                    selected = new.id
                } label: { Image(systemName: "plus") }

                Button {
                    guard let id = selected,
                          let copy = try? modeStore.duplicate(id: id) else { return }
                    selected = copy.id
                } label: { Image(systemName: "plus.square.on.square") }
                .disabled(selected == nil)

                Button {
                    guard let id = selected,
                          let mode = modeStore.mode(by: id),
                          !mode.isBuiltIn else { return }
                    try? modeStore.delete(id: id)
                    selected = modeStore.modes.first?.id
                } label: { Image(systemName: "trash") }
                .disabled(selected.flatMap { modeStore.mode(by: $0)?.isBuiltIn } ?? true)

                Spacer()
            }
            .buttonStyle(.bordered)
            .padding(8)
        }
    }

    private func row(_ m: Mode) -> some View {
        HStack {
            if store.activeModeID == m.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Text(m.name)
            if m.isBuiltIn {
                Image(systemName: "lock").foregroundStyle(.secondary)
            }
            if m.isDirty {
                Image(systemName: "pencil.circle").foregroundStyle(.orange)
            }
        }
    }
}

private struct ModeEditor: View {
    @Binding var mode: Mode
    @ObservedObject var contextStore: ContextStore
    @ObservedObject var store: SettingsStore
    @ObservedObject var modeStore: ModeStore

    var body: some View {
        Form {
            HStack {
                TextField("Name", text: $mode.name)
                Button("Make Active") { store.activeModeID = mode.id }
                    .disabled(store.activeModeID == mode.id)
            }

            Section("System prompt") {
                TextEditor(text: $mode.systemPrompt)
                    .frame(minHeight: 140)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Attached context packs") {
                if contextStore.packs.isEmpty {
                    Text("No context packs yet. Add one in the Contexts tab.")
                        .foregroundStyle(.secondary)
                }
                ForEach(contextStore.packs) { pack in
                    Toggle(pack.title, isOn: binding(for: pack.id))
                }
                if mode.attachedContextIDs.count > 3 {
                    Text("⚠︎ Up to 3 contexts are cached individually. Additional contexts are concatenated into a single cached block.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Overrides (optional)") {
                TextField("Model override (blank = global)",
                          text: Binding(
                            get: { mode.modelOverride ?? "" },
                            set: { mode.modelOverride = $0.isEmpty ? nil : $0 }
                          ))
                Stepper("Max tokens: \(mode.maxTokens.map(String.init) ?? "global")",
                        value: Binding(
                            get: { mode.maxTokens ?? 0 },
                            set: { mode.maxTokens = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...800, step: 20)
            }

            if mode.isBuiltIn {
                Section {
                    Button("Reset to Default") {
                        try? modeStore.resetToDefaults(id: mode.id)
                    }
                    .disabled(!mode.isDirty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { mode.attachedContextIDs.contains(id) },
            set: { on in
                if on {
                    if !mode.attachedContextIDs.contains(id) {
                        mode.attachedContextIDs.append(id)
                    }
                } else {
                    mode.attachedContextIDs.removeAll { $0 == id }
                }
            }
        )
    }
}
