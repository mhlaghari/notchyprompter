import Foundation

/// Resolves the on-disk locations used by v0.2 stores.
///
/// All paths live under ~/Library/Application Support/NotchyPrompter/.
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
        let d = appSupportDir.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}
