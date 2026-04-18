# NotchyPrompter v0.2 — Open Issues After Acceptance Testing

**Date:** 2026-04-18
**Context:** These issues surfaced during live acceptance of the v0.2
branch (`v0.2-modes-and-sessions`). The code landed and builds green;
the problems below are correctness, quality, or developer-experience
issues that need research and follow-up work before a clean v0.3.

Each section is self-contained so a research agent can investigate
it without needing the full conversation history. Assumes the reader
has access to the repo at `/Users/mhlaghari/teleprompter` and the
worktree at `/Users/mhlaghari/.config/superpowers/worktrees/teleprompter/v0.2-modes-and-sessions`.

---

## Issue 1 — Stable code-signing identity (RESOLVED in v0.2.0)

**Status:** Fixed — shipped as `scripts/setup-dev-signing.sh` in v0.2.0.
TCC now keys off the `NotchyPrompter Dev` leaf-cert SHA in the Designated
Requirement, verified surviving a rebuild cycle in acceptance testing
after a one-time `tccutil reset`. Known caveat: first rebuild after
switching away from the old ad-hoc identity needs `tccutil reset
ScreenCapture com.mhlaghari.notchyprompter` once to clear the stale
grant; the setup script should probably do this automatically in a
future revision.

**Original symptom (for history).** Every `./build.sh` invalidated the
Screen Recording (TCC) grant. User had to `tccutil reset ScreenCapture
com.mhlaghari.notchyprompter`, re-grant in System Settings, sometimes
restart the app twice, for each rebuild. This happened ~5 times during
a single acceptance-testing session.

**Root cause.** `build.sh` runs `codesign --sign -` (ad-hoc). Ad-hoc
signatures hash over the binary; every rebuild → different signature
→ TCC treats as new app identity.

**What CLAUDE.md already documents.** "(a) create a self-signed
persistent certificate in Keychain and sign with `codesign --sign
'NotchyPrompter Dev'`" is listed as an option in the README roadmap.

**Research questions.**
1. What's the minimum non-interactive script that generates a code-
   signing key + self-signed certificate with the right Code Signing
   Extended Key Usage, imports into the login keychain, and trusts it
   for local code signing?
2. Can `security` alone do it, or is `openssl` required for the cert
   generation step?
3. Does `codesign --sign "NotchyPrompter Dev"` stabilize TCC across
   rebuilds — i.e., does TCC key off the leaf-cert fingerprint rather
   than the signature bytes? (Expected: yes.)
4. What's the one-time user interaction (e.g., "trust this certificate
   for code signing" in Keychain Access) — can that be scripted via
   `security set-key-partition-list` + `security
   add-trusted-cert`, or does it need GUI interaction?

**Target output.** A `scripts/setup-dev-signing.sh` that runs once,
produces the identity, and makes `./build.sh` sign with it. File a PR
against `v0.2-modes-and-sessions` (or a branch off it).

**Acceptance.** After running the setup script once, `./build.sh &&
open NotchyPrompter.app` repeatedly across 3+ rebuilds does NOT
re-prompt for Screen Recording.

---

## Issue 2 — Note-taker prompt: attribution hallucinations

**Symptom.** The Note-taker prompt runs through Qwen 2B (user's local
Ollama). Even with the tightened prompt (`docs/superpowers/plans/2026-04-18-modes-and-sessions.md` Phase 7
+ the SeedData.swift prompt rev at commit-TBD), Qwen frames the
speaker as a third party and sometimes invents multi-person attribution:

Example from session `2026-04-18-075803.log`:

```
them: up essentially stateless. It doesn't really know anything.
      So how do you make a stateless agent act disciplined
me:   - One person claimed stateless agents act like "stateless"
        but admit they don't know anything.
      - The speaker questions how a stateless agent can act "disciplined."
```

The source is ONE speaker in a tutorial video. Qwen is writing it as
"One person claimed…", "Another person described…". These are not
hallucinations of facts, but hallucinations of *attribution*.

**Research questions.**
1. Is this a Qwen 2B artifact (quantized small model's narrative
   default) or does it happen with larger models (Qwen 8B, Llama 3.2
   3B, Haiku) too?
