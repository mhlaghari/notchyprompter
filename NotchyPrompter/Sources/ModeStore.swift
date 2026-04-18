// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum ModeStoreError: Error, LocalizedError {
    case cannotDeleteBuiltIn
    var errorDescription: String? {
        switch self {
        case .cannotDeleteBuiltIn:
            return "Built-in modes can be reset but not deleted."
        }
    }
}

@MainActor
final class ModeStore: ObservableObject {
    @Published private(set) var modes: [Mode] = []
    private let file: URL

    init(file: URL = Paths.modesFile) {
        self.file = file
        self.modes = Self.load(from: file)
    }

    private static func load(from file: URL) -> [Mode] {
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([Mode].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        let seeded = SeedData.initialModes()
        try? Self.save(seeded, to: file)
        return seeded
    }

    private static func save(_ modes: [Mode], to file: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(modes).write(to: file, options: .atomic)
    }

    func upsert(_ mode: Mode) throws {
        if let i = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[i] = mode
        } else {
            modes.append(mode)
        }
        try Self.save(modes, to: file)
    }

    func delete(id: UUID) throws {
        guard let m = modes.first(where: { $0.id == id }) else { return }
        if m.isBuiltIn { throw ModeStoreError.cannotDeleteBuiltIn }
        modes.removeAll { $0.id == id }
        try Self.save(modes, to: file)
    }

    func resetToDefaults(id: UUID) throws {
        guard let i = modes.firstIndex(where: { $0.id == id }) else { return }
        modes[i] = modes[i].resetToDefaults()
        try Self.save(modes, to: file)
    }

    @discardableResult
    func duplicate(id: UUID) throws -> Mode {
        guard let source = modes.first(where: { $0.id == id }) else {
            return modes.first!
        }
        let copy = Mode(
            id: UUID(),
            name: "\(source.name) copy",
            systemPrompt: source.systemPrompt,
            attachedContextIDs: source.attachedContextIDs,
            modelOverride: source.modelOverride,
            maxTokens: source.maxTokens,
            isBuiltIn: false,
            defaults: nil
        )
        try upsert(copy)
        return copy
    }

    /// The Watching built-in, guaranteed to exist post-seed.
    var watchingBuiltIn: Mode {
        modes.first { $0.name == SeedData.watchingBuiltInName && $0.isBuiltIn }!
    }

    func mode(by id: UUID) -> Mode? {
        modes.first { $0.id == id }
    }
}
