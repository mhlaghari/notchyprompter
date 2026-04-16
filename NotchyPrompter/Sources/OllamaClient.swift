import Foundation

/// Ollama chat streaming via newline-delimited JSON over HTTP.
struct OllamaClient: LLMClient {
    let baseURL: URL       // e.g. http://localhost:11434
    let model: String
    let maxTokens: Int

    func stream(chunk: String, history: [ChatTurn]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "content-type")

                    var messages: [[String: String]] = [
                        ["role": "system", "content": systemPrompt]
                    ]
                    messages.append(contentsOf: history.map { ["role": $0.role, "content": $0.content] })
                    messages.append(["role": "user", "content": userMessage(for: chunk)])

                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true,
                        // Disable thinking mode for reasoning-capable models
                        // (qwen3.x, deepseek-r1, etc.) so content tokens
                        // start streaming immediately instead of after the
                        // model finishes its hidden chain-of-thought.
                        "think": false,
                        "options": ["num_predict": maxTokens],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw NSError(domain: "Ollama", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "no HTTP response"])
                    }
                    guard 200..<300 ~= http.statusCode else {
                        throw NSError(domain: "Ollama", code: http.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey:
                                                    "Ollama returned HTTP \(http.statusCode). Is `ollama serve` running?"])
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data)
                                    as? [String: Any] else { continue }
                        if let done = obj["done"] as? Bool, done { break }
                        if let msg = obj["message"] as? [String: Any],
                           let text = msg["content"] as? String, !text.isEmpty {
                            continuation.yield(text)
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