2. Does reframing the prompt fix it? Candidate reframings:
   - Remove any narrative scaffolding ("the speaker") from the prompt.
   - Frame the input as "transcript of a single monologue" explicitly.
   - Use example-shot prompting with 1-2 examples of correct style.
3. Is this something better fixed at a post-processing step (strip
   "the speaker" / "one person" prefixes) than prompt-engineered away?

**Target output.** An updated `SeedData.noteTakerPrompt` (in
`NotchyPrompter/Sources/SeedData.swift`) that eliminates attribution
hallucinations in ≥80% of sampled outputs on Qwen 2B, verified by
running the existing YouTube-video test flow and grepping the log for
"speaker" / "person".

---

## Issue 3 — Note-taker still fires on trivial chunks

**Symptom.** The new prompt says "If the paragraph is filler … output
nothing at all." Qwen 2B ignores this. Example:

```
them: Thank you.
me:   - Speaker thanked the listener at the end of the discussion.
```

**Research questions.**
1. Can Qwen 2B reliably output nothing? (Empirically, small instruct
   models resist empty outputs — they'll always say *something*.)
2. Should the filter be implemented **in Swift**, not in the prompt?
   E.g., a heuristic that skips LLM calls when the buffered paragraph
   has fewer than N tokens or is a known low-signal string ("thank
   you", "okay", "got it"). This is related to the Teleprompter v0.3
   smart-firing work — possibly share the classifier.
3. Should the UI treat the overlay differently for very short replies —
   e.g., not show bubble if only 1 bullet under 8 words?

**Target output.** A `TranscriptFilter` (new file) that sits between
`dispatchChunk` and `accumulator.append` in `Pipeline.swift`, rejecting
low-signal chunks. Plus unit tests with representative inputs.

---

## Issue 4 — Teleprompter mode still role-plays as assistant

**Symptom.** Still produces "Got it. We'll…", "Perfect! Let's…",
"That is exactly what…" even after the v0.2 prompt hardening. Pure
prompt iteration has plateaued.

**Status.** Tracked in full detail in
`docs/superpowers/specs/2026-04-18-teleprompter-v0.3-addendum.md`.
Primary fix is a combination of: silence-based fire debounce + question
detection + prompt v3 + visual overlay treatment.

**Research questions.**
1. Does example-shot prompting (few-shot with transcript → response
   pairs) materially help, or does a 2B model still refuse to adopt
   the user's voice?
2. Is an LLM classifier ("is this a question the user must answer?
   yes/no") a better gate than regex question-mark detection?
3. Should Teleprompter mode pin to a specific larger model by default
   (Haiku? Qwen 8B?) rather than respecting the user's global model
   setting?

**Target output.** Implementation of the v0.3 addendum's tasks 1-4.

---

## Issue 5 — Mode-change event not written to session `.log`

**Symptom.** When the user switches mode mid-session (menu bar → Mode
→ Note-taker while Teleprompter is running), the `[mode: X]` line is
NOT appended to the session's `.log` file. It IS appended to the
session's JSON event list (verified by reading the `.json` after
stop). The discrepancy is only in the `.log`.

**Suspicion.** `Pipeline.recordModeChangeIfRunning(_:)` calls
`sessionRecorder.recordModeChange(mode)`, which should append to log.
But the guard `vm.isRunning` may not be set by the time the mode
selection closure runs if the selection arrives between `start()`
returning and `setStatus("listening")` being called. Alternatively,
the menu-bar's `onSelectMode` callback may run on a different queue
than `@MainActor` expects.

**Research questions.**
1. Add a `DebugLog.write("recordModeChange called, isRunning=\(vm.isRunning)")`
   at the top of `Pipeline.recordModeChangeIfRunning` and verify by
   switching mode mid-session whether the guard fails or the log append
   fails.
2. If the log append fails, is it a FileHandle race (another writer
   has the file open)?

**Target output.** Fix such that mode-switching mid-session always
produces a `[mode: X]` line in the `.log` within 500ms.

---

## Issue 6 — Default Ollama model mismatch

**Symptom.** `SettingsStore.ollamaModel` defaults to `llama3.2:3b`.
User has `qwen3.5:2b` installed, not llama. If a user installs
NotchyPrompter and hasn't pulled the default model, the first Start
will silently fail (404 from Ollama) with no clear UI hint.

**Research questions.**
1. Should Settings pre-populate from Ollama's `/api/tags` endpoint on
   Backend tab load? (List available local models.)
2. Should the "Start" button's pre-flight check include a
   `/api/show` or `/api/tags` probe for the configured model, showing
   a useful error before we try to stream?

**Target output.** A `OllamaModelsProbe` that lists installed models,
and a Settings UI affordance that uses it to pre-populate the model
picker.

---

## Issue 7 — Dictation / self-audio cross-talk

**Symptom.** User reported that while dictating to a DIFFERENT app via
macOS speech-to-text, NotchyPrompter was picking up the dictated audio
and producing Note-taker bullets about the user's own speech. System
audio capture via ScreenCaptureKit normally wouldn't pick up microphone
— it captures system audio output (speakers). Two hypotheses:

1. The macOS dictation feature plays back audio through the speakers
   (e.g., loopback monitoring or an accessibility feature).
2. `excludesCurrentProcessAudio = false` is set (intentional per
   CLAUDE.md for debugging). If some other app is routing its mic
   input to system audio output, NotchyPrompter hears it.

**Research questions.**
1. Under what conditions does ScreenCaptureKit's audio tap pick up
   mic input? Does macOS's built-in Dictation use a loopback that
   becomes visible to `SCStream.capturesAudio = true`?
2. Should `excludesCurrentProcessAudio = true` be re-enabled? (It's
   on CLAUDE.md's known gotcha list as "Temporarily relaxed for
   debugging".)

**Target output.** Empirical test results. If the issue is reproducible
and not fixable via `excludesCurrentProcessAudio`, document in README
known limitations.

---

## Issue 8 — VAD chunker aggressiveness

**Symptom.** VAD config: 800ms speech + 400ms trailing silence (or 15s
hard cap). For rapid speakers with brief pauses, chunks come in at
2-5s intervals — the 2s debounce timer fires between them, producing
per-sentence output even within Note-taker mode. Example (same
session):

```
07:58:21 them: up essentially stateless. It doesn't know anything.
                So how do you make a stateless agent act disciplined
07:58:26 me:   (bullets)
07:58:27 them: and remember rules and learn over time...
                [only 1s after previous chunk]
07:58:29 me:   (bullets)
```

**Research questions.**
1. Should the VAD trailing-silence threshold increase to 1s or 1.5s?
   (Current is 400ms.)
2. Is there a better VAD than energy-based RMS (e.g., Silero VAD,
   WebRTC VAD)? WhisperKit bundles an `EnergyVAD.swift` we're not
   using.
3. Should the accumulator's debounce interact with VAD's trailing
   silence? E.g., emit `[end-of-phrase]` markers and debounce based
   on those rather than wall-clock time.

**Target output.** A tuning guide: what VAD settings (in `VAD.swift`)
produce the most natural paragraph boundaries. Possibly a Settings
slider for "sensitivity".

---

## Appendix: validated-as-working in this session

- Debouncer (`ChunkAccumulator`) after switching to
  `DispatchQueue.asyncAfter` — confirmed via `/tmp/notchy-debug.log`
  traces. Every paragraph fires once after the configured pause.
- Live Transcript window (menu bar → Show Live Transcript, ⌘T) —
  polls session `.log` every 500ms, auto-scrolls.
- Modes.json migration from v0.2.0 (Watching → Note-taker, Meeting →
  Teleprompter, UUIDs preserved).
- Multi-block Claude prompt caching (per Anthropic's 4-breakpoint cap).
- On-disk session artifacts: `<id>.json` (canonical event log,
  written on Stop) + `<id>.log` (live plaintext, appended per event).
- Auto-summary on Stop (when `autoSummarizeOnStop` is true).
