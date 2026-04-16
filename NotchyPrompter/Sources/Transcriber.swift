import Foundation
import WhisperKit

/// Lazy WhisperKit wrapper. First call downloads the model from
/// HuggingFace (`argmaxinc/whisperkit-coreml/<model>`) into
/// `~/Library/Application Support/…` — expect a 30–90 s stall on first run.
actor Transcriber {
    private let modelName: String
    private var kit: WhisperKit?

    init(modelName: String = "openai_whisper-large-v3-v20240930_turbo") {
        self.modelName = modelName
    }

    func warmup() async throws {
        if kit != nil { return }
        NSLog("Transcriber: loading %@ …", modelName)
        let t0 = Date()
        let k = try await WhisperKit(WhisperKitConfig(
            model: modelName,
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        ))
        // Burn one silent inference so the first real chunk is fast.
        _ = try? await k.transcribe(audioArray: Array(repeating: Float(0), count: 16_000))
        self.kit = k
        NSLog("Transcriber: ready (%.1fs)", -t0.timeIntervalSinceNow)
    }

    func transcribe(_ audio: [Float]) async throws -> String {
        if kit == nil { try await warmup() }
        guard let k = kit else { return "" }
        let results = try await k.transcribe(audioArray: audio)
        let text = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}
