// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Resolves the on-disk locations used by v0.2 stores.
///
/// Persistent app state (modes.json, context packs) lives under
/// ~/Library/Application Support/NotchyPrompter/.
/// Per-run session artifacts (.log / .json) live in the project folder at
/// ~/teleprompter/sessions/ so the user can browse them alongside the code
/// without descending into ~/Library. The project's .gitignore excludes
/// `sessions/` so transcripts never get committed.
/// Directories are created lazily on first access.
enum Paths {
    static var appSupportDir: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NotchyPrompter", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modesFile: URL {
        appSupportDir.appendingPathComponent("modes.json")
    }

    static var contextsDir: URL {
        let d = appSupportDir.appendingPathComponent("contexts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static var sessionsDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let d = home.appendingPathComponent("teleprompter/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}
