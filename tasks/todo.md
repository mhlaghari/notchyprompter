# Tasks

Per-task plans. Claude writes here **before** implementing; user verifies before implementation starts. Distinct from `CHANGELOG.md` `## [Unreleased] → ### To do`, which is the release-level roadmap.

## Format

- Use `- [ ]` for pending, `- [x]` for done.
- Each plan gets a `## <task name>` heading.
- Add a `## Review` subsection under the task when finished: outcome, unexpected findings, anything that should go into `lessons.md`.
- Old completed plans can be deleted; git history preserves them.

## Current plan — 2026-04-18: Note-taker = transcript-primary + recap on Stop

Triggered by session `sessions/2026-04-18-112714.log`: Note-taker fired 7 LLM calls on 90 s of single-speaker monologue about Goose + Qwen 3 Coder, producing 17 redundant bullets. Qwen never sees the arc — only the current paragraph — so the "notes" are actually per-fragment paraphrases.

Reshape: Note-taker records the transcript live (nothing fires during the session), and the existing `autoSummarizeOnStop` hook produces one coherent recap over the full transcript on Stop.

- [x] Add `FireCadence.silent` case — means "record, don't fire LLM per chunk"
- [x] Default Note-taker's `effectiveFireCadence` to `.silent` (was `.debounce(2.0)`). Gated on `defaults.name` so user renames don't break it; stored value is overridden, so legacy `modes.json` with `.debounce(2.0)` pick up the new behaviour without a migration.
- [x] `Pipeline.dispatchChunk` `.silent` branch: routes transcript to `vm.setResponse`; transcript already persisted by `sessionRecorder.recordTranscript` upstream.
- [x] Retune `SeedData.summaryPrompt` default for video/talk recap.
- [x] Unit tests: Note-taker resolves to `.silent` even when stored cadence is `.debounce(2.0)` (2 new tests in `ModeStoreTests`).
- [x] `swift test` (39/39) + `swift build -c release` green.
- [ ] Rebuild `.app`, launch, run a 30–60 s session — live log shows transcript only during the run, `[summary]` block appended on Stop.

### Review

**Outcome:** Pivoted Note-taker to transcript-primary behaviour. One `.silent` case added to `FireCadence`, one branch added to `Pipeline.dispatchChunk`, updated seed + runtime fallback, reworked the summary prompt for generic recaps. 39/39 tests pass.

**Unexpected findings:**
- `ModeStore` already has a non-trivial migration path (legacy `Watching` → `Note-taker`). Rather than add another migration pass for the stored cadence, chose to override in `effectiveFireCadence` based on `defaults.name`. Zero migration, no modes.json rewrite.
- `OverlayViewModel.setResponse` has a 9s auto-hide. For transcript streaming that's fine (each chunk resets the timer); if a speaker pauses for > 9s the overlay fades until the next chunk. No action needed unless UX feedback says otherwise.

**Into lessons.md:**
- When a built-in's default behaviour changes, prefer a runtime override in a computed property over a persisted-state migration — simpler, reversible, and doesn't touch disk.

## Completed — 2026-04-18: Filter trivia + broaden attribution stripper

Triggered by a live session (`sessions/2026-04-18-105531.log`) where `*Wheat*`, `*Wheep*`, `Thank you.` all slipped through to the LLM, and where `AttributionStripper` failed to catch bullets starting with "Speaker advises…" / "User claims…" (regex required a leading "The").

- [x] Merge PR #12 (TranscriptFilter) — kills `< 3` token chunks and the low-signal phrase set (`thank you`, `okay`, `[music]`, etc.)
- [x] Extend `TranscriptFilter` with a regex for Whisper's non-speech markers: whole chunk matching `*word*` or `[word]` should be skipped regardless of token count
- [x] Extend `AttributionStripper` so leading article ("The") is optional — catches "Speaker advises…" / "User claims…" / "Speakers mention…". Also broadened verb list (bare infinitives + `advise/recommend/transition/introduce/outline/challenge/enroll/thank/indicate/use/acknowledge/conclude/highlight/remind/warn`), and added a `(?=\s|[,:])` lookahead so possessive forms ("The speaker's microphone") survive.
- [x] Unit tests for both extensions (11 TranscriptFilter + 6 AttributionStripper, all pass)
- [x] `swift test --filter "AttributionStripperTests|TranscriptFilterTests"` → 17/17 pass
- [ ] Rebuild `.app`, launch, run a fresh session — verify `*X*` markers no longer appear in `notes:` lines and "Speaker advises…" is stripped

