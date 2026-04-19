# NotchyPrompter — Silent Meeting Copilot

A native macOS app that listens to the other person on your call, transcribes
their voice in real time, and surfaces 1–2 concise bullets at the MacBook
notch so you always know what to say next. No virtual audio drivers, no
Python, no background servers — just a `.app`.

**Requirements:** macOS 14 Sonoma or later (tested on macOS 26 Tahoe, M5 Max).

**Version:** 0.3.0 — see [CHANGELOG](./CHANGELOG.md).

## How it works

```
Other person's audio  ──▶  ScreenCaptureKit (system audio tap)
                                     │
                                     ▼
                           AVAudioConverter → 16 kHz mono Float
                                     │
                                     ▼
                        Energy-based VAD (silence chunker)
                                     │
                                     ▼
                           WhisperKit (on-device transcription)
                                     │
                                     ▼
                  LLMClient: Claude API  or  local Ollama
                                     │
                                     ▼
                        SwiftUI overlay at the notch
```

Everything runs in a single Swift process. First launch asks once for Screen
Recording permission, which is what unlocks system-audio capture — no
BlackHole or MIDI setup required.

## Install

Two options:

### A. Build from source

```bash
git clone <this repo>
cd teleprompter/NotchyPrompter

# One-time: create a stable self-signed code-signing identity so macOS
# TCC keeps the Screen Recording grant across rebuilds. You'll be
# prompted for your login keychain password once.
scripts/setup-dev-signing.sh

./build.sh
open NotchyPrompter.app
```

The build script runs `swift build -c release` (pulls [WhisperKit][wk] via
SwiftPM), then assembles a self-contained `.app` bundle and signs it with
the `NotchyPrompter Dev` identity created by the setup script.

Why the setup step? Ad-hoc signing (the previous default) gave the
binary a different identity hash on every build, so macOS revoked the
Screen Recording permission after every rebuild. The self-signed
identity is stable across rebuilds, so you grant Screen Recording once
and it sticks.

[wk]: https://github.com/argmaxinc/WhisperKit

### B. Download the `.app` (once a release is cut)

*Coming soon.* Until then, build from source.

## First run

1. Double-click `NotchyPrompter.app`.
2. macOS will prompt for **Screen Recording & System Audio** the first
   time audio capture starts — allow it. (System Settings → Privacy &
   Security → Screen Recording.) The app has no Dock icon; look for the
   waveform icon in the menu bar.
3. The Settings window opens automatically if nothing is configured.
   Pick a backend:
   - **Claude** — paste your Anthropic API key (stored in Keychain).
     Default model: `claude-haiku-4-5-20251001`.
   - **Ollama** — make sure `ollama serve` is running locally and pull a
     model (e.g. `ollama pull llama3.2:3b`). Default URL: `http://localhost:11434`.
4. Click **Start**. First-time Whisper download is ~500 MB–1.5 GB and
   takes 30–90 s; subsequent launches are instant.

## Use

Play a YouTube interview, join a Meet/Zoom call, whatever — within 2–4 s
of the speaker pausing, bullets fade in at the notch.

Menu bar → **Start/Stop Listening**, **Settings…**, **Quit**.

## Project layout

```
teleprompter/
├── README.md
└── NotchyPrompter/
    ├── Package.swift              # SwiftPM manifest
    ├── Info.plist                 # LSUIElement, NSScreenCaptureUsageDescription
    ├── build.sh                   # swift build → NotchyPrompter.app
    └── Sources/
        ├── NotchyPrompterApp.swift  # @main
        ├── AppDelegate.swift      # wires everything
        ├── MenuBarController.swift
        ├── NotchWindow.swift      # borderless window at safeAreaInsets.top
        ├── OverlayView.swift      # SwiftUI pill + fade
        ├── OverlayViewModel.swift
        ├── SettingsStore.swift    # UserDefaults + Keychain (API key)
        ├── SettingsView.swift     # SwiftUI settings form
        ├── SettingsWindow.swift
        ├── AudioCapture.swift     # SCStream audio tap + AVAudioConverter
        ├── VAD.swift              # energy-based silence chunker
        ├── Transcriber.swift      # WhisperKit wrapper
        ├── LLMClient.swift        # protocol + system prompt
        ├── ClaudeClient.swift     # URLSession + SSE, prompt caching
        └── OllamaClient.swift     # URLSession + NDJSON streaming
```

## Known limitations

- **Screen-share invisibility is best-effort.** `NSWindow.sharingType = .none`
  blocks legacy `CGWindowList*` capture. `ScreenCaptureKit`-based tools
  (modern Zoom, Teams, Meet, QuickTime) still see the overlay. No public
  API yet lets an app opt out of being captured — file feedback with
  Apple if this matters.
- **Whisper cold start.** First run downloads the model from HuggingFace
  (cached at `~/Documents/huggingface/…`). Swap the model name in
  Settings for a smaller variant if you prefer a faster cold start.
- **Claude prompt cache TTL.** The static system prompt is cached
  (`anthropic-beta: prompt-caching-2024-07-31`), but ephemeral cache
  expires after ~5 min of inactivity.
