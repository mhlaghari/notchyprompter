# Research — `m13v` comments on Issues #7 and #8

**Date:** 2026-04-19
**Trigger:** External commenter `m13v` left technical suggestions on open issues #7 (dictation/self-audio cross-talk) and #8 (VAD mid-paragraph flush). This doc verifies both and decides which to implement.

---

## Issue #7 — dictation / self-audio cross-talk in SCK capture

### `m13v`'s claim

> "excludesCurrentProcessAudio=true fixes the trivial self-capture loop but dictation still leaks because macos plays confirmation chirps and sometimes intermediate recognition audio through the default output device, which SCStream legitimately captures. clean fix was per-app audio filtering via SCShareableContent.applications on 14.2+, excluding com.apple.speech.synthesisserver and SpeechRecognitionCore."

### Verdict — substantially correct

1. **`SCContentFilter(display:excludingApplications:exceptingWindows:)` does gate audio by app.** ScreenCaptureKit's audio policy is app-level by design (WWDC22 session 10155; docs on `capturesAudio`). Available since macOS 13.0.
2. **The research doc on PR #14 is WRONG** when it says "No public SCK API filters by audio source." That's true at the *window* level only. Per-app filtering exists and works for audio.
3. **Bundle IDs `m13v` gave are slightly off:**
   - `com.apple.speech.synthesisserver` — real (LaunchAgent plist).
   - `SpeechRecognitionCore` — this is a **framework name, not a bundle ID**. Actual daemon: `com.apple.SpeechRecognitionCore.speechrecognitiond`.
4. **Full exclusion set to use:**
   ```
   com.apple.speech.speechsynthesisd            # modern TTS daemon
   com.apple.speech.synthesisserver             # legacy TTS name
   com.apple.SpeechRecognitionCore.speechrecognitiond  # dictation
   com.apple.corespeechd                        # CoreSpeech (Siri/dictation audio)
   com.apple.SiriTTSService                     # Siri TTS
   com.apple.assistantd                         # Siri orchestrator
   ```
5. **Gotcha:** Our current `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` call (`AudioCapture.swift:31`) hides background daemons. Must pass `onScreenWindowsOnly: false` so speech processes appear in `.applications`.

### Longer-term alternative (not doing now)

Apple's preferred post-14.4 API is `AudioHardwareCreateProcessTap` (see `insidegui/AudioCap`). Cleaner per-PID inclusion/exclusion, no fake-video-stream workaround. Out of scope for this iteration — would be a full rewrite of `AudioCapture.swift`.

### Code snippet

```swift
let excludedBundleIDs: Set<String> = [
    "com.apple.speech.speechsynthesisd",
    "com.apple.speech.synthesisserver",
    "com.apple.SpeechRecognitionCore.speechrecognitiond",
    "com.apple.corespeechd",
    "com.apple.SiriTTSService",
    "com.apple.assistantd",
]
let content = try await SCShareableContent.excludingDesktopWindows(
    false, onScreenWindowsOnly: false)
let excluded = content.applications.filter {
    excludedBundleIDs.contains($0.bundleIdentifier)
}
let filter = SCContentFilter(
    display: display,
    excludingApplications: excluded,
    exceptingWindows: []
)
```

---

## Issue #8 — VAD fires mid-paragraph for rapid speakers

### `m13v`'s claim

> "energy VAD is the wrong tool for rapid speakers... silero v5 onnx via coreml ran ~2ms per 30ms frame on m1, false negatives dropped from ~12% to under 2%. for the boundary problem decouple emission from wall clock entirely. emit on VAD end-of-utterance plus a 1.5s soft grace, accumulator concatenates if grace expires before next speech. the wall-clock debounce is what's eating your paragraphs."

### Verdict — (B) grace period is the real fix; (A) Silero is optional

**(B) grace-period concatenator** — correct. Canonical names: **hangover timer** (WebRTC/GSM), **endpointing** (Kaldi/ASR), **end-of-utterance / turn detection** (modern voice-agent). Production defaults:
- OpenAI Realtime `server_vad`: 500 ms silence
- LiveKit Agents turn-detector: ~500 ms (+ transformer on ASR partials)
- WebRTC VAD: 3-frame (90 ms) hangover
- **1.5s is 2-3× industry default** — long, but fine for a note-taking prompter where fewer/longer chunks > snappy turn-taking. We'll start at 1.2s and tune.

