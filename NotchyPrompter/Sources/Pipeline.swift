import Foundation

/// Wires AudioCapture → VAD → Transcriber → LLMClient → OverlayViewModel.
/// One pipeline per Start/Stop cycle. `@MainActor` because it publishes to
/// the overlay view model.
@MainActor
final class Pipeline {
    private let store: SettingsStore
    private let vm: OverlayViewModel
    private let modeStore: ModeStore
    private let contextStore: ContextStore
    private let sessionRecorder: SessionRecorder

    var postSessionHook: ((Session) async -> Void)?

    func recordModeChangeIfRunning(_ mode: Mode) {
        guard vm.isRunning else { return }
        sessionRecorder.recordModeChange(mode)
    }

    private var capture: AudioCapture?
    private var transcriber: Transcriber?
    private var llm: LLMClient?
    private var mainTask: Task<Void, Never>?
    private var accumulator: ChunkAccumulator?

    private var history: [ChatTurn] = []

    init(store: SettingsStore,
         vm: OverlayViewModel,
         modeStore: ModeStore,
         contextStore: ContextStore,
         sessionRecorder: SessionRecorder) {
        self.store = store
        self.vm = vm
        self.modeStore = modeStore
        self.contextStore = contextStore
        self.sessionRecorder = sessionRecorder
    }

    func start() {
        guard !vm.isRunning else { return }
        guard let client = store.buildClient() else {
            vm.setStatus("missing API key or URL")
            return
        }
        let t = Transcriber(modelName: store.whisperModel)
        let cap = AudioCapture()
        self.llm = client
        self.transcriber = t
        self.capture = cap
        vm.isRunning = true
        vm.setStatus("starting…")
        let activeID = store.activeModeID ?? modeStore.noteTakerBuiltIn.id
        let initial = modeStore.mode(by: activeID) ?? modeStore.noteTakerBuiltIn
        sessionRecorder.startSession(initialMode: initial)

        accumulator = ChunkAccumulator { [weak self] paragraph in
            guard let self, let client = self.llm else { return }
            await self.handleLLM(chunk: paragraph, client: client)
        }

        mainTask = Task { [weak self] in
            await self?.run(capture: cap, transcriber: t, client: client)
        }
    }

    func stop() {
        mainTask?.cancel()
        mainTask = nil
        Task { [weak capture] in await capture?.stop() }
        capture = nil
        transcriber = nil
        llm = nil
        accumulator?.cancel()
        accumulator = nil
        vm.isRunning = false
        vm.setStatus("stopped")
        let recorder = sessionRecorder
        let hook = postSessionHook
        Task { @MainActor in
            do {
                let session = try recorder.endSession()
                await hook?(session)
            } catch {
                NSLog("session end: %@", error.localizedDescription)
            }
        }
    }

    private func run(capture: AudioCapture,
                     transcriber: Transcriber,
                     client: LLMClient) async {
        do {
            try await transcriber.warmup()
            vm.setStatus("listening")
            try await capture.start()
        } catch {
            NSLog("Pipeline start failed: \(error.localizedDescription)")
            let msg = error.localizedDescription
            if msg.lowercased().contains("tcc") || msg.lowercased().contains("declined") {
                vm.setStatus("Grant Screen Recording in System Settings, then click Start again.")
                // Don't auto-retry a denied TCC — user has to re-grant first.
                store.autoStartOnLaunch = false
            } else {
                vm.setStatus("error: \(msg)")
            }
            vm.isRunning = false
            return
        }

        let vad = VADChunker()
        // Tee the capture stream: one side goes to VAD, one to a level meter
        // so we can prove audio is actually arriving.
        let (meterStream, meterCont) = AsyncStream<[Float]>.makeStream()
        let (vadStream, vadCont) = AsyncStream<[Float]>.makeStream()
        let forwarder = Task {
            var frameCount = 0
            var maxRms: Float = 0
            var lastLog = Date()
            for await block in capture.samples {
                meterCont.yield(block)
                vadCont.yield(block)
                frameCount += 1
                var sum: Float = 0
                for v in block { sum += v * v }
                let rms = (sum / Float(max(block.count, 1))).squareRoot()
                if rms > maxRms { maxRms = rms }
                if Date().timeIntervalSince(lastLog) > 3 {
                    NSLog("audio: %d blocks last 3s, peak rms=%.4f (VAD threshold=0.01)",
                          frameCount, maxRms)
                    frameCount = 0; maxRms = 0; lastLog = Date()
                }
            }
            meterCont.finish()
            vadCont.finish()
        }
        _ = meterStream  // consumed by the above task only for logging

        let chunks = vad.chunks(from: vadStream)
        for await chunk in chunks {
            if Task.isCancelled { break }
            NSLog("vad: emitting chunk, %.2fs", Double(chunk.count) / 16000.0)
            do {
                let text = try await transcriber.transcribe(chunk)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                NSLog("transcribe -> %@", trimmed.isEmpty ? "<empty>" : trimmed)
                sessionRecorder.recordTranscript(trimmed,
                    durationMs: Int((Double(chunk.count) / 16000.0) * 1000.0))
                if trimmed.count < 2 { continue }
                await dispatchChunk(trimmed, client: client)
            } catch {
                NSLog("transcribe error: \(error.localizedDescription)")
            }
        }
        forwarder.cancel()
    }

