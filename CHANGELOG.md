# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] — 2026-04-20

### Changed
- **Note-taker is transcript-primary.** The LLM no longer fires per VAD
  chunk during the session. While a session runs, the notch shows the raw
  Whisper transcript (via a new `FireCadence.silent` mode); on Stop,
  `autoSummarizeOnStop` runs once over the full transcript for a
  coherent recap. Fixes the "same point re-emitted 17 times" pattern
  observed on long monologues (`sessions/2026-04-18-112714.log`).
- **VAD uses a grace-period endpointing model.** Replaces wall-clock
  `trailingSilenceMs` (400 ms) with `endOfUtteranceGraceMs` (default
  1200 ms). A ~1 s mid-paragraph breath no longer splits paragraphs for
  rapid speakers; sub-grace speech resumes concatenate the buffer.
  Credit: [`m13v` on #8](https://github.com/mhlaghari/notchyprompter/issues/8).
  Deferred alternatives (Silero v5, `AudioHardwareCreateProcessTap`,
  semantic EoU) documented in
  `docs/superpowers/research-2026-04-19-m13v-feedback.md`.

### Added
- **SCK speech-daemon exclusion.** `AudioCapture` now passes a set of
  macOS speech-process bundle IDs (`speechsynthesisd`, legacy
  `synthesisserver`, `SpeechRecognitionCore.speechrecognitiond`,
  `corespeechd`, `SiriTTSService`, `assistantd`) to
  `SCContentFilter(..., excludingApplications:, ...)` so dictation
  chirps and Siri TTS no longer bleed into the capture stream. Also
  flips `onScreenWindowsOnly: false` so the background daemons are
  discoverable. Credit: [`m13v` on #7](https://github.com/mhlaghari/notchyprompter/issues/7).
- **`TranscriptFilter`** — drops low-signal Whisper chunks before the
  LLM sees them: `[MUSIC]`, `*Music*`, `thank you`-style fillers,
  chunks under 3 tokens, pure non-speech markers (`*word*` / `[word]`
  regardless of length). 11 unit tests.
- **`AttributionStripper`** — removes LLM-side attribution artifacts
  ("The speaker said…", "User claims…", "Speakers mention…") from
  note bullets. Broadened verb whitelist to include bare infinitives
  and more reporting verbs (`advise`, `recommend`, `transition`,
  `introduce`, etc.). Lookahead guards possessives. 6 unit tests.
- **`VADChunkerTests`** — 7 deterministic-Float tests encoding the
  grace-period regression surface (39 → 46 tests total).
- **Session log/JSON labels** — `me:` → `notes:` / `draft:` / `ai:`
  depending on the active mode's cadence, so `.log` reads correctly
  without cross-referencing the mode config.

### Fixed
- Closed mode-change / session crossover issues caught in live sessions:
  `AttributionStripper` now survives possessive forms
  ("The speaker's microphone"); plural subjects ("Speakers mention")
  get stripped thanks to bare-infinitive coverage.
- `Info.plist` `CFBundleShortVersionString` had never been bumped past
  `0.1.0`; corrected to track the VERSION file.

### Deprecated / closed
- Superseded PRs closed: **#10** (VAD `trailingSilenceMs` 400 → 900 ms
  bandaid — replaced by grace-period #16); **#14** (research-only;
  its "no public SCK API filters by audio source" conclusion was
  wrong — replaced by the exclusion code in #17).

## [0.2.0] — 2026-04-18

### Added
- **Modes** — selectable from the menu bar. Three built-ins (Note-taker,
  Teleprompter, Custom) and two seeded custom examples (Interview,
  Presenting). Each mode bundles a system prompt, optional attached
  context packs, and optional per-mode model + max-tokens overrides.
  Switching mid-session takes effect on the next LLM call and is recorded
  in the session log.
- **Context packs** — plain-markdown files with YAML frontmatter stored
  under `~/Library/Application Support/NotchyPrompter/contexts/`. Attach
  per-mode in Settings → Contexts. Dropped-in `.md` files without
  frontmatter are auto-rewritten with a generated id.
- **Session capture** — every Start→Stop cycle is saved as JSON under
  `~/Library/Application Support/NotchyPrompter/sessions/` with an
  interleaved timeline of `mode`, `transcript`, and `reply` events, plus
  a live plaintext `.log` companion that grows during the session. Auto-
  summary on Stop (toggleable). Menu bar → **Summarize Last Session…**
  re-runs the summary with a different prompt in a read-only window.
- **Live Transcript window** (⌘T / menu bar → Show Live Transcript) —
  tails the current session `.log` at 500 ms intervals.
- **Paragraph debouncer** (`ChunkAccumulator`) — Note-taker fires once
  per natural pause instead of per VAD chunk, using `DispatchWorkItem`
  debounce against the trailing-silence cadence.
- **Tabbed Settings** — Backend / Modes / Contexts / About.
- **Multi-block Claude prompt caching** — system prompt plus up to 3
  attached context packs each get their own `cache_control: ephemeral`
  breakpoint (4-breakpoint cap); additional contexts are concatenated
  into the final cached block.
- **SwiftPM test target** — `swift test` runs 20 unit tests covering
  `ContextPack`, `ContextStore`, `ModeStore`, `SessionRecorder`, Claude
  multi-block assembly, and `Paths`.

### Changed
- Licensed under **AGPL-3.0-or-later** (was MIT during internal bring-up).
  Chosen so improvements stay in the commons; commercial dual-licensing
  available on request.
- `LLMClient` protocol now takes an `LLMRequest` value (chunk, history,
  system prompt, attached contexts, optional overrides). Callers build
  the request from the active mode per chunk.
- Built-in modes renamed: Watching → Note-taker, Meeting → Teleprompter
  (UUIDs preserved across migration).

### Fixed
- **Stable code-signing identity.** Replaced ad-hoc `codesign --sign -`
  with a self-signed `NotchyPrompter Dev` certificate via
  `scripts/setup-dev-signing.sh`. TCC now keys off the leaf-cert SHA in
  the Designated Requirement, so Screen Recording permission survives
  rebuilds instead of being revoked each time.

### To do
- Re-enable `excludesCurrentProcessAudio = true` after debugging loop.
- Strip the per-callback audio / VAD debug logs.
- Address open issues tracked in `docs/superpowers/open-issues-2026-04-18.md`
  (attribution hallucinations, trivial-chunk filter, Teleprompter voice,
  mode-change log sync, Ollama model picker, dictation cross-talk,
  VAD tuning).
- Slide-aware presenting mode (screen OCR or Keynote/PowerPoint tap).
- In-app session browser (v0.2 relies on Finder via "Open Sessions Folder").

## [0.1.0] — 2026-04-16

First working end-to-end build.

### Added
- **Native macOS `.app`** — no Python, no BlackHole, no background servers.
- **System-audio capture** via ScreenCaptureKit (`SCStream.capturesAudio = true`).
  One-time Screen & System Audio Recording permission; no virtual audio driver.
- **On-device transcription** via WhisperKit
  (default model: `openai_whisper-large-v3-v20240930_turbo`, downloaded on
  first run).
- **Energy-based VAD chunker** — flushes on ≥ 800 ms speech + ≥ 400 ms
  trailing silence (or 15 s hard cap).
- **Pluggable LLM backend** with two clients:
  - `ClaudeClient` — Anthropic Messages API over URLSession + SSE, with
    ephemeral prompt caching on the static system prompt.
  - `OllamaClient` — `/api/chat` streaming NDJSON, with `think: false` so
    reasoning models (qwen3.x, deepseek-r1) stream content immediately.
- **Settings window** — backend picker, API key (stored in Keychain),
  model fields, context-window + max-tokens steppers, Start / Stop.
- **Menu-bar status item** (`waveform.circle`) with Start / Stop,
  Settings, Quit.
- **Notch overlay** — borderless NSWindow at `safeAreaInsets.top`,
  `sharingType = .none`, `ignoresMouseEvents = true`, auto-hide after 9 s.
- **Auto-restart on TCC grant** — `autoStartOnLaunch` flag so the
  pipeline resumes if macOS kills the app after permission changes.
- SwiftPM-based build (`./build.sh`) that produces a self-contained,
  ad-hoc-signed `.app`.

[Unreleased]: https://github.com/mhlaghari/notchyprompter/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/mhlaghari/notchyprompter/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/mhlaghari/notchyprompter/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mhlaghari/notchyprompter/releases/tag/v0.1.0
