// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

@MainActor
final class ContextStoreTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSaveAndReload() throws {
        let store = ContextStore(directory: tmpDir)
        let pack = ContextPack(id: UUID(), title: "Notes", body: "hi")
        try store.save(pack)

        let reloaded = store.loadAll()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].id, pack.id)
        XCTAssertEqual(reloaded[0].body, "hi")
    }

    func testDropInFileWithoutFrontmatterGetsID() throws {
        let url = tmpDir.appendingPathComponent("plain.md")
        try "# hi\n".write(to: url, atomically: true, encoding: .utf8)
        let store = ContextStore(directory: tmpDir)
        let all = store.loadAll()
        XCTAssertEqual(all.count, 1)
        // File should have been rewritten with frontmatter.
        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(rewritten.hasPrefix("---\n"))
    }

    func testDelete() throws {
        let store = ContextStore(directory: tmpDir)
        let pack = ContextPack(id: UUID(), title: "X", body: "x")
        try store.save(pack)
        try store.delete(id: pack.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
