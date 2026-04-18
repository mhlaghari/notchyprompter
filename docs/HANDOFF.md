# NotchyPrompter — Handoff

**Last updated:** 2026-04-18
**Branch:** `main` (ahead of `v0.2.0` tag by 7 commits)
**Working tree:** clean

Living snapshot of where the project is. Rewrite on each substantive session. Deep-dive artifacts live elsewhere:

- Per-task plan + checklist: [`tasks/todo.md`](../tasks/todo.md)
- Persistent corrections / rules: [`tasks/lessons.md`](../tasks/lessons.md)
- Project conventions: [`CLAUDE.md`](../CLAUDE.md) (root) and [`~/.claude/CLAUDE.md`](../../.claude/CLAUDE.md) (global)
- Design / spec history: [`docs/superpowers/`](./superpowers/)

## Where we are

v0.2.0 shipped on 2026-04-18. Since then, `main` has accumulated quality improvements and a UX pivot that's materially better than v0.2.0 baseline:

- **Signing is stable.** `scripts/setup-dev-signing.sh` creates a self-signed `NotchyPrompter Dev` identity so TCC (Screen Recording) grants survive rebuilds. See lesson on TCC / DR in `lessons.md`.
- **Note-taker is now transcript-primary.** The LLM no longer fires per chunk. While a session runs, the notch shows the raw Whisper transcript; on Stop, `autoSummarizeOnStop` runs once over the full transcript. Validated live in `sessions/2026-04-18-113741.log` — a 10-minute talk about Goose / Qwen 3 Coder produced one coherent 6-section recap instead of 17 per-fragment bullets.
- **Trivia filter + attribution stripper are in place.** `TranscriptFilter` drops `*Bip*` / `[Music]` / `thank you`-style chunks before the LLM. `AttributionStripper` removes leading "The speaker said…" / "User claims…" from any bullets that do slip through. Both have broad unit coverage (39/39 tests green).
- **Session artifacts moved** from `~/Library/Application Support/NotchyPrompter/sessions/` to `~/teleprompter/sessions/` (gitignored). Modes + context packs remain in `~/Library/…` — they are configuration, not per-run artifacts.
- **`me:` → `notes:` / `draft:` / `ai:`** in session logs, reflecting what the LLM was actually doing in the active mode.

## Recent commits (newest first)

```
a629e76 Update todo.md after transcript-primary ship + post-session observations
93bc0f7 Note-taker goes transcript-primary; LLM fires once on Stop
46b51b6 Extend TranscriptFilter + AttributionStripper from live-session data
b847c5e Merge pull request #12 from mhlaghari/issue-3-trivial-chunk-filter
6ae5e77 Merge pull request #11 from mhlaghari/issue-2-attribution-hallucinations
ded4a75 Rename me: to mode-aware label and move sessions to ~/teleprompter
6212ffb Release v0.2.0
```

## Open pull requests (all draft)

| PR  | Branch                                     | Status                                                                                                          |
| --- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| #9  | `issue-4-teleprompter-v0.3-partial`        | Teleprompter prompt rewrite. Partial — cadence work deferred. Live A/B needed vs v0.2 output.                   |
| #10 | `issue-8-vad-tuning`                       | VAD trailing silence 400 → 900 ms. Partial — no settings sliders yet.                                           |
| #13 | `issue-6-ollama-model-picker`              | New `OllamaModelsProbe` + picker in Settings → Backend.                                                         |
| #14 | `issue-7-dictation-crosstalk-research`     | Research doc + README Known-limitations entry. No code change.                                                  |
| #15 | `issue-5-mode-change-log`                  | Diagnostic / instrumentation only. Real fix pending a live repro with `/tmp/notchy-debug.log`.                  |

Closed this session: **#11** (attribution fix), **#12** (trivia filter).

## Next up (from `tasks/todo.md`)

Low-hanging, captured from the `sessions/2026-04-18-113741` review:

1. **Append summary to the `.log`** as well as the `.json` so a plain `cat` shows the recap. One-line change in `SessionRecorder.appendSummary`.
2. **Surface the summary on the notch** after Stop — `vm.setResponse(summary)` with a longer auto-hide.
3. **Upgrade the default summarisation model.** Qwen 2B mangled proper nouns in the 113741 summary ("Zustand" → "Zocostate") and flattened two projects into one sentence. A larger model (Qwen 8B, Haiku) would handle this far better.

Larger:

4. Keyboard shortcuts (⌘⇧L start/stop, ⌘⇧T transcript window) — works around menu-bar occlusion on notched Macs.
5. **"Save" mode** — transcript-only, no overlay, no auto-summary. Lightest of the four pillars the user described (Save / Video notes / Meeting notes / Interview assist).

## Gotchas the next session should know

These are also in `CLAUDE.md` and `lessons.md`, restated here so the handoff is self-contained:

- **Don't rebuild mid-session unless the user expects to re-grant permission.** The signing fix made TCC grants stable across rebuilds — but the first rebuild after switching signing identities still needs `tccutil reset ScreenCapture com.mhlaghari.notchyprompter` once.
- **`excludesCurrentProcessAudio = false` in `AudioCapture.swift:48` is intentional.** Don't "fix" it.
- **No `swift test` + report-results if no tests exist** is OUTDATED — there are now 39 tests. `swift test` from `NotchyPrompter/` is green on main.
- **Per-callback debug logs in `Pipeline.swift` and `AudioCapture.swift` are on the cleanup list** — don't add more. Error paths are fine.
- **Menu-bar occlusion on notched MacBooks:** the status item may be invisible if too many apps install one. No fix yet; keyboard shortcuts are the planned workaround.

## How to pick up

```bash
# One-time (if you don't already have the signing identity)
./NotchyPrompter/scripts/setup-dev-signing.sh

# Build + run
cd NotchyPrompter
swift test                      # 39/39 pass on main
./build.sh                      # produces NotchyPrompter.app, code-signed
open NotchyPrompter.app

# Watch outputs
ls -lat ~/teleprompter/sessions/  # .log (transcript) + .json (events + summaries)
tail -f /tmp/notchy-debug.log     # runtime traces (DispatchWorkItem debouncer, filter skips, etc.)
```

Mode is selected via menu bar → Mode submenu (if the status item is visible — see "Gotchas"). Default = Note-taker, which is now transcript-primary.

## Known limitations

- Summary currently lands in the `.json` `summaries` array only, not the `.log` or the overlay. Cat the JSON (`cat <id>.json | python3 -m json.tool`) to read it.
- Qwen 2B (local Ollama default) is the weakest link for summary quality. Switching to Claude Haiku or a bigger Qwen is a Settings → Backend toggle.
- Notch-occluded menu bar on notched Macs (see Gotchas).
- Distribution signing is not done — build is `NotchyPrompter Dev` self-signed, fine for local use, will trip Gatekeeper if moved.
