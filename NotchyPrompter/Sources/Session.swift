// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum SessionEventKind: String, Codable {
    case mode
    case transcript
    case reply
}

struct SessionEvent: Codable, Equatable {
    let t: Date
    let kind: SessionEventKind
    // Populated per kind:
    let text: String?
    let durationMs: Int?
    let modeId: String?
    let modeName: String?
}

struct SessionSummary: Codable, Equatable {
    let t: Date
    let prompt: String
    let text: String
}

struct Session: Codable, Equatable, Identifiable {
    let id: String            // e.g. "2026-04-18-143022" or "...-2"
    let startedAt: Date
    var endedAt: Date?
    var events: [SessionEvent]
    var summaries: [SessionSummary]
}

struct SessionMeta: Identifiable, Equatable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let fileURL: URL
    let lastModeName: String?
}
