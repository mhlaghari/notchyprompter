// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Simple append-to-file logger for tracing runtime behaviour during
/// development. Writes to /tmp/notchy-debug.log so output can be tailed
/// without wrestling with macOS's unified log private-data redaction.
///
/// Intentionally cheap: single file, append-only, no rotation, no levels.
/// Remove before shipping a release build.
enum DebugLog {
    static let url = URL(fileURLWithPath: "/tmp/notchy-debug.log")
    private static let iso = ISO8601DateFormatter()
    private static let queue = DispatchQueue(label: "notchy.debuglog")

    static func write(_ line: String) {
        let stamped = "[\(iso.string(from: Date()))] \(line)\n"
        guard let data = stamped.data(using: .utf8) else { return }
        queue.async {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try? data.write(to: url)
                return
            }
            if let fh = try? FileHandle(forWritingTo: url) {
                defer { try? fh.close() }
                try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
            }
        }
    }
}
