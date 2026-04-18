// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Decides whether a transcript chunk is worth sending to the Note-taker
/// LLM. Small local instruct models (Qwen 2B) ignore "output nothing for
/// filler" prompt rules and will always emit *something*, so we cull the
/// trivial chunks in Swift before the LLM is called.
///
/// Pure, synchronous, no actor isolation. The caller handles the skip
/// by dropping the chunk and logging the reason via `DebugLog`.
///
/// Scope: Note-taker mode only. Teleprompter has its own smart-firing
/// rules tracked in issue #4 (v0.3 addendum); do not reuse this filter
/// there without a design review.
enum TranscriptFilter {
    enum Decision: Equatable {
        case send
        case skip(reason: String)
    }

    /// Minimum whitespace-delimited token count. Anything shorter is
    /// treated as filler regardless of content. 3 is the pragmatic floor:
    /// short affirmations and greetings are covered by the low-signal
    /// set (caught regardless of token count), while a 3-token utterance
    /// like "yes I did" still carries enough content to be worth sending
    /// to the LLM.
    static let minTokenCount = 3

    /// Known low-signal utterances. Case-insensitive. Matched against the
    /// normalised form of the input (trimmed, lowercased, trailing
    /// punctuation stripped). Exposed as a `Set` so future work can add
    /// entries without touching `decide`.
    static let lowSignal: Set<String> = [
        "thank you",
        "thanks",
        "thanks for watching",
        "thank you for watching",
        "okay",
        "ok",
        "got it",
        "right",
        "yeah",
        "uh huh",
        "mm hmm",
        "[music]",
        "[applause]",
    ]

    /// Matches a chunk that is entirely a non-speech marker. WhisperKit
    /// emits these for short non-speech sounds:
    ///   `*Bip*`, `*Wheat*`, `*Wheep*`, `[Music]`, `[Applause]`, `[ applause ]`
    /// The multi-word bracketed ones (e.g. `[Light music]`) pass the token
    /// floor, so we need a dedicated regex rather than relying on token count
    /// alone. Anchored to the full trimmed chunk — mid-sentence `*emphasis*`
    /// or quoted `[citations]` don't trigger this.
    private static let nonSpeechMarker: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: "^[\\*\\[]\\s*[A-Za-z][A-Za-z ]*\\s*[\\*\\]]$",
            options: []
        )
    }()

    /// Returns `.send` if the chunk should proceed to the LLM, or
    /// `.skip(reason:)` with a short human-readable explanation
    /// suitable for a debug log line.
    ///
    /// Input case and punctuation are preserved for the caller — the
    /// filter only normalises a local copy for comparison.
    static func decide(_ input: String) -> Decision {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .skip(reason: "empty")
        }

        let ns = trimmed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        if nonSpeechMarker.firstMatch(in: trimmed, options: [], range: fullRange) != nil {
            return .skip(reason: "non-speech marker: \(trimmed)")
        }

        let normalised = normalise(trimmed)
        if lowSignal.contains(normalised) {
            return .skip(reason: "low-signal phrase: \(normalised)")
        }

        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        if tokens.count < minTokenCount {
            return .skip(reason: "too short: \(tokens.count) tokens")
        }

        return .send
    }

    /// Lowercase + trim trailing punctuation (.,!?;:) so "Thank you."
    /// and "thank you" both collapse onto the same lookup key. Interior
    /// punctuation and bracketed markers like "[music]" are preserved
    /// so they can be matched as-is.
    private static func normalise(_ s: String) -> String {
        let lowered = s.lowercased()
        let punctuation: Set<Character> = [".", ",", "!", "?", ";", ":"]
        return String(lowered.reversed()
            .drop(while: { punctuation.contains($0) || $0.isWhitespace })
            .reversed())
    }
}