**(A) Silero v5** — nice-to-have, not a fix. The failure mode is wall-clock emission, not energy-VAD false-negatives. Swapping detectors without changing the emission logic keeps mis-firing on the same clock. Our current RMS detector is good enough for speech-end detection; the grace-period wrapper around it is the actual remedy.

**If we do Silero later:** `paean-ai/silero-vad-swift` (MIT, SPM-native, CoreML, ~2MB, zero deps) is the right pick. 7 stars but exactly the right shape. Fallback: `helloooideeeeea/RealTimeCutVADLibrary` (62 stars, but requires `onnxruntime-objc`).

### Failure modes of grace-period

- **Thinker pause > grace** — speaker pauses 1.6s mid-sentence, grace expires, chunk fires mid-sentence. Mitigations: adaptive grace extended on non-terminal punctuation in ASR partials; semantic EoU model (LiveKit's `turn_detector`). Not solving now; accept this trade-off.
- **Existing 15 s hard cap** still catches pathological cases.

### Refactor shape

```
Current (wall-clock):
  onFrame(speech): speechMs++; silenceMs=0; buffer.append
  onFrame(silence, inSpeech): buffer.append; silenceMs++
  flush when speechMs >= 800 && silenceMs >= 900  OR  totalMs >= 15000

New (grace-period):
  onFrame(speech): if graceActive, cancel grace; buffer.append; speechMs++
  onFrame(silence, inSpeech): buffer.append; silenceMs++
  when silenceMs >= endOfUtteranceMs (400ms): arm grace timer (1.2s)
  grace fires: emit buffer, reset
  new speech arrives before grace fires: keep existing buffer, concat
  hard cap totalMs >= 15000: emit regardless
```

~30 lines delta to `VAD.swift`. Zero new deps.

---

## Implementation plan — do / don't

### DO

1. **Grace-period VAD refactor (supersedes PR #10)** — new branch, close #10.
2. **Per-app audio exclusion (replaces / extends PR #14)** — rewrite the research doc's wrong conclusion, add `excludingApplications` code to `AudioCapture.swift`, keep the README Known-limitations entry, ship as one PR closing #7.

### DON'T (now)

- **Don't pull Silero v5 in now.** Pure wall-clock → grace-period refactor should resolve the reported problem. Revisit only if RMS false-negatives show up in live sessions after the grace-period ships.
- **Don't migrate to `AudioHardwareCreateProcessTap`** yet. Much bigger rewrite; stick with SCK exclusion list for now.
- **Don't add a transformer EoU / semantic endpointing.** Overkill; keep the 30-line refactor.
- **Don't ship PR #10 as-is.** It's a bandaid (trailing silence 400→900 ms) that doesn't solve the root cause. Close in favour of the grace-period branch.

### DEFER / unchanged

- **PR #13 (Ollama picker)** — complete, just needs manual UI smoke-test.
- **PR #9 (Teleprompter v0.3 prompt)** — complete, needs live A/B.
- **PR #15 (mode-change diagnostic)** — logging only, waits on live repro.

---

## Sources

- [SCContentFilter — Apple](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
- [`capturesAudio` — Apple](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio)
- [Capturing screen content in macOS — Apple](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)
- [Take ScreenCaptureKit to the next level — WWDC22/10155](https://developer.apple.com/videos/play/wwdc2022/10155/)
- [Capturing system audio with Core Audio taps — Apple](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
- [insidegui/AudioCap](https://github.com/insidegui/AudioCap) — post-14.4 process-tap sample
- [Mnpn/Azayaka Recording.swift](https://github.com/Mnpn/Azayaka/blob/main/Azayaka/Recording.swift) — real `excludingApplications` use
- [snakers4/silero-vad](https://github.com/snakers4/silero-vad)
- [paean-ai/silero-vad-swift](https://github.com/paean-ai/silero-vad-swift) — MIT, SPM, CoreML
- [helloooideeeeea/RealTimeCutVADLibrary](https://github.com/helloooideeeeea/RealTimeCutVADLibrary)
- [OpenAI Realtime VAD docs](https://platform.openai.com/docs/guides/realtime-vad)
- [LiveKit turn detection](https://docs.livekit.io/agents/build/turns/)
- [LiveKit transformer EoU blog](https://blog.livekit.io/using-a-transformer-to-improve-end-of-turn-detection)
- Issue comments: [#7](https://github.com/mhlaghari/teleprompter/issues/7), [#8](https://github.com/mhlaghari/teleprompter/issues/8)