## Review

**Outcome:** Both filters extended cleanly in one commit. All 17 relevant unit tests pass.

**Unexpected findings:**
- The original `AttributionStripper` regex matched "The speaker" as a prefix even when followed by an apostrophe — possessive forms were being stripped. Needed a `(?=\s|[,:\-—–])` lookahead to force whitespace-or-punctuation after the subject.
- The verb whitelist in PR #11 only covered past / 3sg forms (`mentions`, `mentioned` — no bare `mention`). Plural subjects ("Speakers mention") need the bare infinitive. Roughly doubled the list.
- Live-session data (sessions/2026-04-18-105531.log) revealed Qwen uses more varied verbs than anticipated — `advises`, `recommends`, `transitions`, `introduces`, etc. Whitelist now covers them all.

**Into lessons.md:**
- Regex subject patterns for natural-language stripping need lookaheads to guard possessives.
- Reporting-verb whitelists for LLM-output scrubbing must include bare infinitives to catch plural subjects.

## Next (planning only — not starting yet)

- [ ] **Transcript-primary overlay + silent-until-substantial summariser.** The core v0.3 pivot: notch shows raw Whisper text; LLM only fires on a 60–90 s window of accumulated transcript with a prompt that permits empty output. Replaces per-chunk Note-taker firing. Bigger scope — needs its own spec + branch.
- [ ] Keyboard shortcuts (⌘⇧L start/stop, ⌘⇧T transcript window) — works around menu-bar occlusion on notched Macs.
- [ ] "Save" mode — transcript-only, no LLM, no bullets. Lightest of the four pillars (Save / Video notes / Meeting notes / Interview assist).

## Project state — 2026-04-18

### Branches

- **`main`** — shipping branch. v0.2.0 tagged. Beyond v0.2.0: Issue 1 signing fix, mode-aware session labels, sessions moved to `~/teleprompter/sessions/`, attribution fix (PR #11), trivia filter (PR #12).
- **`v0.2-modes-and-sessions`** — deleted after merge.
- Other branches exist as the 5 surviving draft PRs (see below) — each lives on its own branch pushed to origin.

### Open pull requests (all draft unless noted)

| PR | Branch | Next step |
|---|---|---|
| #9 | `issue-4-teleprompter-v0.3-partial` | Review prompt rewrite. Live A/B Teleprompter output vs v0.2 on the same audio. Partial — full v0.3 cadence work deferred. |
| #10 | `issue-8-vad-tuning` | Verify paragraph coalescing on fast-speaker video. Partial — settings sliders + tuning doc deferred. |
| #11 | merged | (done — landed in main) |
| #12 | merged | (done — landed in main; extensions shipping now) |
| #13 | `issue-6-ollama-model-picker` | Open Settings → Backend with Ollama selected; confirm picker lists installed models + pre-flight error path. |
| #14 | `issue-7-dictation-crosstalk-research` | Research doc + README limitation — read, run the three diagnostic checks, merge. |
| #15 | `issue-5-mode-change-log` | Diagnostic-only. Reproduce mid-session mode switch, inspect `/tmp/notchy-debug.log`, then ship the real fix in a follow-up. |

### Open GitHub issues

- #2 — closed by merged PR #11.
- #3 — closed by merged PR #12 (today).
- #4, #5, #6, #7, #8 — open, tracked by draft PRs above.

### Claude-harness worktrees

`.claude/worktrees/agent-*` are scratch space from the earlier parallel-agent dispatch. Safe to delete once the corresponding draft PR is merged. They are not tracked by git.
