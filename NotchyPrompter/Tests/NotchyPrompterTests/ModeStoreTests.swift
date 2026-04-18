// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

@MainActor
final class ModeStoreTests: XCTestCase {
    private var tmpFile: URL!

    override func setUp() async throws {
        tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModeStore-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpFile)
    }

    func testSeedsWhenMissing() throws {
        let store = ModeStore(file: tmpFile)
        XCTAssertEqual(store.modes.count, 5)
        XCTAssertTrue(store.modes.contains { $0.name == "Watching" && $0.isBuiltIn })
        XCTAssertTrue(store.modes.contains { $0.name == "Interview" && !$0.isBuiltIn })
    }

    func testSaveAndReload() throws {
        let store = ModeStore(file: tmpFile)
        var m = store.modes.first { $0.name == "Meeting" }!
        m.systemPrompt = "overridden"
        try store.upsert(m)

        let store2 = ModeStore(file: tmpFile)
        let reloaded = store2.modes.first { $0.name == "Meeting" }!
        XCTAssertEqual(reloaded.systemPrompt, "overridden")
        XCTAssertTrue(reloaded.isDirty)
    }

    func testResetToDefault() throws {
        let store = ModeStore(file: tmpFile)
        var m = store.modes.first { $0.name == "Meeting" }!
        let originalPrompt = m.systemPrompt
        m.systemPrompt = "something else"
        try store.upsert(m)
        try store.resetToDefaults(id: m.id)
        let restored = store.modes.first { $0.name == "Meeting" }!
        XCTAssertEqual(restored.systemPrompt, originalPrompt)
    }

    func testDeleteBuiltInIsRejected() throws {
        let store = ModeStore(file: tmpFile)
        let watching = store.modes.first { $0.name == "Watching" }!
        XCTAssertThrowsError(try store.delete(id: watching.id))
    }

    func testDeleteCustom() throws {
        let store = ModeStore(file: tmpFile)
        let interview = store.modes.first { $0.name == "Interview" }!
        try store.delete(id: interview.id)
        XCTAssertNil(store.modes.first { $0.id == interview.id })
    }
}
