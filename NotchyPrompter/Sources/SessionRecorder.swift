// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

@MainActor
final class SessionRecorder {
    typealias Clock = () -> Date

    private let directory: URL
    private let clock: Clock
    private var current: Session?
    private var liveLogURL: URL?

    init(directory: URL = Paths.sessionsDir, clock: @escaping Clock = Date.init) {
        self.directory = directory
        self.clock = clock
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
    }

    var hasActiveSession: Bool { current != nil }

    /// URL of the live plaintext log for the currently-running session, or
    /// nil if none. Useful for tailing the transcript in real time.
    var currentLogURL: URL? { liveLogURL }

    func startSession(initialMode: Mode) {
        let now = clock()
        let baseID = Self.filenameStem(for: now)
        let id = uniqueID(stem: baseID)
        var s = Session(id: id, startedAt: now, endedAt: nil, events: [], summaries: [])
        s.events.append(SessionEvent(
            t: now, kind: .mode,
            text: nil, durationMs: nil,
            modeId: initialMode.id.uuidString, modeName: initialMode.name
        ))
        current = s
        let logURL = directory.appendingPathComponent("\(id).log")
        liveLogURL = logURL
        let header = "[session \(id) started \(Self.iso.string(from: now))]\n"
            + "[mode: \(initialMode.name)]\n"
        try? header.write(to: logURL, atomically: true, encoding: .utf8)
    }

    func recordTranscript(_ text: String, durationMs: Int) {
        guard var s = current else { return }
        let t = clock()
        s.events.append(SessionEvent(
            t: t, kind: .transcript,
            text: text, durationMs: durationMs,
            modeId: nil, modeName: nil
        ))
        current = s
        appendLog("[\(Self.iso.string(from: t))] them: \(text)\n")
    }

    func recordReply(_ text: String, label: String = "ai") {
        guard var s = current else { return }
        let t = clock()
        s.events.append(SessionEvent(
            t: t, kind: .reply,
            text: text, durationMs: nil,
            modeId: nil, modeName: nil
        ))
        current = s
        // Pad label to align with "them:" (5 chars) so logs stay column-aligned
        // when the label is shorter (e.g. "ai"  ).
        let padded = label.padding(toLength: max(5, label.count), withPad: " ", startingAt: 0)
        appendLog("[\(Self.iso.string(from: t))] \(padded): \(text)\n")
    }

    func recordModeChange(_ mode: Mode) {
        guard var s = current else { return }
        let t = clock()
        s.events.append(SessionEvent(
            t: t, kind: .mode,
            text: nil, durationMs: nil,
            modeId: mode.id.uuidString, modeName: mode.name
        ))
        current = s
        appendLog("[\(Self.iso.string(from: t))] [mode: \(mode.name)]\n")
    }

    private func appendLog(_ line: String) {
        guard let url = liveLogURL else {
            DebugLog.write("SessionRecorder.appendLog skipped: liveLogURL is nil")
            return
        }
        guard let data = line.data(using: .utf8) else {
            DebugLog.write("SessionRecorder.appendLog skipped: UTF-8 encode failed")
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            DebugLog.write("SessionRecorder.appendLog error: \(error.localizedDescription) url=\(url.path)")
        }
    }

    private static let iso = ISO8601DateFormatter()

    @discardableResult
    func endSession() throws -> Session {
        guard var s = current else {
            throw NSError(domain: "SessionRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no active session"])
        }
        s.endedAt = clock()
        try writeToDisk(s)
        current = nil
        return s
    }

    func appendSummary(sessionID: String, prompt: String, text: String) throws {
        let url = directory.appendingPathComponent("\(sessionID).json")
        let data = try Data(contentsOf: url)
        var s = try Self.decoder.decode(Session.self, from: data)
        s.summaries.append(SessionSummary(t: clock(), prompt: prompt, text: text))
        try writeToDisk(s)
    }

    func listSessions() -> [SessionMeta] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory,
                                                     includingPropertiesForKeys: nil)
        else { return [] }
        var metas: [SessionMeta] = []
        for url in items where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let s = try? Self.decoder.decode(Session.self, from: data)
            else { continue }
            let lastMode = s.events.reversed().first { $0.kind == .mode }?.modeName
            metas.append(SessionMeta(
                id: s.id, startedAt: s.startedAt, endedAt: s.endedAt,
                fileURL: url, lastModeName: lastMode
            ))
        }
        return metas.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Helpers

    private static func filenameStem(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        return df.string(from: date)
    }

    private func uniqueID(stem: String) -> String {
        var candidate = stem
        var n = 2
        while FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("\(candidate).json").path) {
            candidate = "\(stem)-\(n)"
            n += 1
        }
        return candidate
    }

    private func writeToDisk(_ session: Session) throws {
        let url = directory.appendingPathComponent("\(session.id).json")
        try Self.encoder.encode(session).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
