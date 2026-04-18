import SwiftUI

struct BackendSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var vm: OverlayViewModel
    var onStart: () -> Void
    var onStop: () -> Void
    @State private var showKey = false
    @State private var ollamaModels: [String] = []
    @State private var ollamaProbeError: String? = nil
    @State private var ollamaProbeLoading = false

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
                        .onChange(of: store.ollamaURL) { _, _ in
                            Task { await refreshOllamaModels() }
                        }

                    if ollamaProbeError == nil && !ollamaModels.isEmpty {
                        HStack {
                            Picker("Model", selection: $store.ollamaModel) {
                                ForEach(modelPickerOptions, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            Button {
                                Task { await refreshOllamaModels() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(ollamaProbeLoading)
                        }
                        TextField("Or type a model name", text: $store.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        HStack {
                            TextField("Model", text: $store.ollamaModel)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                Task { await refreshOllamaModels() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(ollamaProbeLoading)
                        }
                    }

                    if let err = ollamaProbeError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if !ollamaModels.isEmpty,
                              !ollamaModels.contains(store.ollamaModel) {
                        Text("Model '\(store.ollamaModel)' isn't installed. Run `ollama pull \(store.ollamaModel)`.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Start with `ollama serve` and `ollama pull \(store.ollamaModel)`.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .task {
                    await refreshOllamaModels()
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

    /// Picker options: installed models, plus the current value if it isn't in
    /// the list (so the user's custom entry stays selected).
    private var modelPickerOptions: [String] {
        if store.ollamaModel.isEmpty || ollamaModels.contains(store.ollamaModel) {
            return ollamaModels
        }
        return ollamaModels + [store.ollamaModel]
    }

    private func refreshOllamaModels() async {
        guard let url = URL(string: store.ollamaURL) else {
            ollamaProbeError = "Invalid Ollama URL: \(store.ollamaURL)"
            ollamaModels = []
            return
        }
        ollamaProbeLoading = true
        defer { ollamaProbeLoading = false }
        do {
            let probe = OllamaModelsProbe(baseURL: url)
            let names = try await probe.listInstalled()
            ollamaModels = names
            ollamaProbeError = nil
        } catch {
            ollamaModels = []
            ollamaProbeError = "Couldn't reach Ollama at \(store.ollamaURL). Is `ollama serve` running?"
        }
    }
}
