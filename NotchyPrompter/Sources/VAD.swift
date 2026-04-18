import Foundation

/// Energy-based silence detector over a 16 kHz mono Float stream.
///
/// Emits a chunk (the buffered speech + trailing silence) once the speaker
/// has produced ≥ `minSpeechMs` of speech followed by ≥ `trailingSilenceMs`
/// of silence. Also flushes if the buffer exceeds `maxChunkMs`.
///
/// Simpler than webrtcvad and dependency-free; accuracy is plenty for a
/// one-human meeting signal. Threshold is in RMS amplitude (0.0–1.0).
final class VADChunker {
    struct Config {
        var rmsThreshold: Float = 0.01   // ~ -40 dBFS
        var minSpeechMs: Int = 800
        var trailingSilenceMs: Int = 900
        var maxChunkMs: Int = 15_000
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

    /// Convenience init for the common tuning knobs. Other fields use defaults.
    convenience init(minSpeechMs: Int, trailingSilenceMs: Int) {
        var cfg = Config()
        cfg.minSpeechMs = minSpeechMs
        cfg.trailingSilenceMs = trailingSilenceMs
        self.init(cfg)
    }

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

            let flush =
                (inSpeech && speechMs >= cfg.minSpeechMs && silenceMs >= cfg.trailingSilenceMs)
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
