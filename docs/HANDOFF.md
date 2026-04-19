# NotchyPrompter — Handoff

**Last updated:** 2026-04-20
**Current version:** **0.3.0** (tagged) — see [CHANGELOG](../CHANGELOG.md)
**Working tree on `main`:** clean
**Tests:** 46/46 green (`cd NotchyPrompter && swift test`)

This is the single document the next Claude session should read first. It's the complete picture — paste whatever's not obvious from code into here so the next agent doesn't have to re-infer project state.

Supporting artefacts:

- [`CLAUDE.md`](../CLAUDE.md) — project-level rules (don't-touch list, architecture contracts, build commands)
- [`~/.claude/CLAUDE.md`](~/.claude/CLAUDE.md) — global universal rules (Karpathy / Cherny merged)
- [`tasks/todo.md`](../tasks/todo.md) — per-task plans (write here BEFORE implementing)
- [`tasks/lessons.md`](../tasks/lessons.md) — corrections / rules the user has issued; read at session start
- [`docs/superpowers/`](./superpowers/) — spec + research history
- [`CHANGELOG.md`](../CHANGELOG.md) — release-level roadmap

---

## 1. What the app does

Native macOS app. ScreenCaptureKit taps system audio → AVAudioConverter resamples to 16 kHz mono → VAD chunker → WhisperKit transcribes on-device → LLMClient (Claude or Ollama) produces notes/draft/ai replies → SwiftUI notch overlay. Everything is one Swift process; no Python, no BlackHole, no background daemons. One TCC grant (Screen & System Audio Recording) unlocks it all.

**Four modes (selectable from the menu bar):** Note-taker (default, transcript-primary), Teleprompter, Custom, plus seeded Interview / Presenting. Each mode bundles a system prompt, attached context packs, optional per-mode model/max-tokens overrides, and a `FireCadence` (`silent | debounce(n) | onQuestionOrPause`).

**Four-pillar product vision the user sketched:** Save / Video-notes / Meeting-notes / Interview-assist. Only Note-taker + Teleprompter exist today. Save is the lightest next pillar (transcript-only, no overlay).

---

## 2. Architecture contracts (DON'T break these)

- **Audio chain:** `SCStream` → `AVAudioConverter` (16 kHz mono Float) → `VADChunker` → `Transcriber` (WhisperKit) → `LLMClient` → `OverlayViewModel`.
- `Pipeline` is `@MainActor`. `AudioCapture` is `@unchecked Sendable`; SCStream callbacks run on `.global(qos: .userInitiated)` — cross actor boundaries explicitly.
- Swift 6 strict concurrency is ON.
- `LLMClient` protocol takes an `LLMRequest` value (chunk, history, system prompt, attached contexts, optional overrides). Two clients: `ClaudeClient` (SSE + `anthropic-beta: prompt-caching-2024-07-31`, up to 4 ephemeral cache breakpoints) and `OllamaClient` (NDJSON streaming, `think: false` so reasoning models stream content immediately).
- VAD (`VAD.swift`): grace-period endpointing, `endOfUtteranceGraceMs=1200`, `minSpeechMs=800`, `maxChunkMs=15000`, `rmsThreshold=0.01`.

---

## 3. Defaults (don't change silently)

- Claude model: `claude-haiku-4-5-20251001`
- Ollama URL: `http://localhost:11434`
- Whisper model: `openai_whisper-large-v3-v20240930_turbo`
- Claude prompt cache: ephemeral, ~5 min TTL
- Note-taker defaults to `FireCadence.silent` — LLM runs once on Stop via `autoSummarizeOnStop`, not per chunk
- Session artefacts: `~/teleprompter/sessions/` (gitignored). Modes + context packs: `~/Library/Application Support/NotchyPrompter/` (configuration, not per-run)
- Runtime debug tail: `/tmp/notchy-debug.log`

---

## 4. Gotchas — read before touching the relevant file

- **`excludesCurrentProcessAudio = false` in `AudioCapture.swift` is intentional.** CLAUDE.md flags this as debugging-relaxed. Don't "fix" unless explicitly asked.
- **TCC resets on signature change.** `./build.sh` signs with the `NotchyPrompter Dev` self-signed identity (stable), so rebuilds don't revoke Screen Recording grant. If the identity ever changes, run `tccutil reset ScreenCapture com.mhlaghari.notchyprompter` once.
- **Don't rebuild mid-session** unless the user expects to re-grant. Kill the app first: `pkill -f NotchyPrompter`.
- **Per-callback debug logs in `Pipeline.swift` and `AudioCapture.swift` are on the cleanup list** (see `README.md` → Roadmap → Cleanup). Don't add more. Error paths are fine.
- **Notch-occluded menu bar on MacBooks with a notch:** the status item may be invisible if too many apps install one. Keyboard shortcuts (⌘⇧L / ⌘⇧T) are the planned workaround — not yet implemented.
- **`swift test` + report-results is FINE now** — 46 tests exist, suite runs in < 1 s. (Earlier CLAUDE.md said "don't run tests" when zero existed; that's outdated.)
- **No `swift build` alone — always `./build.sh`.** TCC keys off the bundle, not the raw binary.

---

## 5. What changed since v0.2.0 (shipped today as v0.3.0)

Full entry in `CHANGELOG.md` → `[0.3.0]`. Summary:

- **Note-taker pivot** — transcript-primary during the session; summary on Stop. Dramatically better output on long monologues.
- **TranscriptFilter + AttributionStripper** — filter Whisper noise before the LLM; strip attribution artefacts from whatever slips through.
- **Grace-period VAD** (PR #16) — supersedes the 400→900 ms bandaid; 1.2 s grace window stops rapid-speaker paragraphs from splitting mid-sentence.
- **Speech-daemon SCK exclusion** (PR #17) — stops macOS dictation chirps and Siri TTS from bleeding into the transcript.
- **Test coverage jumped 39 → 46** (new `VADChunkerTests`).
- **Bumped `Info.plist` version** — was still `0.1.0` from bring-up; now tracks the `VERSION` file at 0.3.0, build number 3.

Live verification that this works:
- `sessions/2026-04-19-200942.log` (PR #17 smoke-test) — 85 s on a Claude-4.7-benchmarks video, no dictation chirps in transcript.
- `sessions/2026-04-19-201735.log` (PR #16 smoke-test) — 85 s on a Claude-Code tutorial, 12 s paragraph-length chunks instead of sentence-length fragments. One ambiguous short trailing chunk at Stop but otherwise clean.

---

## 6. Open PRs (still DRAFT, deferred — all code-complete, waiting on live verification)

| PR  | Branch                              | What it does                                                                             | Blocker to merge                                                                 |
| --- | ----------------------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| #9  | `issue-4-teleprompter-v0.3-partial` | Rewrites `SeedData.teleprompterPrompt` (drops role framing, expands no-start list)       | Live A/B — record Teleprompter on same audio pre/post; count "Got it." ≤10%      |
| #13 | `issue-6-ollama-model-picker`       | `OllamaModelsProbe` + picker in Settings → Backend + pre-flight "run `ollama pull`" hint | Settings → Backend with Ollama selected; verify picker lists installed models    |
| #15 | `issue-5-mode-change-log`           | Instruments `SessionRecorder.appendLog` error paths + regression test                    | Live repro mid-session mode switch; inspect `/tmp/notchy-debug.log`              |

Closed this session: **#10** (VAD bandaid, superseded by #16), **#14** (research-only, superseded by #17). Previously closed: #11 (attribution fix), #12 (trivia filter) — merged into main.

---

## 7. Explicitly deferred (don't implement without re-opening the decision)

- **Silero v5 ONNX/CoreML VAD** — research verdict (`docs/superpowers/research-2026-04-19-m13v-feedback.md`) says wall-clock emission was the real #8 bug; Silero is optional polish. Revisit only if live sessions show RMS false-negatives degrading transcripts. Pick: `paean-ai/silero-vad-swift` (MIT, SPM, CoreML, ~2 MB).
- **`AudioHardwareCreateProcessTap` migration** (macOS 14.4+) — Apple's preferred per-PID audio tap. Cleaner than SCK but a full rewrite of `AudioCapture.swift`. Out of scope for 0.3; on the long-term list when distribution signing happens.
- **Transformer / semantic end-of-utterance detection** — LiveKit-style turn-detection on ASR partials. Overkill for the notch prompter shape; grace-period is enough.
- **Re-enable `excludesCurrentProcessAudio = true`** — still on the cleanup list (see `README.md` → Roadmap → Cleanup). Was relaxed during debugging; test and flip back when you're sure no regression.

---

## 8. Next up — three tracks

**Track A — clear the backlog (1 session).** Merge the three deferred DRAFT PRs after their manual verification. Smallest effort, biggest reduction in mental overhead.

**Track B — UX polish (1-2 sessions).**
1. Append summary text to `.log` as well as `.json` (one-line change in `SessionRecorder.appendSummary`; currently you have to `cat <id>.json | python3 -m json.tool` to see the recap).
2. Surface the summary on the notch after Stop (`vm.setResponse(summary)` with a longer auto-hide, say 30-60 s).
3. Upgrade the default summarisation model — Qwen 2B mangles proper nouns ("Zustand" → "Zocostate"). Default to Claude Haiku or Qwen 8B.
4. Keyboard shortcuts (⌘⇧L start/stop, ⌘⇧T transcript window) via `NSEvent.addGlobalMonitorForEvents` — works around the notch-occluded menu bar.

**Track C — the four pillars (2-3 sessions each).**
1. **Save mode** — transcript-only, no live overlay, no auto-summary. Lightest new pillar; mostly config plumbing.
2. **Meeting notes** — structured output (attendees, decisions, action items); likely needs Claude Opus for quality.
3. **Interview assist** — Teleprompter + live question-answering with resume context pack attached.
4. **Video notes** — today's Note-taker renamed; consider adding chapter detection + per-chapter recap.

User's stated preference (unprompted): "now that we have a good notch transcriber working" — track B and track C are both legitimate; pick by use-case. Track A first regardless.

---

## 9. How to pick up (physical workflow)

```bash
# One-time setup, only if you're on a fresh machine
./NotchyPrompter/scripts/setup-dev-signing.sh

# Normal loop — RUN THESE FROM THE REPO ROOT (/Users/mhlaghari/teleprompter/)
git fetch --all
git checkout main && git pull
cd NotchyPrompter
swift test                    # 46/46 should pass on main
./build.sh                    # produces NotchyPrompter.app, code-signed with Dev identity
open NotchyPrompter.app

# Watch outputs during a session
ls -lat ~/teleprompter/sessions/     # .log (transcript) + .json (events + summaries)
tail -f /tmp/notchy-debug.log        # runtime traces

# If NSLog output needs to be inspected (sometimes invisible via `log show` on macOS 26):
#   prefer /tmp/notchy-debug.log, or attach a debugger.

# Clean kill
pkill -f NotchyPrompter
```

Menu bar → **Mode** submenu picks Note-taker / Teleprompter / Custom / seeded examples. Default = Note-taker (transcript-primary).

---

## 10. Lessons logged this cycle

Full versions in `tasks/lessons.md`. Highlights:

- **When a built-in's default behaviour changes, prefer a runtime override in a computed property over a persisted-state migration.** Zero migration, no `modes.json` rewrite. We used `Mode.effectiveFireCadence` gated on `defaults.name`.
- **Regex subject patterns for natural-language stripping need lookaheads** to guard possessives.
- **Reporting-verb whitelists for LLM-output scrubbing must include bare infinitives** to catch plural subjects ("Speakers mention" vs "The speaker mentions").
- **Don't fix pre-existing working code unless explicitly asked.** The CLAUDE.md global rule. This cycle we stayed surgical on `AudioCapture.swift` — didn't touch `excludesCurrentProcessAudio = false`, didn't tidy the pre-callback debug logs.
- **Research before shipping when an external commenter flags a gotcha.** `m13v` on #7 and #8 was ~95% right; the project's prior research doc was partly wrong. 500 words of verified research beats hours of confusion on the wrong fix.
- **Tests encode intent.** The grace-period refactor and PR #10's trailing-silence retune produce nearly the same behaviour at the default — but the regression test for a 1050 ms mid-paragraph breath makes the intent explicit and guards against future "bump the knob" regressions.

---

## 11. Known limitations (v0.3.0 reality)

- Summary lands in `.json` `summaries` array only, not the `.log` or the notch overlay. `cat <id>.json | python3 -m json.tool` to read.
- Qwen 2B (Ollama default) is the weakest link for summary quality — mangles proper nouns and collapses multiple topics.
- **Dictation cross-talk residual:** SCK daemon exclusion (PR #17) kills leakage from Apple's speech daemons, but user-side audio routing still leaks — Live Listen, conferencing apps with monitor-my-mic, aggregate devices (BlackHole / Loopback) routing mic → default output. Long-term fix is `AudioHardwareCreateProcessTap` migration.
- Notch-occluded menu bar on notched Macs — no fix yet; keyboard shortcuts are planned.
- `NSWindow.sharingType = .none` is best-effort; ScreenCaptureKit-based recorders (Zoom/Meet/Teams/QuickTime) can still see the notch overlay. No public API opts a window out of capture on Tahoe.
- Distribution signing not done — `NotchyPrompter Dev` self-signed; fine locally, trips Gatekeeper if moved.
- WhisperKit model download (~1.5 GB) happens on first run with minimal progress indication.

---

## 12. User's communication preferences (observed)

From feedback this cycle:

- **Prefers concrete step-by-step instructions over narrative overviews.** If asked "how to use?", give exact bash commands, not a summary of the goal. Got confused when I led with multiple merge options instead of a single recommended flow — ended up asking "which ones should I merge? do I merge without testing?"
- **State the current directory assumption explicitly in code snippets.** User tried `cd NotchyPrompter && ./build.sh` from within `NotchyPrompter/`; the `cd` was double and failed. Always specify where the command expects to run from.
- **Wants completeness when asked** ("did you update everything?" = audit all the places, report honestly, don't just answer yes).
- **Trusts the agent to pick a direction.** "If you feel it's right, then let's do that approach" — present the evidence, make the call, explain the trade-off; don't over-ask. But DO pause after significant chunks of work (we paused between PR #16 and PR #17 for a check-in; that landed well).
- **Short confirmations mean go.** "yea ok" = proceed with the proposed plan.

---

## 13. Recent commits (newest first, since v0.2.0)

```
4d236fe Merge PR #16 from mhlaghari/issue-8-vad-grace-period
74f1e49 Merge PR #17 from mhlaghari/issue-7-speech-daemon-exclusion
114fb67 Housekeeping: reflect PRs #16 / #17 in todo + handoff + README
70c769c AudioCapture: exclude macOS speech daemons from SCK mix
a3243e6 Plan follow-up to m13v's comments on #7 and #8
6987e35 VAD: grace-period endpointing (supersedes PR #10)
2b1dada Add docs/HANDOFF.md — living snapshot for session-to-session pickup
a629e76 Update todo.md after transcript-primary ship + post-session observations
93bc0f7 Note-taker goes transcript-primary; LLM fires once on Stop
46b51b6 Extend TranscriptFilter + AttributionStripper from live-session data
b847c5e Merge PR #12 from mhlaghari/issue-3-trivial-chunk-filter
6ae5e77 Merge PR #11 from mhlaghari/issue-2-attribution-hallucinations
ded4a75 Rename me: to mode-aware label and move sessions to ~/teleprompter
```
