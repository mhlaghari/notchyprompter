# Lessons

Corrections from the user that should persist across sessions on this project. Read at session start.

## Format

Each lesson:

- **Pattern:** what went wrong or what the user corrected.
- **Rule:** what Claude should do differently next time.
- **Context:** (optional) when this applies — specific files, workflows, commands.

## Lessons so far

### Parallel-agent dispatch must respect rate limits

- **Pattern:** I launched 7 agents in parallel off one Claude account. All hit the rate limit, completed with partial (uncommitted) work. Had to manually take over.
- **Rule:** Before fanning out N agents, estimate token budget and stage the fan-out across quota windows. 5+ long-running agents on one account is risky. Offer a sequential or waved plan as an alternative.
- **Context:** `Agent` tool use when multiple issues would otherwise be dispatched concurrently.

### Whisper hallucinates on non-speech audio

- **Pattern:** WhisperKit emits `*Bip*`, `*Wheat*`, `*Wheep*`, `[Music]`, `[Applause]`, or `Thank you.` for short non-speech sounds or silence. The LLM downstream narrates these as if they were real speech ("Someone named Wheat was just called out").
- **Rule:** Never hand Whisper output directly to an LLM for a user-facing product. Filter first. Minimum filter: (a) token-count floor, (b) low-signal phrase set, (c) regex for bracketed / star-wrapped non-speech markers.
- **Context:** Any Whisper → LLM path in this project. See `TranscriptFilter.swift`.

### Small local LLMs ignore "output nothing" prompt rules

- **Pattern:** Qwen 2B (and similar small instruct models) will always produce something even when the prompt says "if the input is filler, output nothing." Tested empirically.
- **Rule:** If "empty output on empty signal" is required, do the filtering in Swift before the LLM call. Don't trust the prompt. Larger models (Haiku, Qwen 8B+) may obey better, but design the app so it works on the smallest reasonable local model.
- **Context:** Note-taker and similar "silent when not substantial" features. See `TranscriptFilter.swift`.

### Small local LLMs also invent attribution

- **Pattern:** Qwen 2B frames a single-speaker monologue as multi-person dialogue: "One person claimed…", "Another speaker said…", "Speaker advises…". Prompt changes help but don't eliminate it.
- **Rule:** Combine prompt engineering with a Swift-side post-processing stripper. Regex subjects must include article-less variants ("Speaker" without "The"), not just the explicit "The speaker" form.
- **Context:** `AttributionStripper.swift`. Any user-facing LLM output that summarises speech.

### Regex-based NLP strippers need lookaheads to guard possessives

- **Pattern:** A subject-match regex like `^The speakers?` happily matched "The speaker's microphone" and stripped it to "'s microphone" — an anchor on whitespace-or-separator is required.
- **Rule:** After any subject token in a stripping regex, add `(?=\s|[,:\-—–])` (or similar) so the subject must be followed by whitespace or a separator. Word boundary (`\b`) is insufficient because apostrophes, contractions, and possessives produce word boundaries too.
- **Context:** Any regex that strips leading phrases from natural-language output. See `AttributionStripper.swift`.

### Reporting-verb whitelists must include bare infinitives

- **Pattern:** The verb list in `AttributionStripper` had `mentions|mentioned` but not `mention`. Plural subjects use the bare form ("Speakers mention…", "Users want…"), so the partial list only stripped the subject and left the verb behind.
- **Rule:** When whitelisting reporting verbs for LLM-output scrubbing, enumerate all three forms: bare infinitive, third-person singular, past tense. "Says / said / say" — all three. Conservative: unknown verbs should pass through unchanged, not over-strip.
- **Context:** `AttributionStripper.swift`. Any NLP post-processing that relies on a verb list.

### macOS TCC keys off signing identity DR, not just bundle id

- **Pattern:** Every `./build.sh` with ad-hoc signing (`codesign --sign -`) produced a new cdhash, which TCC treats as a new app, wiping the Screen Recording grant.
- **Rule:** For any macOS app that uses TCC-gated APIs (Screen Recording, Microphone, Accessibility, etc.), ship a stable self-signed identity for dev use. See `scripts/setup-dev-signing.sh` for the working setup (self-signed cert + `set-key-partition-list` + `add-trusted-cert`).
- **Context:** Any macOS app with TCC dependencies. Project CLAUDE.md documents this gotcha.

### OpenSSL 3.x PKCS#12 is incompatible with macOS `security`

- **Pattern:** `openssl pkcs12 -export` on OpenSSL 3.x produces a bundle that macOS `security import` rejects with "MAC verification failed (wrong password?)". macOS's CDSA-era reader only speaks PBE-SHA1-3DES + SHA1 MAC.
- **Rule:** Always pass `-legacy` to `openssl pkcs12 -export` when the output will be imported into the macOS keychain. Fall back to bare `-export` for OpenSSL 1.x where `-legacy` does not exist.
- **Context:** Any script that generates a PKCS#12 for `security import`. See `scripts/setup-dev-signing.sh`.

### Menu-bar status items can be occluded by the notch

