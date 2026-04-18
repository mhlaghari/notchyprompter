# Research — NotchyPrompter picking up macOS Dictation audio

**Date:** 2026-04-18
**Issue:** [#7](https://github.com/mhlaghari/notchyprompter/issues/7)
**Status:** inconclusive from code-read alone; empirical test required from user

## Problem restatement

While the user was dictating into a different app via macOS built-in Dictation, NotchyPrompter produced Note-taker bullets about the user's own speech. NotchyPrompter captures **system audio output** (speakers) via `ScreenCaptureKit` — it does not tap the microphone. So either the user's voice is somehow routing through system output, or something else in the audio graph is letting the mic signal leak into the captured stream.

## Findings

### 1. Does `SCStream.capturesAudio` ever include mic input?

`ScreenCaptureKit`'s audio tap captures **only the speaker-bound output mix** of the system. Mic input does not appear in that stream unless another layer is explicitly routing it back to output. The mix includes every process that sends audio to `AudioDeviceIOProc` — any app doing its own loopback, monitoring, or live playback of mic audio is visible to SCK.

Relevant knobs on `SCStreamConfiguration`:
- `capturesAudio: Bool` — master switch.
- `excludesCurrentProcessAudio: Bool` — set to `false` in `AudioCapture.swift:48` per `CLAUDE.md` (intentional, for debugging). Would only affect NotchyPrompter's own playback, not third-party processes.
- `channelCount`, `sampleRate` — don't affect which sources are mixed in.

There is **no public API** to filter captured audio by originating process or source type beyond the current-process exclusion. Rogue Amoeba's Loopback-style tools achieve per-source capture by installing a kernel audio driver (`IOAudio` HAL plugin) — not feasible without the user installing extra software and granting kernel-extension / system extension permission.

### 2. Does macOS Dictation loop its mic capture back to system output?

macOS 14+ Dictation runs on-device by default. The mic capture feeds the recognizer; **the recognized text is injected into the focused text field** and does not need to be re-played. No feedback loop in normal operation.

But: if the user has **"Live Listen"** (an accessibility feature) turned on, mic → output IS routed at the system level, and NotchyPrompter would see it. Live Listen is toggled from Control Center → Hearing → Live Listen, or Accessibility settings. It is typically off.

Another plausible cause: the user has an audio interface or app doing **input monitoring** — e.g., OBS "Monitor Audio" on an input source, Zoom/FaceTime/Teams with a mic feedback loop enabled, Audio Hijack chains, DAWs with monitoring on. In any of those cases SCK sees the mic signal because the monitoring app is writing it to output.

### 3. Would re-enabling `excludesCurrentProcessAudio = true` help?

**No.** That flag only excludes audio **originating from NotchyPrompter itself**. The dictated audio is coming from somewhere else (the mic → some monitoring route → speakers), so flipping this flag does not address the symptom. It should still be re-enabled eventually for the reason it was added for (stop NotchyPrompter's own UI sounds / LLM playback from entering the loop), but that's a separate cleanup item on the CHANGELOG To-do list, not a fix for this issue.

### 4. What do similar tools do?

- **Audio Hijack / Loopback (Rogue Amoeba):** ship a HAL audio driver that exposes arbitrary per-app audio as virtual devices; `AVAudioEngine` can then tap a specific process.
- **BlackHole:** virtual loopback cable. Not a filter — a sink.
- **ScreenCaptureKit tools (OBS Studio, Screenity, QuickTime):** accept the whole mix as-is.

No library-level solution exists as of macOS 14.x / 15.x Tahoe for per-app filtering via SCK alone.

## Recommendation

**Document as a known limitation and provide an empirical-repro script.** The most likely cause is user-side audio routing (Live Listen, mic monitoring in a conferencing app, Audio Hijack chain). NotchyPrompter has no public API to filter those out, and the `excludesCurrentProcessAudio` flip commonly suggested does not apply.

### Empirical test the user can run

```bash
# While NotchyPrompter is NOT running, confirm whether mic audio is on the
# speaker bus. If any of these show non-silence while you speak, that's
# the source of the crosstalk NotchyPrompter is picking up.
#
# 1. Open Audio MIDI Setup (/Applications/Utilities/Audio MIDI Setup.app).
#    In the sidebar, select your output device (Built-in Output, AirPods, etc.)
#    and watch the level meters while you speak into the mic. They should be
#    flat. If they're not — your system is routing mic → output.
#
# 2. System Settings → Accessibility → Audio → Live Listen. Confirm it's off.
#
# 3. Check any running conferencing / DAW / monitoring app for "monitor input"
#    or "listen to this device" toggles. Disable them.
```

If the user can rule out all three and still reproduces the crosstalk, we have a genuine new finding and can reopen for further investigation.

### README update

This document adds an entry to README Known Limitations so users know why, in rare configurations, NotchyPrompter might hear mic audio.

## Sources

- Apple — [`SCStreamConfiguration` reference](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration) (accessed 2026-04-18)
- Apple — [WWDC23 10155 "What's new in ScreenCaptureKit"](https://developer.apple.com/videos/play/wwdc2023/10155/) — audio-tap semantics
- Apple — [Live Listen user guide](https://support.apple.com/guide/mac-help/live-listen-mchl976c3b05/mac) (accessed 2026-04-18)
- Rogue Amoeba — [Under the hood of per-app audio capture](https://rogueamoeba.com/support/knowledgebase/?serial=5A01) (background on why HAL drivers are needed for per-source filtering)
