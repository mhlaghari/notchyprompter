// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// One-shot non-streaming LLM call that turns a Session's transcript/reply
/// log into a recap. Reuses the user's configured LLMClient so they don't
/// need a separate key/backend for summaries.
@MainActor
struct SummaryGenerator {
    let client: LLMClient

    /// Renders the session's events as a transcript log suitable for the
    /// summary prompt.
    static func transcriptText(for session: Session) -> String {
        var out: [String] = []
        let df = ISO8601DateFormatter()
        for e in session.events {
            switch e.kind {
            case .mode:
                out.append("[mode: \(e.modeName ?? "?")]")
            case .transcript:
                out.append("[\(df.string(from: e.t))] them: \(e.text ?? "")")
            case .reply:
                out.append("[\(df.string(from: e.t))] me:   \(e.text ?? "")")
            }
        }
        return out.joined(separator: "\n")
    }

    /// Runs a non-streaming summary. Returns the concatenated reply text.
    func run(prompt: String, session: Session) async throws -> String {
        let transcript = Self.transcriptText(for: session)
        let request = LLMRequest(
            chunk: transcript,
            history: [],
            systemPrompt: prompt,
            attachedContexts: [],
            modelOverride: nil,
            maxTokensOverride: 800
        )
        var acc = ""
        for try await delta in client.stream(request) {
            acc += delta
        }
        return acc.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