- **Pattern:** `LSUIElement = true` + NSStatusBar-only UI = the app is unreachable when too many status items overflow past the notch on a MacBook Pro / Air. User can't find it, has to Cmd-Tab.
- **Rule:** Apps whose only entry point is the menu bar must have a fallback: global hotkey (`NSEvent.addGlobalMonitorForEvents`), or a non-occluded overlay button, or an optional Dock icon toggle.
- **Context:** Any macOS LSUIElement app intended to run on notched hardware. Tracked on the NotchyPrompter roadmap.

### Runtime overrides beat persisted-state migrations when changing a built-in's default

- **Pattern:** Changed Note-taker's default firing cadence from `.debounce(2.0)` to `.silent`. The seed already persisted `.debounce(2.0)` to `modes.json`, so every existing install would have needed a migration pass to pick up the new behaviour.
- **Rule:** When changing a built-in's default behaviour, prefer a runtime override in a computed property (gated on `defaults.name` or an equivalent stable identifier) over adding a persisted-state migration. No disk rewrite, no staged-migration ordering concerns, reversible by flipping one line.
- **Context:** `Mode.effectiveFireCadence`. Applies to any `Codable` settings that have both a "stored" and "resolved at runtime" form.

### Per-chunk LLM firing loses narrative thread

- **Pattern:** VAD-chunked transcripts (2–5 s paragraphs) fed one-at-a-time to an LLM produce per-fragment paraphrases instead of a synthesised recap. Qwen sees 80 characters of mid-sentence text and comments on that fragment because it can't see the thread — it only ever gets one paragraph.
- **Rule:** For summarisation modes (Note-taker), accumulate across a longer window (60–90 s or silence-triggered) and send the whole accumulation in one LLM call with a prompt that permits empty output. Per-chunk firing is correct for Teleprompter (reply latency matters) but wrong for note-taking.
- **Context:** `Pipeline.dispatchChunk` → `handleLLM`. Transcript-primary summariser work in planning.

### Wall-clock VAD debounce eats paragraphs for rapid speakers

- **Pattern:** Energy-VAD + `trailingSilenceMs` flushed mid-paragraph when the speaker took a sub-second breath. Raising the threshold (400 → 900 ms) was a bandaid; 1 s breaths still split. Confirmed in live session `sessions/2026-04-19-200942.log` — "…a benchmark for how good" / "this model is at trading" is one sentence, split by the old VAD.
- **Rule:** Treat VAD chunking as endpointing: emit on **end-of-utterance + grace window** (1200 ms default), not wall-clock silence count. Speech inside the grace resets silenceMs and keeps the buffer growing. Mechanically similar to bumping the threshold, but the mental model makes the intent explicit and the regression test (1050 ms mid-paragraph pause must not flush) guards against future "knob bumps".
- **Context:** `VAD.swift`. Industry reference: OpenAI Realtime `server_vad` uses 500 ms; LiveKit Agents uses 500 ms + semantic EoU. Our 1200 ms is tuned for note-taking prompter (fewer longer chunks > snappy turn-taking).

### ScreenCaptureKit DOES filter audio per-app — just not per-window

- **Pattern:** Prior research doc claimed "no public SCK API filters by audio source; per-source capture requires a HAL audio driver". False. `SCContentFilter(display:excludingApplications:exceptingWindows:)` gates audio by application (WWDC22 session 10155 — audio policy is app-level by design). Our own filter had `excludingApplications: []` since bring-up, letting speech daemons leak.
- **Rule:** When an external commenter contradicts existing docs, verify before dismissing. In this case the commenter (`m13v` on #7) was correct; the doc was wrong. Apple's audio policy distinguishes per-window (no API) from per-app (public API since macOS 13.0).
- **Context:** `AudioCapture.swift`. Also: `SCShareableContent.excludingDesktopWindows(_, onScreenWindowsOnly:)` must pass `false` for `onScreenWindowsOnly` — background daemons (`speechsynthesisd`, `corespeechd`, etc.) don't own on-screen windows, so the default `true` hides them and the exclusion becomes a no-op. Post-14.4 alternative: `AudioHardwareCreateProcessTap` (cleaner, per-PID, but a full rewrite).

### Bundle IDs for macOS speech daemons (for future reference)

- `com.apple.speech.speechsynthesisd` — modern TTS daemon
- `com.apple.speech.synthesisserver` — legacy TTS LaunchAgent (still present on 14/15)
- `com.apple.SpeechRecognitionCore.speechrecognitiond` — dictation (framework name `SpeechRecognitionCore` is NOT the bundle ID)
- `com.apple.corespeechd` — CoreSpeech framework daemon (Siri/dictation audio pipeline)
- `com.apple.SiriTTSService` — Siri TTS
- `com.apple.assistantd` — Siri orchestrator

### User prefers concrete step-by-step over option menus

- **Pattern:** Presented two merge workflows (one-at-a-time vs combined test branch) and asked the user to pick. User responded with confusion — "which ones should I merge? do I merge without testing?". Dense technical summaries also triggered pushback ("I am so confused").
- **Rule:** For operational questions ("how do I use this?"), give ONE recommended flow with exact commands, then offer the alternative as a one-liner ("say the word if you want combined"). State the current-directory assumption explicitly in code snippets — user ran `cd NotchyPrompter && ./build.sh` from within `NotchyPrompter/` because the earlier snippet included `cd`.
- **Context:** General communication. User is confident with concepts but prefers unambiguous operational instructions.