- **Self-signed.** The build script signs with a local `NotchyPrompter
  Dev` identity created by `scripts/setup-dev-signing.sh`. Gatekeeper
  will complain if you move the `.app` elsewhere or hand it to someone
  else. For distribution, sign with a Developer ID cert and notarise via
  `xcrun notarytool`.

## Distribution notes (for contributors)

```bash
# Release build
./build.sh

# Sign with a Developer ID (replace with your identity)
codesign --force --deep --sign "Developer ID Application: Your Name" \
    --options runtime NotchyPrompter.app

# Zip and notarise
ditto -c -k --keepParent NotchyPrompter.app NotchyPrompter.zip
xcrun notarytool submit NotchyPrompter.zip \
    --apple-id you@example.com --team-id TEAMID --password "app-specific-pw" \
    --wait
xcrun stapler staple NotchyPrompter.app
```

## Roadmap / TODO

Loose ends from the v0.1.0 working build. Contributions welcome.

### Cleanup (before v0.1.1)
- [ ] Re-enable `SCStreamConfiguration.excludesCurrentProcessAudio = true`
      (temporarily `false` in `AudioCapture.swift` for debugging).
- [ ] Strip the per-callback `AudioCapture callbacks last 3s`,
      `audio: N blocks`, and `vad: emitting chunk` logs from `Pipeline.swift`
      and `AudioCapture.swift` — keep only error paths.
- [x] Replace ad-hoc signing with a stable identity so rebuilds don't
      invalidate Screen-Recording permission every time. Done in
      `scripts/setup-dev-signing.sh` — creates a self-signed
      `NotchyPrompter Dev` cert; `build.sh` signs with it. Developer ID
      signing for redistribution is still tracked under Engineering.

### Quality
- [ ] Tune VAD: currently RMS threshold 0.01, 800 ms speech / 400 ms silence.
      Add a "hear-yourself" level meter in Settings so users can pick a
      threshold that matches their audio setup.
- [ ] Suppress duplicate transcripts (WhisperKit sometimes re-emits tail
      text when overlapping chunks land close together).
- [x] ~~Detect `Hallucinated phrases` list from Whisper (`thank you for watching`,
      `[MUSIC]`, etc.) and filter them out before calling the LLM.~~
      Shipped as `TranscriptFilter` (PRs #11 + #12) with `AttributionStripper` for LLM-side leaks.
- [ ] Graceful handling when Ollama isn't running — surface a clear
      "start `ollama serve`" message in the overlay / Settings status line.

### UX
- [ ] Hotkey to toggle listening (e.g. ⌘⇧L) via `NSEvent.addGlobalMonitorForEvents`.
- [ ] Overlay show/hide animation polish; optionally pin mode so bullets
      stay visible until you dismiss them.
- [ ] Dark / light adaptation — currently fixed 78 % black pill, white text.
- [ ] Multi-display support: currently picks `NSScreen.main`. On external
      monitors that lack a notch, fall back to a corner position.
- [ ] Settings "Test Connection" button for both backends.

### Features
- [x] ~~**Custom prompts + context packs** — the headline v0.2 feature.~~
      Shipped in v0.2.0 as Modes (Note-taker / Teleprompter / Custom +
      seeded Interview / Presenting) and Context Packs. See CHANGELOG and
      `docs/superpowers/specs/2026-04-18-modes-and-sessions-design.md`.
- [ ] Per-conversation history export (copy transcript + replies to
      clipboard / save to `.md`).
- [ ] Support streaming LLM output character-by-character into the overlay
      (already works for Ollama; verify Claude SSE path under load).
- [ ] Language selection for WhisperKit (currently auto-detects; expose
      a picker for better accuracy on non-English audio).

### Engineering
- [ ] GitHub Actions CI: `swift build -c release` on `macos-14` and
      `macos-15` runners on every PR.
- [ ] Notarisation workflow — `xcrun notarytool` in CI gated by tags, so
      `v0.1.x` → published `.dmg` release.
- [ ] Unit tests for `VADChunker` (deterministic Float fixtures) and
      `OllamaClient` / `ClaudeClient` (URLProtocol-mocked responses).
- [ ] Document how to add a third LLM backend (e.g. LM Studio, MLX Swift).

### Known limitations (not roadmap — just reality)
- `NSWindow.sharingType = .none` is best-effort; ScreenCaptureKit-based
  screen recorders (Zoom, Meet, Teams, QuickTime on Sonoma+) still see
  the overlay. No public API opts a window out of capture on Tahoe.
- WhisperKit model download (~1.5 GB) happens on first run — show a
  clearer progress indicator in Settings.

## License

Copyright © 2026 Mohammad Hamza Laghari.

NotchyPrompter is released under the **GNU Affero General Public License v3.0
or later** (AGPL-3.0-or-later) — see [LICENSE](./LICENSE).

**What this means in practice:**
- You may use, study, modify, and distribute NotchyPrompter freely.
- If you distribute a modified version, or **run it as a hosted service**,
  you must release your modifications under AGPL-3.0 and make the source
  available to users.
- If you want to build proprietary software on top of NotchyPrompter, contact
  me about a commercial licence — I'm open to dual-licensing in exchange
  for a fair arrangement.

Contributions are welcome under the same licence. By submitting a pull
request you agree your contributions will be licensed under AGPL-3.0-or-later.

