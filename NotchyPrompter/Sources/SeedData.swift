// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum SeedData {
    static let watchingPrompt = """
    You are a silent meeting copilot. Give me 1-2 concise bullet points I \
    should respond with or be aware of based on what the other person just \
    said. Be extremely brief.
    """

    static let meetingPrompt = """
    You are a silent meeting copilot. Draft a concise first-person response \
    I can say out loud right now, grounded in any attached context notes. \
    Use bullets only if the other person asked a multi-part question. Be \
    extremely brief — one or two sentences at most.
    """

    static let interviewPrompt = """
    You are a silent interview copilot. Draft a concise first-person answer \
    to the interviewer's question, grounded in the attached résumé and job \
    description. If the question is behavioural, lead with STAR structure. \
    One or two sentences.
    """

    static let presentingPrompt = """
    You are a silent presentation copilot. The audience just asked a \
    question. Draft a concise first-person answer suitable for a live \
    presentation, grounded in the attached deck notes. One or two sentences.
    """

    static let summaryPrompt = """
    You are given a transcript and reply log from a meeting. Produce a \
    concise recap: what was discussed, decisions made, action items (who \
    owes what by when if stated), and open questions. Markdown.
    """

    static func initialModes() -> [Mode] {
        let watching = Mode(
            id: UUID(),
            name: "Watching",
            systemPrompt: watchingPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Watching", systemPrompt: watchingPrompt)
        )
        let meeting = Mode(
            id: UUID(),
            name: "Meeting",
            systemPrompt: meetingPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Meeting", systemPrompt: meetingPrompt)
        )
        let custom = Mode(
            id: UUID(),
            name: "Custom",
            systemPrompt: "",
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Custom", systemPrompt: "")
        )
        let interview = Mode(
            id: UUID(),
            name: "Interview",
            systemPrompt: interviewPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: false,
            defaults: nil
        )
        let presenting = Mode(
            id: UUID(),
            name: "Presenting",
            systemPrompt: presentingPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: false,
            defaults: nil
        )
        return [watching, meeting, custom, interview, presenting]
    }

    /// ID used by callers that want to look up the Watching built-in by name
    /// for initial `activeModeID`. We re-derive it at runtime from ModeStore
    /// rather than hardcoding, since the seeded UUIDs are fresh per install.
    static let watchingBuiltInName = "Watching"
}
