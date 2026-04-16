import Foundation
import Security
import SwiftUI

/// Persistent user settings. API key lives in Keychain; other knobs in
/// UserDefaults. `@MainActor` so SwiftUI bindings are safe.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("backend") private var backendRaw: String = LLMBackend.claude.rawValue
    @AppStorage("claudeModel") var claudeModel: String = "claude-haiku-4-5-20251001"
    @AppStorage("ollamaModel") var ollamaModel: String = "llama3.2:3b"
    @AppStorage("ollamaURL") var ollamaURL: String = "http://localhost:11434"
    @AppStorage("whisperModel") var whisperModel: String =
        "openai_whisper-large-v3-v20240930_turbo"
    @AppStorage("maxTokens") var maxTokens: Int = 120
    @AppStorage("contextPairs") var contextPairs: Int = 5
    @AppStorage("autoStartOnLaunch") var autoStartOnLaunch: Bool = false

    @Published var apiKey: String = "" {
        didSet { try? Keychain.set(apiKey, service: Self.kcService, account: Self.kcAccount) }
    }

    var backend: LLMBackend {
        get { LLMBackend(rawValue: backendRaw) ?? .claude }
        set { backendRaw = newValue.rawValue }
    }

    /// `true` when the current configuration can actually run.
    var isRunnable: Bool {
        switch backend {
        case .claude: return !apiKey.isEmpty
        case .ollama: return URL(string: ollamaURL) != nil
        }
    }

    private static let kcService = "com.mhlaghari.notchyprompter"
    private static let kcAccount = "anthropic-api-key"

    private init() {
        if let stored = try? Keychain.get(service: Self.kcService, account: Self.kcAccount) {
            _apiKey = Published(initialValue: stored)
        }
    }

    func buildClient() -> LLMClient? {
        switch backend {
        case .claude:
            guard !apiKey.isEmpty else { return nil }
            return ClaudeClient(apiKey: apiKey, model: claudeModel, maxTokens: maxTokens)
        case .ollama:
            guard let url = URL(string: ollamaURL) else { return nil }
            return OllamaClient(baseURL: url, model: ollamaModel, maxTokens: maxTokens)
        }
    }
}

/// Tiny Keychain shim — generic password, single service/account pair.
enum Keychain {
    static func set(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return }  // deletion only
        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func get(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return String(data: data, encoding: .utf8)
    }
}
