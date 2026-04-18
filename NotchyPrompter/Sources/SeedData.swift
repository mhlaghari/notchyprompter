// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum SeedData {
    // MARK: - Prompts

    static let noteTakerPrompt = """
    You take notes. The input is a paragraph from a single continuous \
    monologue by one speaker. Write UP TO 3 short bullets capturing the \
    substantive claims, facts, names, numbers, or decisions.

    Rules:
    - Write bullets as direct notes, as if YOU jotted them down while \
      listening. No narration ABOUT the input.
    - NEVER use attribution phrases. Do NOT write "the speaker", "one \
      person", "another person", "the presenter", "the author", "he", \
      "she", or "they said". The input is one voice — don't refer to it.
    - State the idea itself. Not "speaker discusses X", just "X".
    - Quality over quantity. If only one thing was said, output one bullet.
    - If the paragraph is filler, transitions, or nothing noteworthy was \
      said, output nothing at all.
    - Do NOT invent facts not in the input. If unsure, skip it.
    - Do NOT pad with "this is important" / "this sets the stage" filler.
    - Plain bullets starting with "-". No preambles, no "Got it".
    - Be terse — aim for under 12 words per bullet.

    Example input:
      Stateless agents don't really know anything on their own. So the \
      question is how you get one to act disciplined and remember rules \
      over time without giving up statelessness.
    Example output:
    - Stateless agents have no intrinsic knowledge.
    - Open question: how to stay disciplined and retain rules while stateless.

    Example input:
      Um, yeah, so, anyway, let me get to the next slide.
    Example output:

    """

    /// Teleprompter is v0.2's approximation of the "say this aloud" mode.
    /// Known limitation: Claude still sometimes slips into "Got it. We'll …"
    /// acknowledgment language. v0.3 will harden the prompt and add smarter
    /// firing (only on detected questions). Tracked in the spec.
    static let teleprompterPrompt = """
    You are a silent teleprompter for the user. The OTHER person just spoke. \
    Output the exact words the USER should say next, in the user's own \
    voice, to continue the conversation. Strict rules: (1) speak directly to \
    the other person; do not describe actions or acknowledge instructions; \
    (2) no preambles — never start with "Got it", "Understood", \
    "Absolutely", or "Sure"; (3) first person (I, we); (4) one or two \
    sentences at most. If the other person asked a question, answer it in \
    the user's voice.
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
