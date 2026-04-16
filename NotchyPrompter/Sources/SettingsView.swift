import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var vm: OverlayViewModel
    var onStart: () -> Void
    var onStop: () -> Void
    @State private var showKey = false

    var body: some View {
        Form {
            Section("Backend") {
                Picker("LLM", selection: Binding(
                    get: { store.backend },
                    set: { store.backend = $0 }
                )) {
                    ForEach(LLMBackend.allCases) { b in
                        Text(b.display).tag(b)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch store.backend {
            case .claude:
                Section("Anthropic") {
                    HStack {
                        if showKey {
                            TextField("API key", text: $store.apiKey)
                        } else {
                            SecureField("API key", text: $store.apiKey)
                        }
                        Button(showKey ? "Hide" : "Show") { showKey.toggle() }
                            .buttonStyle(.bordered)
                    }
                    TextField("Model", text: $store.claudeModel)
                        .textFieldStyle(.roundedBorder)
                }
            case .ollama:
                Section("Ollama") {
                    TextField("Base URL", text: $store.ollamaURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $store.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                    Text("Start with `ollama serve` and `ollama pull \(store.ollamaModel)`.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transcription (WhisperKit)") {
                TextField("Model name", text: $store.whisperModel)
                    .textFieldStyle(.roundedBorder)
                Text("First run downloads ~500 MB–1.5 GB from HuggingFace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Conversation") {
                Stepper("Context pairs: \(store.contextPairs)",
                        value: $store.contextPairs, in: 0...20)
                Stepper("Max tokens per reply: \(store.maxTokens)",
                        value: $store.maxTokens, in: 40...400, step: 20)
            }

            Section("Status") {
                HStack {
                    Circle()
                        .fill(vm.isRunning ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    Text(vm.statusLine.isEmpty ? "Idle" : vm.statusLine)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    if vm.isRunning {
                        Button("Stop", action: onStop)
                    } else {
                        Button("Start", action: onStart).disabled(!store.isRunnable)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}
