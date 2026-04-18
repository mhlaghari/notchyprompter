# Modes, Context Packs, and Session Capture — Design (v0.2)

**Date:** 2026-04-18
**Target release:** NotchyPrompter v0.2
**Status:** approved design, ready for implementation plan

## Problem

NotchyPrompter v0.1 has a single hardcoded system prompt ("summarize what the
other person said in 1–2 bullets"). That works for passively watching videos
but not for the use cases that make the tool genuinely useful on a live call:
drafting a first-person reply, answering an audience question during a
presentation, or grounding responses in the user's own notes.

v0.2 introduces three building blocks:

1. **Modes** — named presets that bundle a system prompt with a set of
   attached context packs. The user switches modes mid-session from the menu
   bar.
2. **Context packs** — plain-markdown notes (résumé, product brief, meeting
   prep) the user authors once and attaches to the modes that need them.
3. **Session capture** — every Start→Stop cycle is persisted as a JSON file;
   an auto-summary is generated on Stop, and the user can re-summarise later
   with a different prompt.

This spec covers v0.2 only. Slide-aware presenting (OCR / Keynote tap) is
explicitly out of scope and deferred to a future spec.

## Goals

- User can configure a mode per scenario (watching, meeting, custom) and
  switch between them from the menu bar without stopping the pipeline.
- User can author context packs and attach them per-mode so responses are
  grounded in their own source material.
- Every listening session is captured to disk with transcript, LLM replies,
  and mode changes, so it can be summarised on demand.
- v0.1 behaviour is preserved for existing users (default mode = Watching,
  which is today's prompt).

## Non-goals

- Slide-awareness (screen OCR, Keynote/PowerPoint integration).
- In-app session browser, search, delete UI, or cloud sync.
- Multi-speaker diarisation.
- Auto-detecting mode based on the frontmost application.
- Team sharing of modes or contexts.

## User-facing design

### Menu bar

The existing menu stays, gets a `Mode` submenu and two session items:

```
NotchyPrompter
├── Start Listening / Stop Listening
├── ─────────
├── Mode: Meeting ▸
│   ├── ✓ Watching
│   │   Meeting
│   │   Custom
│   ├── ─────────
│   │   Interview           (seeded custom)
│   │   Presenting          (seeded custom)
│   │   …user customs
│   └── ─────────
│       Edit Modes…
├── ─────────
├── Summarize Last Session…     (enabled iff ≥1 session exists)
├── Open Sessions Folder
├── ─────────
├── Settings…
└── Quit NotchyPrompter
```

- Clicking a mode switches the active mode immediately. If a session is
  running, the switch is recorded as an event in that session (the session
  does *not* end).
- "Edit Modes…" opens Settings focused on the Modes tab.

### Settings window

Today's single-form Settings becomes tabbed:

```
┌─ Backend ──┬─ Modes ──┬─ Contexts ──┬─ About ─┐
```

- **Backend tab** — today's content: LLM picker, API key, model fields,
  transcription model, context pairs, max tokens, status, Start/Stop. No
  behavioural change.
- **Modes tab** — list on left (built-ins at top with a lock icon meaning
  "can edit, cannot delete"; customs below). Right pane edits the selected
  mode: name, system prompt (multi-line textarea), attached contexts
  (checkbox list of available packs), model override (optional, falls back
  to the Backend tab's model), max output tokens. Built-ins have a
  "Reset to Default" button. Buttons: Add, Duplicate, Delete (customs only).
- **Contexts tab** — list of context packs on left, markdown editor on
  right with title field + body. Buttons: Add, Delete, Reveal in Finder.
- **About tab** — version, licence, link to repo. (Minor, can be deferred.)

### Overlay

The overlay itself does not change structurally. Mode-specific styling
lives entirely in the prompt, not in the UI — a "bullet" response and a
"first-person draft" response both render as plain text in the pill. The
overlay already auto-hides after 9 s and supports multi-line; that's
sufficient for both styles.

## Data model

### Mode

```swift
struct Mode: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var attachedContextIDs: [UUID]   // references ContextPack.id
    var modelOverride: String?       // nil = use SettingsStore.<backend>Model
    var maxTokens: Int?              // nil = use SettingsStore.maxTokens
    let isBuiltIn: Bool              // Watching, Meeting, Custom → true
    let defaults: ModeDefaults?      // populated iff isBuiltIn; used by Reset
}

struct ModeDefaults: Codable, Equatable {
    let name: String
    let systemPrompt: String
    // attachedContextIDs intentionally NOT in defaults — attached contexts
    // are always a user choice.
}
```

### Context pack

```swift
struct ContextPack: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var body: String        // markdown; passed verbatim to the LLM
}
```

Persisted one per file at:

```
~/Library/Application Support/NotchyPrompter/contexts/<id>.md
```

File format — YAML frontmatter for title + id, body below:

```markdown
---
id: 0a3e...-...
title: Résumé — 2026
---

# Mohammad Laghari
…markdown body…
```

Rationale: frontmatter keeps the id stable when the user renames, and makes
the file self-describing if the user browses the folder directly. `id` in
frontmatter is the source of truth; if a file is dropped in externally
without an `id`, NotchyPrompter generates one and rewrites the file on first
load.

### Session

One JSON file per Start→Stop cycle at:

```
~/Library/Application Support/NotchyPrompter/sessions/YYYY-MM-DD-HHMMSS.json
```

If the user starts two sessions within the same second (theoretically
possible — stop-and-immediate-restart), the filename gains a `-N` suffix
(`…-HHMMSS-2.json`). Session `id` matches the filename stem.

```jsonc
{
  "id": "2026-04-18-143022",
  "startedAt": "2026-04-18T14:30:22Z",
  "endedAt":   "2026-04-18T15:12:04Z",
  "events": [
    { "t": "2026-04-18T14:30:22Z", "kind": "mode",       "modeId": "…uuid…", "modeName": "Meeting" },
    { "t": "2026-04-18T14:30:37Z", "kind": "transcript", "text": "So tell me about the migration you led…", "durationMs": 4200 },
    { "t": "2026-04-18T14:30:41Z", "kind": "reply",      "text": "I led the migration from Postgres 13 to 16…" },
    { "t": "2026-04-18T14:41:18Z", "kind": "mode",       "modeId": "…uuid…", "modeName": "Custom: Interview" }
  ],
  "summaries": [
    {
      "t": "2026-04-18T15:12:05Z",
      "prompt": "<auto-summary prompt used>",
      "text": "…generated recap…"
    }
  ]
}
```

Events are append-only during the session and written as a single JSON file
on Stop (no streaming-JSON pressure — events are infrequent). `summaries` is
a list so re-runs with different prompts append rather than overwrite.

### Settings

New keys in `SettingsStore`:

- `activeModeID: String` (AppStorage; stores UUID as string since
  AppStorage does not support UUID directly; defaults to the Watching
  built-in's id on first launch post-upgrade)
- `autoSummarizeOnStop: Bool` (AppStorage; default `true`)
- `summaryPrompt: String` (AppStorage; default provided — see below)

Modes are persisted as a JSON array in
`~/Library/Application Support/NotchyPrompter/modes.json` (single file, not
one-per-mode — modes are small and frequently listed together).

### Default seed data

Three built-ins (non-deletable, editable, resettable):

| Mode | Default system prompt |
|---|---|
| Watching | Today's prompt verbatim: "You are a silent meeting copilot. Give me 1-2 concise bullet points I should respond with or be aware of based on what the other person just said. Be extremely brief." |
| Meeting | "You are a silent meeting copilot. Draft a concise first-person response I can say out loud right now, grounded in any attached context notes. Use bullets only if the other person asked a multi-part question. Be extremely brief — one or two sentences at most." |
| Custom | "" (empty — user fills it in) |

Two seeded customs (user can edit or delete):

| Mode | Default system prompt |
|---|---|
| Interview | "You are a silent interview copilot. Draft a concise first-person answer to the interviewer's question, grounded in the attached résumé and job description. If the question is behavioural, lead with STAR structure. One or two sentences." |
| Presenting | "You are a silent presentation copilot. The audience just asked a question. Draft a concise first-person answer suitable for a live presentation, grounded in the attached deck notes. One or two sentences." |

Default `summaryPrompt`:

> "You are given a transcript and reply log from a meeting. Produce a
> concise recap: what was discussed, decisions made, action items (who owes
> what by when if stated), and open questions. Markdown."

## Component changes

### `LLMClient` protocol

Today:
```swift
protocol LLMClient: Sendable {
    func stream(chunk: String, history: [ChatTurn]) -> AsyncThrowingStream<String, Error>
}
```

After:
```swift
struct LLMRequest {
    let chunk: String
    let history: [ChatTurn]
    let systemPrompt: String          // from active Mode
    let attachedContexts: [ContextPack]
    let modelOverride: String?
    let maxTokensOverride: Int?
}

protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}
```

The global `systemPrompt` constant and `userMessage(for:)` helper stay; the
constant becomes the Watching built-in's default text used for seeding.

### `ClaudeClient`

Today the `system:` field is a single cached block. After:

```jsonc
"system": [
  { "type": "text", "text": "<mode.systemPrompt>",   "cache_control": { "type": "ephemeral" } },
  { "type": "text", "text": "<context1.body>",       "cache_control": { "type": "ephemeral" } },
  { "type": "text", "text": "<context2.body>",       "cache_control": { "type": "ephemeral" } }
]
```

Each block is cached separately so attaching a different context pack on a
later request still hits the system-prompt cache. Mode change = systemPrompt
block changes = first block busts, but context-pack blocks survive if
re-used.

Claude's prompt-caching API supports up to 4 `cache_control` breakpoints
total across the whole request — that caps us at 1 system-prompt block
plus 3 context-pack blocks. If the user attaches more than 3 contexts,
contexts 1 and 2 each get their own cached block and contexts 3..N are
concatenated (with `\n\n---\n\n` separators) into the final cached block.
The Modes-tab UI notes this as "up to 3 contexts cached individually;
additional contexts still work but share a cache block."

### `OllamaClient`

Ollama has no prompt cache, so the mode's system prompt + concatenated
context bodies become the `system` field verbatim. Mode switch = next
request uses the new system field; no cache-busting concerns.

### `Pipeline`

Two changes:

1. On each chunk, read `settings.activeMode` and the attached contexts at
   call time (*not* at Start) so mid-session mode switches take effect on
   the very next LLM call.
2. A new `SessionRecorder` collaborator receives events (`transcript`,
   `reply`, `mode`) and persists them on `stop()`. On Stop, if
   `autoSummarizeOnStop` is true, fire one non-streaming LLM call against
   the recorded events using `summaryPrompt`, append to `summaries`, and
   re-write the file.

Mode change on a running pipeline emits a `mode` event and nothing else —
history is preserved across mode changes (the user might want continuity
between "prep video" and "actual call").

### `SessionRecorder` (new)

```swift
@MainActor
final class SessionRecorder {
    private var currentSession: Session?
    private let sessionsDir: URL

    func startSession(initialMode: Mode) { … }
    func recordTranscript(_ text: String, durationMs: Int) { … }
    func recordReply(_ text: String) { … }
    func recordModeChange(_ mode: Mode) { … }
    func endSession() async throws -> Session { … }    // writes file, returns session
    func appendSummary(sessionID: String, prompt: String, text: String) async throws { … }
    func listSessions() -> [SessionMeta] { … }         // for "Summarize Last Session…"
}

struct SessionMeta: Identifiable, Equatable {
    let id: String            // matches Session.id; also the filename stem
    let startedAt: Date
    let endedAt: Date?
    let fileURL: URL
    let lastModeName: String?
}
```

### `MenuBarController`

`rebuildMenu(running:)` signature stays; its body grows to read the active
mode and the list of modes (injected via a small protocol or closure). When
the user picks a mode the controller calls into `SettingsStore` +
`Pipeline.recordModeChange(...)` if running.

### `SettingsWindow` / `SettingsView`

Today's single Form is wrapped in a `TabView` with the four tabs above.
Backend tab's body is unchanged. Modes and Contexts tabs are new views
(`ModesSettingsView`, `ContextsSettingsView`) backed by two new stores
(`ModeStore`, `ContextStore`) that load/save JSON files on disk.

## Data flow — end to end

```
User speaks
    │
    ▼
AudioCapture ─▶ VAD ─▶ Transcriber ─▶ trimmed text
                                          │
                                          ▼
                             Pipeline.handleLLM(chunk)
                                          │
            reads ActiveMode + attached ContextPacks from stores
                                          │
                                          ▼
                         LLMRequest ─▶ LLMClient.stream(...)
                                          │  streams deltas
                                          ▼
                                   OverlayViewModel (pill)
                                          │
                                 on stream complete ─▶ SessionRecorder.recordReply
                                          │
                                          ▼
                                    Pipeline.stop()
                                          │
                      SessionRecorder.endSession() ─▶ writes JSON
                                          │
                 if autoSummarizeOnStop ─▶ LLMClient one-shot against session
                                          │
                                          ▼
                       SessionRecorder.appendSummary() ─▶ rewrites JSON
```

## Migration

- On first launch post-v0.2, if `modes.json` does not exist, seed the
  three built-ins + two example customs and set `activeModeID` to
  Watching's id.
- Existing v0.1 behaviour is preserved: Watching's default prompt is byte-
  for-byte identical to today's `systemPrompt` constant.
- No sessions from before v0.2 are back-filled; the sessions folder just
  starts accumulating on first post-upgrade Stop.

## Testing strategy

- **Unit**: `SessionRecorder` event ordering + JSON round-trip;
  `ModeStore` / `ContextStore` load/save + frontmatter parsing;
  `LLMRequest` construction from (mode, contexts, settings).
- **Integration**: `ClaudeClient` system-block assembly — confirm 1 system
  prompt block + N context blocks + correct cache_control placement. Use
  URLProtocol mock.
- **Manual**: start a session in Meeting mode, switch to Custom mid-
  session, stop, verify session JSON has a `mode` event between the
  transcripts and that a summary is appended.

## Open questions (deferred to implementation)

- Should `modelOverride` also override the *backend* (allow a mode to say
  "always use Ollama even when the global backend is Claude")? v0.2:
  **no** — mode only overrides model name within the active backend.
  Cross-backend override is a niche case; easy to add later.
- Should summaries stream into a window on Stop, or just silently save?
  v0.2: **silently save**, surface via "Summarize Last Session…" which
  opens a small read-only window showing the latest summary with a "Copy"
  button. Avoids surprise modal UX on Stop.

## Rollback

All new features are behind new data files; v0.2 can be downgraded to v0.1
by deleting `modes.json` and the sessions/contexts folders — UserDefaults
keys not read by v0.1 are inert. The Claude prompt-cache change is
backwards-compatible; v0.1's single-block system is a subset of the new
multi-block format.
