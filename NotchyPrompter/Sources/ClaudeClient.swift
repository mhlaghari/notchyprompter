import Foundation

/// Minimal Anthropic Messages API streaming client via URLSession + SSE.
/// Uses prompt caching on the system prompt plus up to 3 attached context
/// blocks (Anthropic caps cache_control at 4 breakpoints per request).
struct ClaudeClient: LLMClient {
    let apiKey: String
    let model: String             // default model; overridden per-request if set
    let maxTokens: Int            // default; overridden per-request if set
    let apiVersion: String = "2023-06-01"
    private static let maxCacheBreakpoints = 4  // total across system blocks

    /// Builds the `system` array payload. Exposed for unit tests.
    static func systemBlocks(for request: LLMRequest) -> [[String: Any]] {
        let systemBlock: [String: Any] = [
            "type": "text",
            "text": request.systemPrompt,
            "cache_control": ["type": "ephemeral"],
        ]
        // Remaining breakpoints after the system block.
        let budget = maxCacheBreakpoints - 1
        let ctx = request.attachedContexts
        if ctx.count <= budget {
            return [systemBlock] + ctx.map {
                [
                    "type": "text",
                    "text": $0.body,
                    "cache_control": ["type": "ephemeral"],
                ]
            }
        }
        // First (budget - 1) get their own blocks; the rest are concatenated
        // into the final block (which still gets a cache breakpoint).
        var blocks: [[String: Any]] = [systemBlock]
        let solo = ctx.prefix(budget - 1)
        for c in solo {
            blocks.append([
                "type": "text",
                "text": c.body,
                "cache_control": ["type": "ephemeral"],
            ])
        }
        let tail = ctx.dropFirst(budget - 1)
            .map { $0.body }
            .joined(separator: "\n\n---\n\n")
        blocks.append([
            "type": "text",
            "text": tail,
            "cache_control": ["type": "ephemeral"],
        ])
        return blocks
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    req.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

                    let body: [String: Any] = [
                        "model": request.modelOverride ?? model,
                        "max_tokens": request.maxTokensOverride ?? maxTokens,
                        "stream": true,
                        "system": Self.systemBlocks(for: request),
                        "messages": (request.history.map { ["role": $0.role, "content": $0.content] })
                            + [["role": "user", "content": userMessage(for: request.chunk)]],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw NSError(domain: "Claude", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "no HTTP response"])
                    }
                    guard 200..<300 ~= http.statusCode else {
                        var errBody = ""
                        for try await line in bytes.lines { errBody += line + "\n" }
                        throw NSError(domain: "Claude", code: http.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey: errBody])
                    }

                    var currentEvent: String? = nil
                    for try await line in bytes.lines {
                        if line.isEmpty { currentEvent = nil; continue }
                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst("event:".count))
                                .trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        if line.hasPrefix("data:") {
                            let payload = String(line.dropFirst("data:".count))
                                .trimmingCharacters(in: .whitespaces)
                            guard let data = payload.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data)
                                        as? [String: Any]
                            else { continue }

                            if currentEvent == "content_block_delta",
                               let delta = obj["delta"] as? [String: Any],
                               let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(text)
                            }
                            if currentEvent == "message_stop" { break }
                            if currentEvent == "error",
                               let errObj = obj["error"] as? [String: Any],
                               let msg = errObj["message"] as? String {
                                throw NSError(domain: "Claude", code: -2,
                                              userInfo: [NSLocalizedDescriptionKey: msg])
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
