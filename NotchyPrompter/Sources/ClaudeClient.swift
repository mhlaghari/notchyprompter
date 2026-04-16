import Foundation

/// Minimal Anthropic Messages API streaming client via URLSession + SSE.
/// Uses prompt caching on the static system message (ephemeral, 5-min TTL).
struct ClaudeClient: LLMClient {
    let apiKey: String
    let model: String
    let maxTokens: Int
    let apiVersion: String = "2023-06-01"

    func stream(chunk: String, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
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
                        "model": model,
                        "max_tokens": maxTokens,
                        "stream": true,
                        "system": [[
                            "type": "text",
                            "text": systemPrompt,
                            "cache_control": ["type": "ephemeral"],
                        ]],
                        "messages": (history.map { ["role": $0.role, "content": $0.content] })
                            + [["role": "user", "content": userMessage(for: chunk)]],
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
                               let text = delta["text"] as? String,
                               !text.isEmpty {
                                continuation.yield(text)
                            }
                            if currentEvent == "message_stop" {
                                break
                            }
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
