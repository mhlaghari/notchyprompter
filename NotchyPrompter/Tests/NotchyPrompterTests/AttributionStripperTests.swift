// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

final class AttributionStripperTests: XCTestCase {
    // Regression coverage for the original case from issue #2: bullets
    // that lead with "The speaker …" should have the prefix stripped.
    func testStripsTheSpeakerPrefix() {
        XCTAssertEqual(
            AttributionStripper.cleanLine("- The speaker says Opus 4.7 is really good"),
            "- Opus 4.7 is really good"
        )
    }

    // Article-less variants observed in live Qwen 2B output on
    // sessions/2026-04-18-105531.log — "Speaker advises" without "The".
    func testStripsArticleLessSubjects() {
        let cases: [(String, String)] = [
            ("- Speaker advises researching and trading items",
             "- Researching and trading items"),
            ("- User claims Opus 4.7 will be good",
             "- Opus 4.7 will be good"),
            ("- Speakers mention the upcoming release",
             "- The upcoming release"),
            ("- Users want a better model picker",
             "- A better model picker"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(AttributionStripper.cleanLine(input), expected,
                           "strip failed for \"\(input)\"")
        }
    }

    // Non-bullet lines must pass through untouched — the stripper only
    // operates on lines that lead with a bullet marker.
    func testNonBulletLinesPassThrough() {
        let line = "The speaker said we should regroup at 3pm."
        XCTAssertEqual(AttributionStripper.cleanLine(line), line)
    }

    // Strip must not eat legitimate content that only happens to start
    // with a subject token (e.g. possessive or role context).
    func testDoesNotStripPossessive() {
        // "The speaker's" — the "'s" makes this a possessive, not a subject+verb.
        let line = "- The speaker's microphone was muted"
        XCTAssertEqual(AttributionStripper.cleanLine(line), line,
                       "possessive must survive strip")
    }

    // If stripping would leave an empty bullet, the whole line is dropped.
    func testEmptyAfterStripDropsLine() {
        XCTAssertEqual(AttributionStripper.cleanLine("- The speaker says"), "")
    }

    // clean(_:) applies to every line of a multi-line reply, preserving
    // blank lines between bullets.
    func testCleanAppliesToAllLines() {
        let input = """
            - Speaker notes the market closed early
            - User claims tariffs will rise

            - The speaker emphasized the timeline
            """
        let expected = """
            - The market closed early
            - Tariffs will rise

            - The timeline
            """
        XCTAssertEqual(AttributionStripper.clean(input), expected)
    }
}
