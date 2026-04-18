// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

final class LLMRequestAssemblyTests: XCTestCase {
    func testSystemBlocksWithNoContexts() {
        let req = LLMRequest(
            chunk: "hi",
            history: [],
            systemPrompt: "SYS",
            attachedContexts: [],
            modelOverride: nil,
            maxTokensOverride: nil
        )
        let blocks = ClaudeClient.systemBlocks(for: req)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["text"] as? String, "SYS")
        let cc = blocks[0]["cache_control"] as? [String: String]
        XCTAssertEqual(cc?["type"], "ephemeral")
    }

    func testTwoContextsGetOwnBlocks() {
        let c1 = ContextPack(id: UUID(), title: "A", body: "AAA")
        let c2 = ContextPack(id: UUID(), title: "B", body: "BBB")
        let req = LLMRequest(
            chunk: "hi", history: [], systemPrompt: "SYS",
            attachedContexts: [c1, c2],
            modelOverride: nil, maxTokensOverride: nil
        )
        let blocks = ClaudeClient.systemBlocks(for: req)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0]["text"] as? String, "SYS")
        XCTAssertEqual(blocks[1]["text"] as? String, "AAA")
        XCTAssertEqual(blocks[2]["text"] as? String, "BBB")
    }

    func testOverflowConcatsIntoFinalBlock() {
        let ctx = (0..<5).map { i in
            ContextPack(id: UUID(), title: "C\(i)", body: "BODY\(i)")
        }
        let req = LLMRequest(
            chunk: "hi", history: [], systemPrompt: "SYS",
            attachedContexts: ctx,
            modelOverride: nil, maxTokensOverride: nil
        )
        let blocks = ClaudeClient.systemBlocks(for: req)
        // 1 system + 2 own blocks + 1 concat'd tail block = 4 (cap of 4)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0]["text"] as? String, "SYS")
        XCTAssertEqual(blocks[1]["text"] as? String, "BODY0")
        XCTAssertEqual(blocks[2]["text"] as? String, "BODY1")
        let tail = blocks[3]["text"] as? String ?? ""
        XCTAssertTrue(tail.contains("BODY2"))
        XCTAssertTrue(tail.contains("BODY3"))
        XCTAssertTrue(tail.contains("BODY4"))
        XCTAssertTrue(tail.contains("---"))
    }
}
