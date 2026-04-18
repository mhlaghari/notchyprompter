import Foundation

enum LLMBackend: String, CaseIterable, Identifiable, Codable {
    case claude
    case ollama
    var id: String { rawValue }
    var display: String { self == .claude ? "Claude" : "Ollama (local)" }
}

struct ChatTurn: Codable, Equatable {
    let role: String
    let content: String
}

/// What the pipeline hands to an LLMClient on each user chunk.
struct LLMRequest {
    let chunk: String
    let history: [ChatTurn]
    let systemPrompt: String
    let attachedContexts: [ContextPack]
    let modelOverride: String?
    let maxTokensOverride: Int?
}

func userMessage(for chunk: String) -> String {
    "The other person just said: '\(chunk.trimmingCharacters(in: .whitespacesAndNewlines))'"
}

protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}
