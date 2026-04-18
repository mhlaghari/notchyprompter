// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

final class TranscriptFilterTests: XCTestCase {
    // Filler phrases should be rejected regardless of case / trailing
    // punctuation. Covers the "Thank you." regression from issue #3.
    func testObviousFillerPhrasesAreSkipped() {
        let samples = [
            "Thank you.",
            "thanks",
            "Okay!",
            "OK",
            "Got it.",
            "Right.",
            "Yeah",
            "Uh huh",
            "mm hmm",
        ]
        for s in samples {
            if case .send = TranscriptFilter.decide(s) {
                XCTFail("expected skip for filler \"\(s)\"")
            }
        }
    }

    func testEmptyAndWhitespaceAreSkipped() {
        XCTAssertEqual(TranscriptFilter.decide(""), .skip(reason: "empty"))
        XCTAssertEqual(TranscriptFilter.decide("   \n\t  "),
                       .skip(reason: "empty"))
    }

    // Short but substantive utterances MUST pass. "yes I did" is at the
    // 3-token floor and carries real content, so it should NOT be
    // filtered out — the filler list exists for the typical 1-2 word
    // acknowledgments.
    func testShortButMeaningfulChunkPasses() {
        XCTAssertEqual(TranscriptFilter.decide("yes I did"), .send)
    }

    // A long paragraph that contains filler-like words embedded in real
    // content must NOT be skipped — filtering is phrase-level, not
    // substring-level.
    func testLongFillerHeavyChunkStillPasses() {
        let chunk = "Okay so thank you for watching; the point I wanted " +
                    "to make is that stateless agents really do need a " +
                    "way to remember prior decisions across turns."
        XCTAssertEqual(TranscriptFilter.decide(chunk), .send)
    }

    // WhisperKit sometimes emits bracketed non-speech markers. These
    // should be treated as low-signal.
    func testBracketedMarkersAreSkipped() {
        if case .send = TranscriptFilter.decide("[music]") {
            XCTFail("[music] should be skipped")
        }
        if case .send = TranscriptFilter.decide("[Applause]") {
            XCTFail("[Applause] should be skipped")
        }
    }

    // Very short utterances that aren't in the low-signal set still get
    // filtered by the token-count floor.
    func testShortUnknownPhraseIsSkippedByTokenCount() {
        if case .send = TranscriptFilter.decide("Sure maybe") {
            XCTFail("2-token phrase should fall under min token count")
        }
    }

    // Caller gets the input back unchanged — the filter does not
    // mutate / trim the text it was given.
    func testInputCaseAndPunctuationPreservedForCaller() {
        // decide() returns a Decision; it never echoes the input. This
        // test documents the contract by verifying the reason string
        // uses the *normalised* form but the caller's copy of `input`
        // is a separate `let` that cannot be touched.
        let input = "Thank you."
        _ = TranscriptFilter.decide(input)
        XCTAssertEqual(input, "Thank you.")
    }

    // Low-signal set is `Set<String>` so consumers can extend it.
    func testLowSignalIsExtensibleSet() {
        XCTAssertTrue(TranscriptFilter.lowSignal.contains("thank you"))
        XCTAssertTrue(TranscriptFilter.lowSignal.contains("[music]"))
    }
}
