import Foundation

struct ModeDefaults: Codable, Equatable {
    let name: String
    let systemPrompt: String
}

struct Mode: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var attachedContextIDs: [UUID]
    var modelOverride: String?
    var maxTokens: Int?
    let isBuiltIn: Bool
    let defaults: ModeDefaults?

    /// True when the user has edited a built-in away from its seeded values.
    var isDirty: Bool {
        guard let d = defaults else { return false }
        return d.name != name || d.systemPrompt != systemPrompt
    }

    /// Returns self with name + systemPrompt snapped back to defaults.
    /// Preserves user's attached contexts / overrides on purpose — those are
    /// user decisions, not part of the "factory" mode.
    func resetToDefaults() -> Mode {
        guard let d = defaults else { return self }
        var copy = self
        copy.name = d.name
        copy.systemPrompt = d.systemPrompt
        return copy
    }
}
