// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct ContextsSettingsView: View {
    @ObservedObject var contextStore: ContextStore
    @State private var selected: UUID?

    private var selectedPack: Binding<ContextPack>? {
        guard let id = selected,
              let idx = contextStore.packs.firstIndex(where: { $0.id == id })
        else { return nil }
        return Binding(
            get: { contextStore.packs[idx] },
            set: { new in try? contextStore.save(new) }
        )
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(contextStore.packs) { p in
                        Text(p.title).tag(p.id)
                    }
                }
                HStack {
                    Button {
                        let new = ContextPack(id: UUID(),
                                              title: "New context",
                                              body: "")
                        try? contextStore.save(new)
                        selected = new.id
                    } label: { Image(systemName: "plus") }

                    Button {
                        guard let id = selected else { return }
                        try? contextStore.delete(id: id)
                        selected = contextStore.packs.first?.id
                    } label: { Image(systemName: "trash") }
                    .disabled(selected == nil)

                    Spacer()

                    Button("Reveal") { contextStore.revealInFinder() }
                        .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .frame(minWidth: 180, idealWidth: 200)

            Group {
                if let bind = selectedPack {
                    Form {
                        TextField("Title", text: bind.title)
                        Section("Markdown") {
                            TextEditor(text: bind.body)
                                .frame(minHeight: 300)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                } else {
                    Text("Select or add a context pack")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
