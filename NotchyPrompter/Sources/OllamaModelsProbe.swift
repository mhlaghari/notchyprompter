// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Lists models already pulled into a local Ollama daemon by hitting
/// `GET /api/tags`. Used to populate the Settings model picker and for
/// pre-flight validation before the pipeline starts streaming.
struct OllamaModelsProbe {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    enum ProbeError: Error, LocalizedError, Equatable {
        case unreachable(String)
        case notFound
        case badStatus(Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .unreachable(let msg):
                return "Couldn't reach Ollama: \(msg)"
            case .notFound:
                return "Ollama responded 404 (is `/api/tags` served?)"
            case .badStatus(let code):
                return "Ollama returned HTTP \(code)"
            case .malformed:
                return "Ollama returned malformed JSON"
            }
        }
    }

    /// Fetches the installed model list. Returns names as Ollama reports them
    /// (e.g. `qwen3.5:2b`). Sorted alphabetically for stable UI.
    func listInstalled() async throws -> [String] {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        req.httpMethod = "GET"
        req.timeoutInterval = 5

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ProbeError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.unreachable("no HTTP response")
        }
        if http.statusCode == 404 { throw ProbeError.notFound }
        guard 200..<300 ~= http.statusCode else {
            throw ProbeError.badStatus(http.statusCode)
        }

        return try Self.parseNames(data)
    }

    /// Exposed for tests: decodes the `/api/tags` body into sorted model names.
    static func parseNames(_ data: Data) throws -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]]
        else {
            throw ProbeError.malformed
        }
        let names = models.compactMap { $0["name"] as? String }
        return names.sorted()
    }
}