    /// Routes a fresh transcript chunk through the active mode's firing
    /// cadence. For `.immediate`, we drain any buffered content first (so a
    /// recent mode switch from debounce → immediate doesn't strand a
    /// paragraph), then fire right away. For `.debounce`, we just append
    /// to the accumulator and let its timer decide when to flush.
    private func dispatchChunk(_ text: String, client: LLMClient) async {
        let activeID = store.activeModeID ?? modeStore.noteTakerBuiltIn.id
        let mode = modeStore.mode(by: activeID) ?? modeStore.noteTakerBuiltIn
        DebugLog.write("dispatchChunk: mode=\(mode.name) cadence=\(mode.effectiveFireCadence) text.len=\(text.count)")
        switch mode.effectiveFireCadence {
        case .immediate:
            await accumulator?.flushNow()
            await handleLLM(chunk: text, client: client)
        case .debounce(let seconds):
            accumulator?.append(text, delaySeconds: seconds)
        }
    }

    private func handleLLM(chunk: String, client: LLMClient) async {
        // Resolve active mode fresh each call so mid-session mode switches take
        // effect on the very next chunk.
        let activeID = store.activeModeID ?? modeStore.noteTakerBuiltIn.id
        let mode = modeStore.mode(by: activeID) ?? modeStore.noteTakerBuiltIn

        let attached = mode.attachedContextIDs.compactMap { id in
            contextStore.packs.first { $0.id == id }
        }

        let request = LLMRequest(
            chunk: chunk,
            history: history,
            systemPrompt: mode.systemPrompt,
            attachedContexts: attached,
            modelOverride: mode.modelOverride,
            maxTokensOverride: mode.maxTokens
        )

        NSLog("llm: calling %@ mode=%@ contexts=%d",
              String(describing: type(of: client)), mode.name, attached.count)
        vm.clear()
        vm.displayText = ""
        var acc = ""
        var deltaCount = 0
        do {
            for try await delta in client.stream(request) {
                if Task.isCancelled { return }
                deltaCount += 1
                acc += delta
                vm.setResponse(acc)
            }
            NSLog("llm: stream ended, %d deltas, %d total chars", deltaCount, acc.count)
        } catch {
            NSLog("llm error: \(error.localizedDescription)")
            vm.setStatus("LLM error: \(error.localizedDescription)")
            return
        }
        var reply = acc.trimmingCharacters(in: .whitespacesAndNewlines)
        // Post-process Note-taker output to scrub attribution artifacts like
        // "- The speaker says X". Only runs for Note-taker so Teleprompter's
        // first-person voice isn't touched. Gated on the user setting so it
        // can be disabled for debugging the raw model output.
        if store.stripAttribution, mode.name == SeedData.noteTakerBuiltInName {
            let cleaned = AttributionStripper.clean(reply)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned != reply {
                reply = cleaned
                // Reflect the cleaned text on the overlay so the user doesn't
                // see the pre-strip version lingering after streaming ended.
                vm.setResponse(reply)
            }
        }
        if !reply.isEmpty {
            history.append(ChatTurn(role: "user", content: userMessage(for: chunk)))
            history.append(ChatTurn(role: "assistant", content: reply))
            sessionRecorder.recordReply(reply, label: mode.outputLabel)
            let keep = store.contextPairs * 2
            if history.count > keep { history.removeFirst(history.count - keep) }
        }
    }
}
