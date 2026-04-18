---
description: Remove per-callback debug logs from Pipeline.swift and AudioCapture.swift.
---

Per the CHANGELOG "To do": strip the per-callback noise logs, keep only error paths.

Targets:
- `NotchyPrompter/Sources/AudioCapture.swift` — remove the `audioCbCount` / `screenCbCount` / `lastCbLog` logging block (the "AudioCapture callbacks last 3s" log). Keep the error-path `NSLog` calls (convert failures, stream stop errors).
- `NotchyPrompter/Sources/Pipeline.swift` — remove the `audio: N blocks last 3s, peak rms=...` log in the forwarder task, and the `vad: emitting chunk` / `transcribe -> ...` / `llm: calling ... with chunk` / `llm: stream ended, N deltas` per-chunk logs. Keep error logs and the TCC-detection log.

Show the diff. Do not commit automatically — let the user review.
