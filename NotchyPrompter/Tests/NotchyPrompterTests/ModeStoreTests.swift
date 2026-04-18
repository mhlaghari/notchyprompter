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
        XCTAssertEqual(store.modes.count, 3)
        XCTAssertTrue(store.modes.contains { $0.name == "Note-taker" && $0.isBuiltIn })
        XCTAssertTrue(store.modes.contains { $0.name == "Teleprompter" && $0.isBuiltIn })
        XCTAssertTrue(store.modes.contains { $0.name == "Custom" && $0.isBuiltIn })
    }

    func testSaveAndReload() throws {
        let store = ModeStore(file: tmpFile)
        var m = store.modes.first { $0.name == "Teleprompter" }!
        m.systemPrompt = "overridden"
        try store.upsert(m)

        let store2 = ModeStore(file: tmpFile)
        let reloaded = store2.modes.first { $0.name == "Teleprompter" }!
        XCTAssertEqual(reloaded.systemPrompt, "overridden")
        XCTAssertTrue(reloaded.isDirty)
    }

    func testResetToDefault() throws {
        let store = ModeStore(file: tmpFile)
        var m = store.modes.first { $0.name == "Teleprompter" }!
        let originalPrompt = m.systemPrompt
        m.systemPrompt = "something else"
        try store.upsert(m)
        try store.resetToDefaults(id: m.id)
        let restored = store.modes.first { $0.name == "Teleprompter" }!
        XCTAssertEqual(restored.systemPrompt, originalPrompt)
    }

    func testDeleteBuiltInIsRejected() throws {
        let store = ModeStore(file: tmpFile)
        let noteTaker = store.modes.first { $0.name == "Note-taker" }!
        XCTAssertThrowsError(try store.delete(id: noteTaker.id))
    }

    func testDeleteCustom() throws {
        let store = ModeStore(file: tmpFile)
        // No seeded customs in the new seed; create one, then delete it.
        let custom = Mode(
            id: UUID(), name: "Scratch", systemPrompt: "",
            attachedContextIDs: [], modelOverride: nil, maxTokens: nil,
            isBuiltIn: false, defaults: nil
        )
        try store.upsert(custom)
        XCTAssertNotNil(store.modes.first { $0.id == custom.id })
        try store.delete(id: custom.id)
        XCTAssertNil(store.modes.first { $0.id == custom.id })
    }

    func testLegacyWatchingMigratesToNoteTaker() throws {
        // Simulate a v0.2.0 modes.json with the old names.
        let legacyWatching = Mode(
            id: UUID(), name: "Watching", systemPrompt: "legacy watching prompt",
            attachedContextIDs: [], modelOverride: nil, maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Watching", systemPrompt: "legacy watching prompt")
        )
        let legacyMeeting = Mode(
            id: UUID(), name: "Meeting", systemPrompt: "legacy meeting prompt",
            attachedContextIDs: [], modelOverride: nil, maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Meeting", systemPrompt: "legacy meeting prompt")
        )
        let legacyIDWatching = legacyWatching.id
        let legacyIDMeeting = legacyMeeting.id

        let enc = JSONEncoder()
        try enc.encode([legacyWatching, legacyMeeting]).write(to: tmpFile)

        let store = ModeStore(file: tmpFile)
        let noteTaker = store.modes.first { $0.name == "Note-taker" }!
        let teleprompter = store.modes.first { $0.name == "Teleprompter" }!
        XCTAssertEqual(noteTaker.id, legacyIDWatching,
                       "UUID must be preserved so activeModeID stays valid")
        XCTAssertEqual(teleprompter.id, legacyIDMeeting)
        // Pristine (unmodified) legacy built-ins get the new prompt.
        XCTAssertEqual(noteTaker.systemPrompt, SeedData.noteTakerPrompt)
        XCTAssertEqual(teleprompter.systemPrompt, SeedData.teleprompterPrompt)
    }

    // Note-taker's effectiveFireCadence must always resolve to .silent,
    // regardless of what the stored fireCadence says. Guards against legacy
    // modes.json that seeded .debounce(2.0) as well as future edits that
    // might accidentally set something else.
    func testNoteTakerEffectiveCadenceIsSilent() throws {
        let store = ModeStore(file: tmpFile)
        let noteTaker = store.modes.first { $0.name == "Note-taker" }!
        XCTAssertEqual(noteTaker.effectiveFireCadence, .silent)
    }

    // Even if a legacy modes.json stored .debounce(2.0) for Note-taker, the
    // runtime cadence must still be .silent.
    func testLegacyNoteTakerWithDebounceStillResolvesSilent() throws {
        let legacyNoteTaker = Mode(
            id: UUID(), name: "Note-taker", systemPrompt: "prompt",
            attachedContextIDs: [], modelOverride: nil, maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Note-taker", systemPrompt: "prompt"),
            fireCadence: .debounce(seconds: 2.0)
        )
        XCTAssertEqual(legacyNoteTaker.effectiveFireCadence, .silent)
    }

    func testLegacyCustomizedWatchingKeepsUserPromptButGetsNewName() throws {
        // User had customized their v0.2.0 Watching prompt.
        let customized = Mode(
            id: UUID(), name: "Watching", systemPrompt: "MY PROMPT",
            attachedContextIDs: [], modelOverride: nil, maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Watching", systemPrompt: "legacy default")
        )
        let enc = JSONEncoder()
        try enc.encode([customized]).write(to: tmpFile)

        let store = ModeStore(file: tmpFile)
        let migrated = store.modes.first { $0.isBuiltIn }!
        XCTAssertEqual(migrated.name, "Note-taker")
        XCTAssertEqual(migrated.systemPrompt, "MY PROMPT",
                       "User customization must survive migration")
        XCTAssertEqual(migrated.defaults?.systemPrompt, SeedData.noteTakerPrompt,
                       "Defaults should point to the new-version default")
    }
}
