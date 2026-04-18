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
/// - `silent`: never fire the LLM during the session. Transcript is still
///   recorded, and the live transcript is routed to the overlay so the
///   user sees what's being captured. A single post-hoc summary fires on
///   Stop via `autoSummarizeOnStop`. This is the Note-taker default —
///   per-chunk firing produced redundant per-fragment paraphrases because
///   the LLM never saw the arc.
enum FireCadence: Codable, Equatable {
    case immediate
    case debounce(seconds: Double)
    case silent
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

    /// The cadence actually used at runtime.
    ///
    /// Note-taker is always `.silent` regardless of the stored `fireCadence`
    /// value — gated on `defaults.name` so user renames don't break the rule.
    /// This overrides any legacy stored cadence (e.g. the v0.2.1 `.debounce(2.0)`
    /// seed) without a modes.json migration, so existing installs pick up the
    /// transcript-primary behaviour on upgrade.
    ///
    /// For other modes, the stored value wins if set; otherwise default to
    /// `.immediate` (the v0.2 behaviour).
    var effectiveFireCadence: FireCadence {
        if defaults?.name == "Note-taker" { return .silent }
        if let c = fireCadence { return c }
        return .immediate
    }

    /// Label written to session logs for this mode's LLM output. Reflects what
    /// the LLM is actually producing so a reader doesn't mistake the line for
    /// something the user said:
    ///   - Note-taker → `notes`  (bullets about what was said)
    ///   - Teleprompter → `draft` (first-person replies to speak)
    ///   - anything else → `ai`   (generic LLM output)
    var outputLabel: String {
        switch name {
        case "Note-taker": return "notes"
        case "Teleprompter": return "draft"
        default: return "ai"
        }
    }
}
