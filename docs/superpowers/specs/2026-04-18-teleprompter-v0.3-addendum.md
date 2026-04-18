# Teleprompter v0.3 — Spec Addendum

**Date:** 2026-04-18
**Supersedes sections of:** `2026-04-18-modes-and-sessions-design.md` (Teleprompter / Meeting mode)
**Status:** backlog

## Context

v0.2 shipped three built-in modes: Note-taker, Teleprompter, Custom.

The Note-taker mode works well — the output is fact-oriented bullets and
the acknowledgment-language failure mode doesn't apply. During
acceptance testing on 2026-04-18, the Teleprompter prompt (v0.2) reliably
produced meta-narration like "Got it. We'll set up comments…" or "Understood. We'll enable direct integration…" instead of
words the user would actually say aloud to the other person.

Two root causes:

1. **Firing cadence is too aggressive.** The VAD emits a chunk on 800ms
   speech + 400ms silence. Every chunk fires a full LLM reply, including
   2-3 word fragments ("send it to Canva or"). A real conversation has
   many short fragments where the user would NOT respond — only at
   question-ends or thought-completions would the user speak.

2. **Prompt ambiguity.** "First-person response I can say out loud" reads
   as "first-person reply from Claude-the-assistant" under Claude's
   training distribution. Claude defaults to role-playing as a project-
   manager assistant acknowledging instructions from the user, not as
   the user speaking to the other side.

## Goals for v0.3

- Only fire the LLM when the other person has likely stopped speaking in
  a way that warrants a response (a question, an end-of-thought pause).
- When it does fire, produce output that reads like dialogue the user
  would speak aloud — no acknowledgments, no meta-narration.

## Non-goals (v0.3)

- Perfect turn-detection. Some false fires are acceptable; the UX cost of
  over-firing is noise, not failure.
- Multi-speaker diarisation.
- Barge-in detection (is the user speaking too?).

## Design options

### Firing cadence (pick one or combine)

1. **Silence-based debounce.** Only fire when there's been ≥ 2 seconds
   of silence since the last VAD chunk. Accumulate chunks in the
   meantime; send the concatenated transcript when the pause arrives.
   Simple; no new deps.
2. **Question detection.** Fire if the latest transcript ends with "?"
   or starts with a wh-word (who/what/when/where/why/how) and has at
   least a subject. Accumulate otherwise.
3. **LLM gate (fast-path classifier).** Run a cheap classifier
   (Haiku) on each chunk: "is this a moment where the user needs to
   respond? yes/no". If yes, fire the real Teleprompter call. If no,
   skip. Adds latency but highest precision.

**Recommended combination**: #1 + #2. Fire if question marker detected
_or_ ≥ 2s silence since last chunk. Skip #3 for v0.3 (extra latency,
extra API cost; defer until we see #1 + #2 fail).

### Prompt rewrite

v0.2's Teleprompter prompt:

> "You are a silent teleprompter for the user. The OTHER person just spoke. Output the exact words the USER should say next, in the user's own voice, to continue the conversation. Strict rules: (1) speak directly to the other person; do not describe actions or acknowledge instructions; (2) no preambles — never start with 'Got it', 'Understood', 'Absolutely', or 'Sure'; (3) first person (I, we); (4) one or two sentences at most. If the other person asked a question, answer it in the user's voice."

Still produces "Got it. We'll…" in practice. Candidate v0.3 prompt:

> "The other person said: `<chunk>`. Reply with EXACTLY what the user should say back to them — nothing else. Do not acknowledge them first. Do not summarise what they said. Do not describe what the user will do. Do not start with 'Got it', 'Understood', 'Absolutely', 'Sure', 'Okay', 'Yeah', 'Right'. Start directly with the words the user speaks. If the user's best response is silence or a single word, return a single word. If the other person asked a question, answer it in the user's voice, grounded in attached context. Be extremely brief — one sentence unless the question genuinely requires two."

Changes:
- Phrased as direct imperative, not role description
- Explicit "do not" list expanded with more filler words
- Calls out "silence or single word" as legitimate outputs
- Removes "first-person" wording that Claude mis-interprets

### Overlay treatment

Currently all LLM output is rendered identically. For Teleprompter, the
treatment should be visually distinct to reinforce "speak this":

- Prefix bubble content with a small quote glyph (e.g. "”").
- Optional: different background colour (slight blue tint) so the user
  knows this is a line they should speak aloud, not a summary.
- Don't change for Note-taker — bullets are fine as-is.

## Acceptance criteria

- On a test recording of a job-interview Q&A, at least 80% of
  Teleprompter outputs are lines the user could verbatim say to the
  interviewer.
- "Got it. We'll…" / "Understood." / "Absolutely." preambles appear in
  ≤ 10% of outputs (down from near 100% in v0.2).
- Over a 10-minute conversation, the LLM fires ≤ 1× per 15 seconds on
  average (down from ~1× per 2 seconds with v0.2's per-chunk firing).

## Tasks (rough order)

1. Add `fireCadence` field to Mode (`onEveryChunk` vs `onQuestionOrPause`).
   Default Note-taker to `onEveryChunk`, Teleprompter to
   `onQuestionOrPause`. Custom user-configurable.
2. Implement a `ChunkAccumulator` in Pipeline that buffers transcripts
   and fires per the mode's cadence. Detect question markers (regex) and
   silence gaps (Date delta since last transcript).
3. Ship the v0.3 Teleprompter prompt.
4. Add the quote-glyph overlay treatment for Teleprompter mode.
5. Unit tests for `ChunkAccumulator` firing rules.

## Related

- Open issue from v0.2 acceptance log (2026-04-18 06:59 session): per-
  chunk firing produced 18 LLM calls in 80 seconds of real dialogue.
