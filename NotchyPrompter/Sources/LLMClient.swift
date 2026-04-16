import Foundation

enum LLMBackend: String, CaseIterable, Identifiable, Codable {
    case claude
    case ollama
    var id: String { rawValue }
    var display: String { self == .claude ? "Claude" : "Ollama (local)" }
}

struct ChatTurn: Codable, Equatable {
    let role: String  // "user" | "assistant"
    let content: String
}

let systemPrompt = """
You are a silent meeting copilot. Give me 1-2 concise bullet points I should \
respond with or be aware of based on what the other person just said. Be \
extremely brief.
"""

func userMessage(for chunk: String) -> String {
    "The other person just said: '\(chunk.trimmingCharacters(in: .whitespacesAndNewlines))'"
}

/// Streams text deltas for the assistant's reply.
protocol LLMClient: Sendable {
    func stream(chunk: String, history: [ChatTurn]) -> AsyncThrowingStream<String, Error>
}
