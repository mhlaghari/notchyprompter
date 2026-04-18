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
            let migrated = migrateLegacyBuiltIns(decoded)
            if migrated != decoded {
                try? save(migrated, to: file)
            }
            return migrated
        }
        let seeded = SeedData.initialModes()
        try? Self.save(seeded, to: file)
        return seeded
    }

    /// Upgrade modes.json written by v0.2.0 (which seeded "Watching" and
    /// "Meeting" built-ins) to the current naming ("Note-taker",
    /// "Teleprompter"). Preserves UUIDs so `activeModeID` references stay
    /// valid. If the user hadn't customized the built-in (i.e. its current
    /// prompt still matches its stored defaults), also refresh the prompt
    /// to the new default. If they had customized it, keep their prompt
    /// but rename it and update the defaults record.
    private static func migrateLegacyBuiltIns(_ modes: [Mode]) -> [Mode] {
        return modes.map { m in
            guard m.isBuiltIn else { return m }

            if m.defaults?.name == SeedData.legacyNoteTakerName
                || m.name == SeedData.legacyNoteTakerName {
                return migrated(m,
                                newName: SeedData.noteTakerBuiltInName,
                                newPrompt: SeedData.noteTakerPrompt)
            }
            if m.defaults?.name == SeedData.legacyTeleprompterName
                || m.name == SeedData.legacyTeleprompterName {
                return migrated(m,
                                newName: SeedData.teleprompterBuiltInName,
                                newPrompt: SeedData.teleprompterPrompt)
            }
            return m
        }
    }

    private static func migrated(_ m: Mode, newName: String, newPrompt: String) -> Mode {
        let oldDefaults = m.defaults
        let wasPristine = oldDefaults.map { $0.name == m.name && $0.systemPrompt == m.systemPrompt } ?? true
        return Mode(
            id: m.id,
            name: newName,
            systemPrompt: wasPristine ? newPrompt : m.systemPrompt,
            attachedContextIDs: m.attachedContextIDs,
            modelOverride: m.modelOverride,
            maxTokens: m.maxTokens,
            isBuiltIn: true,
            defaults: ModeDefaults(name: newName, systemPrompt: newPrompt)
        )
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

    /// The Note-taker built-in, guaranteed to exist post-seed. Used as the
    /// default active mode when the user has no preference.
    var noteTakerBuiltIn: Mode {
        modes.first { $0.name == SeedData.noteTakerBuiltInName && $0.isBuiltIn }!
    }

    func mode(by id: UUID) -> Mode? {
        modes.first { $0.id == id }
    }
}
