// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Energy-based utterance detector over a 16 kHz mono Float stream.
///
/// Emits a chunk (buffered speech + trailing silence) using a grace-period
/// model: once the speaker has produced ≥ `minSpeechMs` of speech, we wait
/// `endOfUtteranceGraceMs` of continuous silence before flushing. If speech
/// resumes inside the grace window, the existing buffer keeps growing — so a
/// rapid speaker's sub-grace breaths concatenate into a single paragraph-sized
/// chunk instead of splitting mid-sentence.
///
/// Also flushes unconditionally if the buffer exceeds `maxChunkMs` to bound
/// latency on pathological monologues.
///
/// Threshold is RMS amplitude (0.0–1.0). Dependency-free; accuracy is fine for
/// a single-speaker signal. See `docs/superpowers/research-2026-04-19-m13v-feedback.md`
/// for the endpointing literature and why this shape beats wall-clock debounce.
final class VADChunker {
    struct Config {
        var rmsThreshold: Float = 0.01        // ~ -40 dBFS
        var minSpeechMs: Int = 800            // gate coughs / throat-clears
        var endOfUtteranceGraceMs: Int = 1200 // hangover before commit
        var maxChunkMs: Int = 15_000          // hard cap, same as before
        var sampleRate: Int = 16_000
        var frameMs: Int = 30
    }

    private let cfg: Config
    private var leftover: [Float] = []
    private var buffer: [Float] = []
    private var speechMs = 0
    private var silenceMs = 0
    private var totalMs = 0
    private var inSpeech = false

    init(_ cfg: Config = .init()) { self.cfg = cfg }

    var frameLen: Int { cfg.sampleRate * cfg.frameMs / 1000 }

    /// Consume an async stream of Float arrays; emit speech chunks.
    func chunks(from source: AsyncStream<[Float]>) -> AsyncStream<[Float]> {
        AsyncStream<[Float]> { continuation in
            let task = Task {
                for await incoming in source {
                    if Task.isCancelled { break }
                    self.process(incoming, emit: { continuation.yield($0) })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Internal testing seam — drives the synchronous frame loop directly so
    /// unit tests can feed deterministic buffers without spinning an AsyncStream.
    func processForTest(_ incoming: [Float], emit: ([Float]) -> Void) {
        process(incoming, emit: emit)
    }

    private func process(_ incoming: [Float], emit: ([Float]) -> Void) {
        var stream = leftover
        stream.append(contentsOf: incoming)
        let len = frameLen
        let n = stream.count / len
        guard n > 0 else {
            leftover = stream
            return
        }
        let consumed = n * len
        leftover = Array(stream.suffix(from: consumed))

        for i in 0..<n {
            let start = i * len
            let frame = Array(stream[start..<(start + len)])
            let rms = Self.rms(frame)
            let isSpeech = rms >= cfg.rmsThreshold

            if isSpeech {
                // Speech inside the grace window cancels the pending emission
                // — silenceMs resets to 0, buffer continues to grow.
                inSpeech = true
                speechMs += cfg.frameMs
                silenceMs = 0
                buffer.append(contentsOf: frame)
                totalMs += cfg.frameMs
            } else if inSpeech {
                buffer.append(contentsOf: frame)
                totalMs += cfg.frameMs
                silenceMs += cfg.frameMs
            }

            // Commit when grace has elapsed on a real utterance, or on hard cap.
            let flush =
                (inSpeech
                 && speechMs >= cfg.minSpeechMs
                 && silenceMs >= cfg.endOfUtteranceGraceMs)
                || (inSpeech && totalMs >= cfg.maxChunkMs)

            if flush {
                emit(buffer)
                buffer.removeAll(keepingCapacity: true)
                speechMs = 0
                silenceMs = 0
                totalMs = 0
                inSpeech = false
            }
        }
    }

    private static func rms(_ x: [Float]) -> Float {
        if x.isEmpty { return 0 }
        var sum: Float = 0
        for v in x { sum += v * v }
        return (sum / Float(x.count)).squareRoot()
    }
}
