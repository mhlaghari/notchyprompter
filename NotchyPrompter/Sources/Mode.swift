// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct ModeDefaults: Codable, Equatable {
    let name: String
    let systemPrompt: String
}

/// When a Mode decides to fire an LLM call.
///
/// - `immediate`: fire on every transcript chunk (v0.2.0 behaviour). Cheap
///   per-chunk reactions. Noisy for long-form listening.
/// - `debounce(seconds:)`: accumulate chunks into a paragraph, fire once
///   after the speaker has been silent for the given duration. Suited to
///   note-taking or recap modes where per-sentence output is too chatty.
enum FireCadence: Codable, Equatable {
    case immediate
    case debounce(seconds: Double)
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
    /// Optional override. When nil, `effectiveFireCadence` derives a sensible
    /// default from the mode's role (Note-taker → debounce; others → immediate).
    var fireCadence: FireCadence? = nil

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

    /// The cadence actually used at runtime. Falls back to Note-taker's
    /// paragraph-debounce default when no explicit cadence is set, so
    /// modes.json written by older versions get the new behaviour for free.
    var effectiveFireCadence: FireCadence {
        if let c = fireCadence { return c }
        if name == "Note-taker" { return .debounce(seconds: 2.0) }
        return .immediate
    }
}
