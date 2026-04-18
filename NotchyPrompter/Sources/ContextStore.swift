// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import AppKit

@MainActor
final class ContextStore: ObservableObject {
    @Published private(set) var packs: [ContextPack] = []
    private let directory: URL

    init(directory: URL = Paths.contextsDir) {
        self.directory = directory
        self.packs = Self.loadAll(from: directory)
    }

    private static func loadAll(from directory: URL) -> [ContextPack] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory,
                                                     includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [ContextPack] = []
        for url in items where url.pathExtension == "md" {
            let fallback = UUID()
            guard let raw = try? String(contentsOf: url, encoding: .utf8),
                  let pack = try? ContextPack.decoded(from: raw, fallbackID: fallback)
            else { continue }
            // If the file lacked a proper id, rewrite it to persist.
            if pack.id == fallback {
                try? pack.encoded().write(to: url, atomically: true, encoding: .utf8)
            }
            result.append(pack)
        }
        return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func loadAll() -> [ContextPack] {
        let reloaded = Self.loadAll(from: directory)
        packs = reloaded
        return reloaded
    }

    func save(_ pack: ContextPack) throws {
        let url = directory.appendingPathComponent("\(pack.id.uuidString).md")
        try pack.encoded().write(to: url, atomically: true, encoding: .utf8)
        packs = Self.loadAll(from: directory)
    }

    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).md")
        try? FileManager.default.removeItem(at: url)
        packs = Self.loadAll(from: directory)
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
    }
}
