// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum SeedData {
    // MARK: - Prompts

    static let noteTakerPrompt = """
    You are a silent note-taker. The user is watching a video or attending \
    a presentation. The input below is a paragraph of transcribed speech.

    Write UP TO 3 short bullets capturing the substantive claims, facts, \
    names, numbers, or decisions in this paragraph.

    Rules:
    - Quality over quantity. If only one thing was said, output one bullet.
    - If the paragraph is filler, transitions, or the speaker hasn't said \
      anything noteworthy yet, output nothing at all.
    - Do NOT restate the speaker's sentence structure. Distill.
    - Do NOT invent facts not in the input. If unsure, skip it.
    - Do NOT pad with "this is important" / "this sets the stage" filler.
    - Plain bullets starting with "-". No preambles, no "Got it".
    - Be terse — aim for under 12 words per bullet.
    """

    /// v0.3 Teleprompter prompt. The v0.2 prompt reliably produced
    /// acknowledgment-language slippage ("Got it. We'll set up comments…")
    /// because "first-person response I can say out loud" reads as "reply
    /// from Claude-the-assistant" under Claude's training distribution.
    ///
    /// This rewrite:
    /// - Phrases as a direct imperative (`Reply with EXACTLY …`) instead of
    ///   describing the assistant's role, which reduces role-play drift.
    /// - Expands the explicit deny-list of acknowledgment tokens ("Got it",
    ///   "Okay", "Yeah", "Right" etc.) so the first-token distribution is
    ///   pushed away from filler.
    /// - Names "silence or a single word" as legitimate outputs so the model
    ///   doesn't feel obligated to produce a full sentence on every chunk.
    /// - Drops "first-person (I, we)" phrasing — empirically Claude latches
    ///   onto that as "first-person assistant voice" rather than "user's
    ///   own voice speaking to the other person".
    ///
    /// See docs/superpowers/specs/2026-04-18-teleprompter-v0.3-addendum.md.
    static let teleprompterPrompt = """
    The other person said: `<chunk>`. Reply with EXACTLY what the user \
    should say back to them — nothing else. Do not acknowledge them \
    first. Do not summarise what they said. Do not describe what the \
    user will do. Do not start with "Got it", "Understood", \
    "Absolutely", "Sure", "Okay", "Yeah", "Right". Start directly with \
    the words the user speaks. If the user's best response is silence \
    or a single word, return a single word. If the other person asked \
    a question, answer it in the user's voice, grounded in attached \
    context. Be extremely brief — one sentence unless the question \
    genuinely requires two.
    """

    static let summaryPrompt = """
    You are given a transcript and reply log from a meeting. Produce a \
    concise recap: what was discussed, decisions made, action items (who \
    owes what by when if stated), and open questions. Markdown.
    """

    // MARK: - Built-in names

    static let noteTakerBuiltInName = "Note-taker"
    static let teleprompterBuiltInName = "Teleprompter"
    static let customBuiltInName = "Custom"

    // MARK: - Initial seed

    static func initialModes() -> [Mode] {
        let noteTaker = Mode(
            id: UUID(),
            name: noteTakerBuiltInName,
            systemPrompt: noteTakerPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: noteTakerBuiltInName,
                                   systemPrompt: noteTakerPrompt),
            fireCadence: .debounce(seconds: 2.0)
        )
        let teleprompter = Mode(
            id: UUID(),
            name: teleprompterBuiltInName,
            systemPrompt: teleprompterPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: teleprompterBuiltInName,
                                   systemPrompt: teleprompterPrompt),
            fireCadence: .immediate
        )
        let custom = Mode(
            id: UUID(),
            name: customBuiltInName,
            systemPrompt: "",
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: customBuiltInName, systemPrompt: ""),
            fireCadence: .immediate
        )
        return [noteTaker, teleprompter, custom]
    }

    // MARK: - Legacy migration

    /// Names used by the v0.2.0 seed. Migrated in place on load.
    static let legacyNoteTakerName = "Watching"
    static let legacyTeleprompterName = "Meeting"
}
