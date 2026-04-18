// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import NotchyPrompter

@MainActor
final class SessionRecorderTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionRecorder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testEndToEndRoundTrip() throws {
        let r = SessionRecorder(directory: tmpDir, clock: { Date(timeIntervalSince1970: 1_000_000) })
        let mode = Mode(
            id: UUID(), name: "Meeting", systemPrompt: "s",
            attachedContextIDs: [], modelOverride: nil, maxTokens: nil,
            isBuiltIn: true, defaults: nil
        )
        r.startSession(initialMode: mode)
        r.recordTranscript("hello", durationMs: 1234)
        r.recordReply("hi back")
        let session = try r.endSession()

        XCTAssertEqual(session.events.count, 3)  // mode, transcript, reply
        XCTAssertEqual(session.events[0].kind, .mode)
        XCTAssertEqual(session.events[1].kind, .transcript)
        XCTAssertEqual(session.events[2].kind, .reply)

        let onDisk = tmpDir.appendingPathComponent("\(session.id).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: onDisk.path))

        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let reloaded = try dec.decode(Session.self, from: Data(contentsOf: onDisk))
        XCTAssertEqual(reloaded, session)
    }

    func testFilenameCollisionAppendsSuffix() throws {
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let r = SessionRecorder(directory: tmpDir, clock: { fixed })
        let mode = Mode(id: UUID(), name: "m", systemPrompt: "", attachedContextIDs: [],
                        modelOverride: nil, maxTokens: nil, isBuiltIn: true, defaults: nil)

        r.startSession(initialMode: mode)
        let s1 = try r.endSession()

        r.startSession(initialMode: mode)
        let s2 = try r.endSession()

        XCTAssertNotEqual(s1.id, s2.id)
        XCTAssertTrue(s2.id.hasSuffix("-2"))
    }

    func testListSessionsOrderedByStartDesc() throws {
        var t = Date(timeIntervalSince1970: 1_700_000_000)
        let r = SessionRecorder(directory: tmpDir, clock: { t })
        let mode = Mode(id: UUID(), name: "m", systemPrompt: "", attachedContextIDs: [],
                        modelOverride: nil, maxTokens: nil, isBuiltIn: true, defaults: nil)

        r.startSession(initialMode: mode); _ = try r.endSession()
        t = t.addingTimeInterval(3600)
        r.startSession(initialMode: mode); _ = try r.endSession()

        let metas = r.listSessions()
        XCTAssertEqual(metas.count, 2)
        XCTAssertGreaterThan(metas[0].startedAt, metas[1].startedAt)
    }
}
