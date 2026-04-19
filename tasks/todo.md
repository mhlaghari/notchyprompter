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

## Current plan — 2026-04-19: act on `m13v` feedback on #7 and #8

Triggered by external comments on issues #7 and #8 (see `docs/superpowers/research-2026-04-19-m13v-feedback.md` for full verdict + citations).

### DO

- [x] **Grace-period VAD refactor** (supersedes #10). Branch `issue-8-vad-grace-period`.
  - [x] Rename `trailingSilenceMs` → `endOfUtteranceGraceMs`, default 1200 ms. Kept `minSpeechMs=800` as cough-filter gate. Update docstring to reflect grace-period semantics.
  - [x] Emission already resets on new speech (silenceMs=0) — the refactor is primarily a rename + threshold bump + doc change. Concatenation behavior verified by unit tests.
  - [x] Keep existing `maxChunkMs` (15 s) hard cap.
  - [x] Unit tests (`VADChunkerTests.swift`, 7 tests): no-speech sanity; short-speech-below-minSpeech; long-silence emits; **1 s mid-paragraph pause does NOT emit** (regression test calibrated between PR #10's 900 ms and new 1200 ms); triple-burst concatenation; hard-cap.
  - [x] `swift test` green (39 → 46).
  - [x] `swift build -c release` green.
  - [ ] Close PR #10 with a link to the new branch; reference supersedes. (User action.)
- [ ] **Per-app audio exclusion for speech daemons** (closes #7). Extends branch `issue-7-dictation-crosstalk-research` OR new branch — decide when branching.
  - [ ] Add `excludedSpeechBundleIDs` constant to `AudioCapture.swift`.
  - [ ] Switch `SCShareableContent.excludingDesktopWindows(_, onScreenWindowsOnly:)` from `true` → `false` so background daemons appear.
  - [ ] Filter `content.applications` by the exclusion set; pass to `SCContentFilter(..., excludingApplications:, ...)`.
  - [ ] Log which bundle IDs were found + excluded on startup (once, then shut up).
  - [ ] Rewrite `docs/superpowers/research-2026-04-18-dictation-crosstalk.md` — correct the "no public API" conclusion, point at the new code.
  - [ ] Keep README Known-limitations entry; reduce to caveat about user-side routing (Live Listen / aggregate devices).
  - [ ] `swift build -c release` green.
  - [ ] Live test: enable macOS Dictation (⌘twice), trigger a recognition chirp, verify it does NOT appear in the transcript.
- [ ] **Close PR #10** once grace-period PR opens.
- [ ] **Update PR #14** (or retarget) with new research verdict + code.

### DON'T

- **Don't pull Silero v5 in.** `m13v`'s grace-period fix resolves the emission bug without changing the detector. Revisit only if RMS false-negatives show up in live sessions after the grace-period ships.
- **Don't migrate to `AudioHardwareCreateProcessTap`.** Much bigger rewrite; stick with SCK exclusion list for now. Note as future work.
- **Don't add semantic/transformer EoU.** Overkill; keep the ~30-line refactor.
- **Don't ship PR #10 as-is.** It's a 400→900 ms bandaid on the wrong axis.

### DEFER (unchanged from yesterday's plan)

- **PR #13 (Ollama picker)** — complete, just needs manual UI smoke-test before marking ready.
- **PR #9 (Teleprompter v0.3 prompt)** — complete, needs live A/B.
- **PR #15 (mode-change diagnostic)** — logging only, waits on live repro of #5.

## Next (planning only — not starting yet)

Captured from live session review `sessions/2026-04-18-113741.log` + `.json`:

- [ ] **Append summary text to the `.log` as well as the `.json`.** Currently `SessionRecorder.appendSummary` only rewrites the JSON. A plain `cat <id>.log` gives transcript but no recap. One-line addition to also append `[summary]\n<text>\n` to the live log.
- [ ] **Surface the summary on the notch on Stop** (not just on disk). Small UX change — `vm.setResponse(summary)` from the `autoSummarizeOnStop` hook path with an auto-hide long enough to actually read it (probably 30–60 s, configurable).
- [ ] **Upgrade the default summarisation model.** Qwen 2B mangled proper nouns in the 113741 summary (`Zustand` → `Zocostate`) and flattened two projects into one sentence. A larger model (Qwen 8B, Haiku) would handle this much better. User-tunable via Settings → Backend, but the *default* summary prompt / model should be chosen to match the pivot.
- [ ] Keyboard shortcuts (⌘⇧L start/stop, ⌘⇧T transcript window) — works around menu-bar occlusion on notched Macs.
- [ ] "Save" mode — transcript-only, no live overlay, no auto-summary. Lightest of the four pillars (Save / Video notes / Meeting notes / Interview assist).

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
