// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

final class ContextPackTests: XCTestCase {
    func testRoundTrip() throws {
        let id = UUID()
        let pack = ContextPack(id: id, title: "Résumé", body: "# Me\n\nHi.\n")
        let encoded = pack.encoded()
        let decoded = try ContextPack.decoded(from: encoded, fallbackID: UUID())
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.title, "Résumé")
        XCTAssertEqual(decoded.body, "# Me\n\nHi.\n")
    }

    func testMissingFrontmatterUsesFallbackID() throws {
        let raw = "# Just markdown\n\nNo frontmatter.\n"
        let fallback = UUID()
        let decoded = try ContextPack.decoded(from: raw, fallbackID: fallback)
        XCTAssertEqual(decoded.id, fallback)
        XCTAssertEqual(decoded.title, "Untitled")
        XCTAssertEqual(decoded.body, raw)
    }

    func testMalformedFrontmatterFallsBack() throws {
        let raw = "---\nnot-yaml-at-all:::\n---\nbody\n"
        let fallback = UUID()
        let decoded = try ContextPack.decoded(from: raw, fallbackID: fallback)
        XCTAssertEqual(decoded.id, fallback)
    }
}
