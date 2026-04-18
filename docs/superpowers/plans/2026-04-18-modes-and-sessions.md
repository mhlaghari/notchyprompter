# NotchyPrompter v0.2 — Modes, Context Packs, and Session Capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship NotchyPrompter v0.2 — named mode presets (selectable from the menu bar), per-mode attached markdown context packs, and per-session JSON capture with auto-summary on Stop, preserving v0.1 behaviour for existing users.

**Architecture:** Three new data stores (ModeStore, ContextStore, SessionRecorder) backed by files under `~/Library/Application Support/NotchyPrompter/`. The `LLMClient` protocol is rewritten around an `LLMRequest` value type so the pipeline can assemble system prompt + attached contexts per call. `ClaudeClient` uses multi-block prompt caching (one block per pack, up to 3, plus the system prompt = 4 cache breakpoints). The menu bar gains a Mode submenu and session-related items; Settings becomes tabbed (Backend / Modes / Contexts / About).

**Tech Stack:** Swift 5.9, SwiftUI, SwiftPM, AppKit, Combine, URLSession. No new third-party dependencies (YAML frontmatter is hand-parsed — format is trivial). A new SwiftPM test target is added for unit tests.

**Spec:** `docs/superpowers/specs/2026-04-18-modes-and-sessions-design.md`

**Execution note:** Recommended to run in a fresh git worktree (see superpowers:using-git-worktrees). Phases are independent enough to be merged incrementally if desired — Phase 1 (Foundation + Paths + Test target) should land first so later phases have test infrastructure.

---

## File structure

### New files under `NotchyPrompter/Sources/`

| File | Responsibility |
|---|---|
| `Paths.swift` | Application Support directory URLs (`modesFile`, `contextsDir`, `sessionsDir`) |
| `Mode.swift` | `Mode` and `ModeDefaults` structs |
| `ModeStore.swift` | Load/save `modes.json`; seed defaults; resolve active mode |
| `ContextPack.swift` | `ContextPack` struct + frontmatter parse/write helpers |
| `ContextStore.swift` | Load/save context pack files under `contexts/` |
| `Session.swift` | `Session`, `SessionEvent`, `SessionSummary`, `SessionMeta` |
| `SessionRecorder.swift` | In-memory event recorder; writes JSON on end; appends summaries |
| `SummaryGenerator.swift` | One-shot LLM call that turns a Session into a summary string |
| `ModesSettingsView.swift` | SwiftUI Modes tab |
| `ContextsSettingsView.swift` | SwiftUI Contexts tab |
| `SettingsTabs.swift` | TabView wrapper over Backend/Modes/Contexts/About |

### New test target under `NotchyPrompter/Tests/NotchyPrompterTests/`

| File | Covers |
|---|---|
| `ContextPackTests.swift` | frontmatter round-trip; missing-id rewrite |
| `ModeStoreTests.swift` | seed on empty disk; load/save; reset-to-default |
| `SessionRecorderTests.swift` | event ordering; JSON round-trip; same-second filename collision |
| `LLMRequestAssemblyTests.swift` | Claude multi-block system with cache_control breakpoints; overflow concat |

### Modified files under `NotchyPrompter/Sources/`

| File | Change |
|---|---|
| `Package.swift` | Add `NotchyPrompterCore` library target (test-importable) + `.testTarget` |
| `LLMClient.swift` | Introduce `LLMRequest`; change protocol signature |
| `ClaudeClient.swift` | Accept `LLMRequest`; assemble multi-block system with cache breakpoints |
| `OllamaClient.swift` | Accept `LLMRequest`; build system from mode prompt + contexts |
| `SettingsStore.swift` | Add `activeModeID`, `autoSummarizeOnStop`, `summaryPrompt` |
| `Pipeline.swift` | Build `LLMRequest` per chunk from active mode; wire `SessionRecorder`; auto-summary on `stop()` |
| `MenuBarController.swift` | Mode submenu; "Summarize Last Session…" and "Open Sessions Folder" items |
| `SettingsView.swift` | Move body into `BackendSettingsView`; wrapped by new `SettingsTabs` |
| `AppDelegate.swift` | Instantiate `ModeStore`, `ContextStore`, `SessionRecorder`; inject into `Pipeline` and `MenuBarController` |

### Phase map

```
Phase 1: Foundation            → Paths, Package.swift test target
Phase 2: Context packs         → ContextPack, ContextStore (+ tests)
Phase 3: Modes                 → Mode, ModeStore, seed data (+ tests)
Phase 4: LLM integration       → LLMRequest, protocol, Claude + Ollama (+ tests)
Phase 5: Pipeline wiring       → read active mode per chunk; no sessions yet
Phase 6: Session capture       → Session types, SessionRecorder (+ tests)
Phase 7: Summary generation    → SummaryGenerator + auto-run on Stop
Phase 8: Menu bar              → Mode submenu + session items
Phase 9: Settings UI           → TabView, Modes tab, Contexts tab
Phase 10: Manual acceptance    → end-to-end sanity pass
```

Each phase ends in a commit; the build is green after every commit.

---

## Phase 1 — Foundation

### Task 1.1: Add `Paths.swift`

**Files:**
- Create: `NotchyPrompter/Sources/Paths.swift`

- [ ] **Step 1: Create the file**

```swift
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
```

- [ ] **Step 2: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: build succeeds, no new warnings.

- [ ] **Step 3: Commit**

```bash
git add NotchyPrompter/Sources/Paths.swift
git commit -m "Add Paths helper for v0.2 on-disk stores"
```

### Task 1.2: Add SwiftPM test target

**Files:**
- Modify: `NotchyPrompter/Package.swift`
- Create: `NotchyPrompter/Tests/NotchyPrompterTests/SmokeTest.swift`

- [ ] **Step 1: Refactor `Package.swift` to expose an importable target**

Replace the whole file:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchyPrompter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchyPrompter", targets: ["NotchyPrompter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.18.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchyPrompter",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NotchyPrompterTests",
            dependencies: ["NotchyPrompter"],
            path: "Tests/NotchyPrompterTests"
        ),
    ]
)
```

- [ ] **Step 2: Create a smoke test**

```swift
// Tests/NotchyPrompterTests/SmokeTest.swift
import XCTest
@testable import NotchyPrompter

final class SmokeTest: XCTestCase {
    func testPathsResolve() {
        XCTAssertTrue(Paths.appSupportDir.path.contains("NotchyPrompter"))
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd NotchyPrompter && swift test`
Expected: 1 test passes (`testPathsResolve`).

If `swift test` complains that the executable target isn't testable, change the `@testable import NotchyPrompter` to `import NotchyPrompter` and make `Paths` methods/properties `public` — *or* switch the executable to a mixed `.executableTarget` that depends on a separate `.target` called `NotchyPrompterKit` holding all logic. For this plan we stick with `@testable import`, which works for executable targets in Swift 5.9+.

- [ ] **Step 4: Commit**

```bash
git add NotchyPrompter/Package.swift NotchyPrompter/Tests
git commit -m "Add SwiftPM test target with Paths smoke test"
```

---

## Phase 2 — Context packs

### Task 2.1: `ContextPack` struct with frontmatter parse/write

**Files:**
- Create: `NotchyPrompter/Sources/ContextPack.swift`
- Create: `NotchyPrompter/Tests/NotchyPrompterTests/ContextPackTests.swift`

- [ ] **Step 1: Write failing tests first**

```swift
// Tests/NotchyPrompterTests/ContextPackTests.swift
import XCTest
@testable import NotchyPrompter

final class ContextPackTests: XCTestCase {
    func testRoundTrip() throws {
        let id = UUID()
        let pack = ContextPack(id: id, title: "Résumé", body: "# Me\n\nHi.\n")
        let encoded = pack.encoded()
        let decoded = try ContextPack.decoded(from: encoded, fallbackID: UUID())
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.title, "Résumé")
        XCTAssertEqual(decoded.body, "# Me\n\nHi.\n")
    }

    func testMissingFrontmatterUsesFallbackID() throws {
        let raw = "# Just markdown\n\nNo frontmatter.\n"
        let fallback = UUID()
        let decoded = try ContextPack.decoded(from: raw, fallbackID: fallback)
        XCTAssertEqual(decoded.id, fallback)
        XCTAssertEqual(decoded.title, "Untitled")
        XCTAssertEqual(decoded.body, raw)
    }

    func testMalformedFrontmatterFallsBack() throws {
        let raw = "---\nnot-yaml-at-all:::\n---\nbody\n"
        let fallback = UUID()
        let decoded = try ContextPack.decoded(from: raw, fallbackID: fallback)
        XCTAssertEqual(decoded.id, fallback)
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `cd NotchyPrompter && swift test --filter ContextPackTests`
Expected: FAIL with "cannot find 'ContextPack' in scope".

- [ ] **Step 3: Implement `ContextPack`**

```swift
// Sources/ContextPack.swift
import Foundation

struct ContextPack: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var body: String

    /// Markdown with YAML frontmatter (id + title).
    func encoded() -> String {
        """
        ---
        id: \(id.uuidString)
        title: \(title.replacingOccurrences(of: "\n", with: " "))
        ---

        \(body)
        """
    }

    /// Parse a markdown file. Accepts files with or without frontmatter; when
    /// frontmatter is absent or malformed, the body is the whole file and
    /// `fallbackID` is used (callers rewrite the file to persist it).
    static func decoded(from raw: String, fallbackID: UUID) throws -> ContextPack {
        guard raw.hasPrefix("---\n") else {
            return ContextPack(id: fallbackID, title: "Untitled", body: raw)
        }
        let rest = raw.dropFirst("---\n".count)
        guard let endRange = rest.range(of: "\n---\n") else {
            return ContextPack(id: fallbackID, title: "Untitled", body: raw)
        }
        let frontmatter = rest[rest.startIndex..<endRange.lowerBound]
        let bodyAfter = rest[endRange.upperBound...]
        // Strip one leading newline if present.
        let body = bodyAfter.first == "\n"
            ? String(bodyAfter.dropFirst())
            : String(bodyAfter)

        var idStr: String?
        var title: String?
        for line in frontmatter.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: ":", maxSplits: 1,
                                   omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "id": idStr = val
            case "title": title = val
            default: continue
            }
        }
        let id = idStr.flatMap(UUID.init(uuidString:)) ?? fallbackID
        return ContextPack(id: id, title: title ?? "Untitled", body: body)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `cd NotchyPrompter && swift test --filter ContextPackTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add NotchyPrompter/Sources/ContextPack.swift NotchyPrompter/Tests/NotchyPrompterTests/ContextPackTests.swift
git commit -m "Add ContextPack with YAML-frontmatter markdown serialization"
```

### Task 2.2: `ContextStore` — load/save packs on disk

**Files:**
- Create: `NotchyPrompter/Sources/ContextStore.swift`
- Modify: `NotchyPrompter/Tests/NotchyPrompterTests/ContextPackTests.swift` (append store tests in a new class)

- [ ] **Step 1: Write failing tests first**

Append to `ContextPackTests.swift`:

```swift
final class ContextStoreTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSaveAndReload() throws {
        let store = ContextStore(directory: tmpDir)
        let pack = ContextPack(id: UUID(), title: "Notes", body: "hi")
        try store.save(pack)

        let reloaded = store.loadAll()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].id, pack.id)
        XCTAssertEqual(reloaded[0].body, "hi")
    }

    func testDropInFileWithoutFrontmatterGetsID() throws {
        let url = tmpDir.appendingPathComponent("plain.md")
        try "# hi\n".write(to: url, atomically: true, encoding: .utf8)
        let store = ContextStore(directory: tmpDir)
        let all = store.loadAll()
        XCTAssertEqual(all.count, 1)
        // File should have been rewritten with frontmatter.
        let rewritten = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(rewritten.hasPrefix("---\n"))
    }

    func testDelete() throws {
        let store = ContextStore(directory: tmpDir)
        let pack = ContextPack(id: UUID(), title: "X", body: "x")
        try store.save(pack)
        try store.delete(id: pack.id)
        XCTAssertTrue(store.loadAll().isEmpty)
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Run: `cd NotchyPrompter && swift test --filter ContextStoreTests`
Expected: FAIL with "cannot find 'ContextStore' in scope".

- [ ] **Step 3: Implement `ContextStore`**

```swift
// Sources/ContextStore.swift
import Foundation

/// File-backed store of ContextPacks, one .md per pack.
@MainActor
final class ContextStore: ObservableObject {
    @Published private(set) var packs: [ContextPack] = []
    private let directory: URL

    init(directory: URL = Paths.contextsDir) {
        self.directory = directory
        self.packs = loadAll()
    }

    func loadAll() -> [ContextPack] {
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

    func save(_ pack: ContextPack) throws {
        let url = directory.appendingPathComponent("\(pack.id.uuidString).md")
        try pack.encoded().write(to: url, atomically: true, encoding: .utf8)
        packs = loadAll()
    }

    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).md")
        try? FileManager.default.removeItem(at: url)
        packs = loadAll()
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
    }
}
```

Note: `NSWorkspace` requires `import AppKit`:

```swift
import Foundation
import AppKit
```

- [ ] **Step 4: Run tests — expect pass**

Run: `cd NotchyPrompter && swift test --filter ContextStoreTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add NotchyPrompter/Sources/ContextStore.swift NotchyPrompter/Tests
git commit -m "Add ContextStore (file-backed context pack store)"
```

---

## Phase 3 — Modes

### Task 3.1: `Mode` + `ModeDefaults`

**Files:**
- Create: `NotchyPrompter/Sources/Mode.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Mode.swift
import Foundation

struct ModeDefaults: Codable, Equatable {
    let name: String
    let systemPrompt: String
}

struct Mode: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var attachedContextIDs: [UUID]
    var modelOverride: String?
    var maxTokens: Int?
    let isBuiltIn: Bool
    let defaults: ModeDefaults?

    /// True when the user has edited a built-in away from its seeded values.
    var isDirty: Bool {
        guard let d = defaults else { return false }
        return d.name != name || d.systemPrompt != systemPrompt
    }

    /// Returns self with name + systemPrompt snapped back to defaults.
    /// Preserves user's attached contexts / overrides on purpose — those are
    /// user decisions, not part of the "factory" mode.
    func resetToDefaults() -> Mode {
        guard let d = defaults else { return self }
        var copy = self
        copy.name = d.name
        copy.systemPrompt = d.systemPrompt
        return copy
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add NotchyPrompter/Sources/Mode.swift
git commit -m "Add Mode and ModeDefaults structs"
```

### Task 3.2: `SeedData` with built-ins + example customs

**Files:**
- Create: `NotchyPrompter/Sources/SeedData.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/SeedData.swift
import Foundation

enum SeedData {
    static let watchingPrompt = """
    You are a silent meeting copilot. Give me 1-2 concise bullet points I \
    should respond with or be aware of based on what the other person just \
    said. Be extremely brief.
    """

    static let meetingPrompt = """
    You are a silent meeting copilot. Draft a concise first-person response \
    I can say out loud right now, grounded in any attached context notes. \
    Use bullets only if the other person asked a multi-part question. Be \
    extremely brief — one or two sentences at most.
    """

    static let interviewPrompt = """
    You are a silent interview copilot. Draft a concise first-person answer \
    to the interviewer's question, grounded in the attached résumé and job \
    description. If the question is behavioural, lead with STAR structure. \
    One or two sentences.
    """

    static let presentingPrompt = """
    You are a silent presentation copilot. The audience just asked a \
    question. Draft a concise first-person answer suitable for a live \
    presentation, grounded in the attached deck notes. One or two sentences.
    """

    static let summaryPrompt = """
    You are given a transcript and reply log from a meeting. Produce a \
    concise recap: what was discussed, decisions made, action items (who \
    owes what by when if stated), and open questions. Markdown.
    """

    static func initialModes() -> [Mode] {
        let watching = Mode(
            id: UUID(),
            name: "Watching",
            systemPrompt: watchingPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Watching", systemPrompt: watchingPrompt)
        )
        let meeting = Mode(
            id: UUID(),
            name: "Meeting",
            systemPrompt: meetingPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Meeting", systemPrompt: meetingPrompt)
        )
        let custom = Mode(
            id: UUID(),
            name: "Custom",
            systemPrompt: "",
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: true,
            defaults: ModeDefaults(name: "Custom", systemPrompt: "")
        )
        let interview = Mode(
            id: UUID(),
            name: "Interview",
            systemPrompt: interviewPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: false,
            defaults: nil
        )
        let presenting = Mode(
            id: UUID(),
            name: "Presenting",
            systemPrompt: presentingPrompt,
            attachedContextIDs: [],
            modelOverride: nil,
            maxTokens: nil,
            isBuiltIn: false,
            defaults: nil
        )
        return [watching, meeting, custom, interview, presenting]
    }

    /// ID used by callers that want to look up the Watching built-in by name
    /// for initial `activeModeID`. We re-derive it at runtime from ModeStore
    /// rather than hardcoding, since the seeded UUIDs are fresh per install.
    static let watchingBuiltInName = "Watching"
}
```

- [ ] **Step 2: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add NotchyPrompter/Sources/SeedData.swift
git commit -m "Add SeedData with built-in + seeded-custom modes"
```

### Task 3.3: `ModeStore`

**Files:**
- Create: `NotchyPrompter/Sources/ModeStore.swift`
- Create: `NotchyPrompter/Tests/NotchyPrompterTests/ModeStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/NotchyPrompterTests/ModeStoreTests.swift
import XCTest
@testable import NotchyPrompter

final class ModeStoreTests: XCTestCase {
    private var tmpFile: URL!

    override func setUpWithError() throws {
        tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModeStore-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpFile)
    }

    func testSeedsWhenMissing() throws {
        let store = ModeStore(file: tmpFile)
        XCTAssertEqual(store.modes.count, 5)
        XCTAssertTrue(store.modes.contains { $0.name == "Watching" && $0.isBuiltIn })
        XCTAssertTrue(store.modes.contains { $0.name == "Interview" && !$0.isBuiltIn })
    }

    func testSaveAndReload() throws {
        let store = ModeStore(file: tmpFile)
        var m = store.modes.first { $0.name == "Meeting" }!
        m.systemPrompt = "overridden"
        try store.upsert(m)

        let store2 = ModeStore(file: tmpFile)
        let reloaded = store2.modes.first { $0.name == "Meeting" }!
        XCTAssertEqual(reloaded.systemPrompt, "overridden")
        XCTAssertTrue(reloaded.isDirty)
    }

    func testResetToDefault() throws {
        let store = ModeStore(file: tmpFile)
        var m = store.modes.first { $0.name == "Meeting" }!
        let originalPrompt = m.systemPrompt
        m.systemPrompt = "something else"
        try store.upsert(m)
        try store.resetToDefaults(id: m.id)
        let restored = store.modes.first { $0.name == "Meeting" }!
        XCTAssertEqual(restored.systemPrompt, originalPrompt)
    }

    func testDeleteBuiltInIsRejected() throws {
        let store = ModeStore(file: tmpFile)
        let watching = store.modes.first { $0.name == "Watching" }!
        XCTAssertThrowsError(try store.delete(id: watching.id))
    }

    func testDeleteCustom() throws {
        let store = ModeStore(file: tmpFile)
        let interview = store.modes.first { $0.name == "Interview" }!
        try store.delete(id: interview.id)
        XCTAssertNil(store.modes.first { $0.id == interview.id })
    }
}
```

- [ ] **Step 2: Run — expect failure**

Run: `cd NotchyPrompter && swift test --filter ModeStoreTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ModeStore`**

```swift
// Sources/ModeStore.swift
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
        _ = try? save(seeded, to: file)
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
```

- [ ] **Step 4: Run — expect pass**

Run: `cd NotchyPrompter && swift test --filter ModeStoreTests`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add NotchyPrompter/Sources/ModeStore.swift NotchyPrompter/Tests
git commit -m "Add ModeStore with seed, CRUD, reset, duplicate"
```

### Task 3.4: Extend `SettingsStore` with v0.2 keys

**Files:**
- Modify: `NotchyPrompter/Sources/SettingsStore.swift`

- [ ] **Step 1: Add properties**

Inside `SettingsStore`, after `autoStartOnLaunch`:

```swift
    @AppStorage("activeModeID") var activeModeIDString: String = ""
    @AppStorage("autoSummarizeOnStop") var autoSummarizeOnStop: Bool = true
    @AppStorage("summaryPrompt") var summaryPrompt: String = SeedData.summaryPrompt
```

Add a helper:

```swift
    var activeModeID: UUID? {
        get { UUID(uuidString: activeModeIDString) }
        set { activeModeIDString = newValue?.uuidString ?? "" }
    }
```

- [ ] **Step 2: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add NotchyPrompter/Sources/SettingsStore.swift
git commit -m "Extend SettingsStore with v0.2 keys (active mode, summary)"
```

---

## Phase 4 — LLM integration

### Task 4.1: Introduce `LLMRequest` and change protocol

**Files:**
- Modify: `NotchyPrompter/Sources/LLMClient.swift`

- [ ] **Step 1: Replace the file contents**

```swift
// Sources/LLMClient.swift
import Foundation

enum LLMBackend: String, CaseIterable, Identifiable, Codable {
    case claude
    case ollama
    var id: String { rawValue }
    var display: String { self == .claude ? "Claude" : "Ollama (local)" }
}

struct ChatTurn: Codable, Equatable {
    let role: String
    let content: String
}

/// What the pipeline hands to an LLMClient on each user chunk.
struct LLMRequest {
    let chunk: String
    let history: [ChatTurn]
    let systemPrompt: String
    let attachedContexts: [ContextPack]
    let modelOverride: String?
    let maxTokensOverride: Int?
}

func userMessage(for chunk: String) -> String {
    "The other person just said: '\(chunk.trimmingCharacters(in: .whitespacesAndNewlines))'"
}

protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}
```

Note: the v0.1 `systemPrompt` constant is deleted — its text now lives in
`SeedData.watchingPrompt` and flows through `LLMRequest.systemPrompt`.

- [ ] **Step 2: Build — expect errors**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: FAIL with errors in `ClaudeClient.swift`, `OllamaClient.swift`, `Pipeline.swift` — the protocol changed.

- [ ] **Step 3: Commit the protocol change alone so the failing state is tracked**

Skip — do not commit yet. The next tasks fix the callers.

### Task 4.2: Update `ClaudeClient` for multi-block system + cache breakpoints

**Files:**
- Modify: `NotchyPrompter/Sources/ClaudeClient.swift`
- Create: `NotchyPrompter/Tests/NotchyPrompterTests/LLMRequestAssemblyTests.swift`

- [ ] **Step 1: Write failing tests (assembly-only — does not hit network)**

Expose a pure helper on ClaudeClient for test. Add the test first:

```swift
// Tests/NotchyPrompterTests/LLMRequestAssemblyTests.swift
import XCTest
@testable import NotchyPrompter

final class LLMRequestAssemblyTests: XCTestCase {
    func testSystemBlocksWithNoContexts() {
        let req = LLMRequest(
            chunk: "hi",
            history: [],
            systemPrompt: "SYS",
            attachedContexts: [],
            modelOverride: nil,
            maxTokensOverride: nil
        )
        let blocks = ClaudeClient.systemBlocks(for: req)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["text"] as? String, "SYS")
        let cc = blocks[0]["cache_control"] as? [String: String]
        XCTAssertEqual(cc?["type"], "ephemeral")
    }

    func testTwoContextsGetOwnBlocks() {
        let c1 = ContextPack(id: UUID(), title: "A", body: "AAA")
        let c2 = ContextPack(id: UUID(), title: "B", body: "BBB")
        let req = LLMRequest(
            chunk: "hi", history: [], systemPrompt: "SYS",
            attachedContexts: [c1, c2],
            modelOverride: nil, maxTokensOverride: nil
        )
        let blocks = ClaudeClient.systemBlocks(for: req)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0]["text"] as? String, "SYS")
        XCTAssertEqual(blocks[1]["text"] as? String, "AAA")
        XCTAssertEqual(blocks[2]["text"] as? String, "BBB")
    }

    func testOverflowConcatsIntoFinalBlock() {
        let ctx = (0..<5).map { i in
            ContextPack(id: UUID(), title: "C\(i)", body: "BODY\(i)")
        }
        let req = LLMRequest(
            chunk: "hi", history: [], systemPrompt: "SYS",
            attachedContexts: ctx,
            modelOverride: nil, maxTokensOverride: nil
        )
        let blocks = ClaudeClient.systemBlocks(for: req)
        // 1 system + 2 own blocks + 1 concat'd tail block = 4 (cap of 4)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0]["text"] as? String, "SYS")
        XCTAssertEqual(blocks[1]["text"] as? String, "BODY0")
        XCTAssertEqual(blocks[2]["text"] as? String, "BODY1")
        let tail = blocks[3]["text"] as? String ?? ""
        XCTAssertTrue(tail.contains("BODY2"))
        XCTAssertTrue(tail.contains("BODY3"))
        XCTAssertTrue(tail.contains("BODY4"))
        XCTAssertTrue(tail.contains("---"))
    }
}
```

- [ ] **Step 2: Run — expect failure**

Run: `cd NotchyPrompter && swift test --filter LLMRequestAssemblyTests`
Expected: FAIL ("cannot find 'systemBlocks'" or build error in ClaudeClient).

- [ ] **Step 3: Replace `ClaudeClient` contents**

```swift
// Sources/ClaudeClient.swift
import Foundation

/// Minimal Anthropic Messages API streaming client via URLSession + SSE.
/// Uses prompt caching on the system prompt plus up to 3 attached context
/// blocks (Anthropic caps cache_control at 4 breakpoints per request).
struct ClaudeClient: LLMClient {
    let apiKey: String
    let model: String             // default model; overridden per-request if set
    let maxTokens: Int            // default; overridden per-request if set
    let apiVersion: String = "2023-06-01"
    private static let maxCacheBreakpoints = 4  // total across system blocks

    /// Builds the `system` array payload. Exposed for unit tests.
    static func systemBlocks(for request: LLMRequest) -> [[String: Any]] {
        let systemBlock: [String: Any] = [
            "type": "text",
            "text": request.systemPrompt,
            "cache_control": ["type": "ephemeral"],
        ]
        // Remaining breakpoints after the system block.
        let budget = maxCacheBreakpoints - 1
        let ctx = request.attachedContexts
        if ctx.count <= budget {
            return [systemBlock] + ctx.map {
                [
                    "type": "text",
                    "text": $0.body,
                    "cache_control": ["type": "ephemeral"],
                ]
            }
        }
        // First (budget - 1) get their own blocks; the rest are concatenated
        // into the final block (which still gets a cache breakpoint).
        var blocks: [[String: Any]] = [systemBlock]
        let solo = ctx.prefix(budget - 1)
        for c in solo {
            blocks.append([
                "type": "text",
                "text": c.body,
                "cache_control": ["type": "ephemeral"],
            ])
        }
        let tail = ctx.dropFirst(budget - 1)
            .map { $0.body }
            .joined(separator: "\n\n---\n\n")
        blocks.append([
            "type": "text",
            "text": tail,
            "cache_control": ["type": "ephemeral"],
        ])
        return blocks
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    req.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")

                    let body: [String: Any] = [
                        "model": request.modelOverride ?? model,
                        "max_tokens": request.maxTokensOverride ?? maxTokens,
                        "stream": true,
                        "system": Self.systemBlocks(for: request),
                        "messages": (request.history.map { ["role": $0.role, "content": $0.content] })
                            + [["role": "user", "content": userMessage(for: request.chunk)]],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw NSError(domain: "Claude", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "no HTTP response"])
                    }
                    guard 200..<300 ~= http.statusCode else {
                        var errBody = ""
                        for try await line in bytes.lines { errBody += line + "\n" }
                        throw NSError(domain: "Claude", code: http.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey: errBody])
                    }

                    var currentEvent: String? = nil
                    for try await line in bytes.lines {
                        if line.isEmpty { currentEvent = nil; continue }
                        if line.hasPrefix("event:") {
                            currentEvent = String(line.dropFirst("event:".count))
                                .trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        if line.hasPrefix("data:") {
                            let payload = String(line.dropFirst("data:".count))
                                .trimmingCharacters(in: .whitespaces)
                            guard let data = payload.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data)
                                        as? [String: Any]
                            else { continue }

                            if currentEvent == "content_block_delta",
                               let delta = obj["delta"] as? [String: Any],
                               let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(text)
                            }
                            if currentEvent == "message_stop" { break }
                            if currentEvent == "error",
                               let errObj = obj["error"] as? [String: Any],
                               let msg = errObj["message"] as? String {
                                throw NSError(domain: "Claude", code: -2,
                                              userInfo: [NSLocalizedDescriptionKey: msg])
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run — expect tests pass**

Run: `cd NotchyPrompter && swift test --filter LLMRequestAssemblyTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit (after Pipeline + Ollama fixes land — continue to 4.3)**

Skip — build still broken until 4.3 lands.

### Task 4.3: Update `OllamaClient`

**Files:**
- Modify: `NotchyPrompter/Sources/OllamaClient.swift`

- [ ] **Step 1: Replace the file**

```swift
// Sources/OllamaClient.swift
import Foundation

/// Ollama chat streaming via newline-delimited JSON over HTTP.
/// No prompt cache; system prompt is rebuilt from scratch per request.
struct OllamaClient: LLMClient {
    let baseURL: URL
    let model: String
    let maxTokens: Int

    private static func systemString(for request: LLMRequest) -> String {
        var parts: [String] = [request.systemPrompt]
        for c in request.attachedContexts {
            parts.append("---\n\n\(c.body)")
        }
        return parts.joined(separator: "\n\n")
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "content-type")

                    var messages: [[String: String]] = [
                        ["role": "system", "content": Self.systemString(for: request)]
                    ]
                    messages.append(contentsOf: request.history.map {
                        ["role": $0.role, "content": $0.content]
                    })
                    messages.append(["role": "user", "content": userMessage(for: request.chunk)])

                    let body: [String: Any] = [
                        "model": request.modelOverride ?? model,
                        "messages": messages,
                        "stream": true,
                        "think": false,
                        "options": ["num_predict": request.maxTokensOverride ?? maxTokens],
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw NSError(domain: "Ollama", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "no HTTP response"])
                    }
                    guard 200..<300 ~= http.statusCode else {
                        throw NSError(domain: "Ollama", code: http.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey:
                                                    "Ollama returned HTTP \(http.statusCode). Is `ollama serve` running?"])
                    }

                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data)
                                    as? [String: Any] else { continue }
                        if let done = obj["done"] as? Bool, done { break }
                        if let msg = obj["message"] as? [String: Any],
                           let text = msg["content"] as? String, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build (Pipeline still broken)**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: FAIL — Pipeline still calls old signature. Next task fixes it.

---

## Phase 5 — Pipeline wiring

### Task 5.1: Wire `ModeStore` + `ContextStore` into `Pipeline`

**Files:**
- Modify: `NotchyPrompter/Sources/Pipeline.swift`

- [ ] **Step 1: Update `Pipeline` to take stores in the init**

Replace:

```swift
init(store: SettingsStore, vm: OverlayViewModel) {
    self.store = store
    self.vm = vm
}
```

with:

```swift
private let modeStore: ModeStore
private let contextStore: ContextStore

init(store: SettingsStore,
     vm: OverlayViewModel,
     modeStore: ModeStore,
     contextStore: ContextStore) {
    self.store = store
    self.vm = vm
    self.modeStore = modeStore
    self.contextStore = contextStore
}
```

- [ ] **Step 2: Update `handleLLM` to build `LLMRequest` from active mode**

Replace the `handleLLM(chunk:client:)` body:

```swift
private func handleLLM(chunk: String, client: LLMClient) async {
    // Resolve active mode fresh each call so mid-session mode switches take
    // effect on the very next chunk.
    let activeID = store.activeModeID ?? modeStore.watchingBuiltIn.id
    let mode = modeStore.mode(by: activeID) ?? modeStore.watchingBuiltIn

    let attached = mode.attachedContextIDs.compactMap { id in
        contextStore.packs.first { $0.id == id }
    }

    let request = LLMRequest(
        chunk: chunk,
        history: history,
        systemPrompt: mode.systemPrompt,
        attachedContexts: attached,
        modelOverride: mode.modelOverride,
        maxTokensOverride: mode.maxTokens
    )

    NSLog("llm: calling %@ mode=%@ contexts=%d",
          String(describing: type(of: client)), mode.name, attached.count)
    vm.clear()
    vm.displayText = ""
    var acc = ""
    var deltaCount = 0
    do {
        for try await delta in client.stream(request) {
            if Task.isCancelled { return }
            deltaCount += 1
            acc += delta
            vm.setResponse(acc)
        }
        NSLog("llm: stream ended, %d deltas, %d total chars", deltaCount, acc.count)
    } catch {
        NSLog("llm error: \(error.localizedDescription)")
        vm.setStatus("LLM error: \(error.localizedDescription)")
        return
    }
    let reply = acc.trimmingCharacters(in: .whitespacesAndNewlines)
    if !reply.isEmpty {
        history.append(ChatTurn(role: "user", content: userMessage(for: chunk)))
        history.append(ChatTurn(role: "assistant", content: reply))
        let keep = store.contextPairs * 2
        if history.count > keep { history.removeFirst(history.count - keep) }
    }
}
```

- [ ] **Step 3: Update `AppDelegate` to pass the new stores**

In `AppDelegate.swift`, add properties and wire them:

```swift
private let modeStore = ModeStore()
private let contextStore = ContextStore()
```

Change the pipeline construction:

```swift
let p = Pipeline(store: store, vm: vm,
                 modeStore: modeStore, contextStore: contextStore)
self.pipeline = p
```

In the same file, initialize `activeModeID` if unset (migration path):

Inside `applicationDidFinishLaunching`, right after `let p = Pipeline(...)`:

```swift
if store.activeModeID == nil {
    store.activeModeID = modeStore.watchingBuiltIn.id
}
```

- [ ] **Step 4: Build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: build succeeds.

- [ ] **Step 5: Run all tests**

Run: `cd NotchyPrompter && swift test`
Expected: all tests pass (context/mode/assembly + smoke).

- [ ] **Step 6: Commit (Phase 2 + 3 + 4 + 5 landed together)**

```bash
git add NotchyPrompter/Sources NotchyPrompter/Tests
git commit -m "Wire ModeStore + ContextStore through LLMRequest and Pipeline"
```

---

## Phase 6 — Session capture

### Task 6.1: `Session` + `SessionEvent` + `SessionMeta` value types

**Files:**
- Create: `NotchyPrompter/Sources/Session.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/Session.swift
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
```

- [ ] **Step 2: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add NotchyPrompter/Sources/Session.swift
git commit -m "Add Session value types"
```

### Task 6.2: `SessionRecorder`

**Files:**
- Create: `NotchyPrompter/Sources/SessionRecorder.swift`
- Create: `NotchyPrompter/Tests/NotchyPrompterTests/SessionRecorderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/NotchyPrompterTests/SessionRecorderTests.swift
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

        let reloaded = try JSONDecoder().decode(Session.self,
                                                from: Data(contentsOf: onDisk))
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
```

- [ ] **Step 2: Run — expect failure**

Run: `cd NotchyPrompter && swift test --filter SessionRecorderTests`
Expected: FAIL.

- [ ] **Step 3: Implement `SessionRecorder`**

```swift
// Sources/SessionRecorder.swift
import Foundation

@MainActor
final class SessionRecorder {
    typealias Clock = () -> Date

    private let directory: URL
    private let clock: Clock
    private var current: Session?

    init(directory: URL = Paths.sessionsDir, clock: @escaping Clock = Date.init) {
        self.directory = directory
        self.clock = clock
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
    }

    var hasActiveSession: Bool { current != nil }

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
    }

    func recordTranscript(_ text: String, durationMs: Int) {
        guard var s = current else { return }
        s.events.append(SessionEvent(
            t: clock(), kind: .transcript,
            text: text, durationMs: durationMs,
            modeId: nil, modeName: nil
        ))
        current = s
    }

    func recordReply(_ text: String) {
        guard var s = current else { return }
        s.events.append(SessionEvent(
            t: clock(), kind: .reply,
            text: text, durationMs: nil,
            modeId: nil, modeName: nil
        ))
        current = s
    }

    func recordModeChange(_ mode: Mode) {
        guard var s = current else { return }
        s.events.append(SessionEvent(
            t: clock(), kind: .mode,
            text: nil, durationMs: nil,
            modeId: mode.id.uuidString, modeName: mode.name
        ))
        current = s
    }

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
        var s = try JSONDecoder.session.decode(Session.self, from: data)
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
                  let s = try? JSONDecoder.session.decode(Session.self, from: data)
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
        let enc = JSONEncoder.session
        try enc.encode(session).write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var session: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var session: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd NotchyPrompter && swift test --filter SessionRecorderTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add NotchyPrompter/Sources/SessionRecorder.swift NotchyPrompter/Tests
git commit -m "Add SessionRecorder with JSON persistence and collision suffix"
```

### Task 6.3: Wire `SessionRecorder` into `Pipeline`

**Files:**
- Modify: `NotchyPrompter/Sources/Pipeline.swift`
- Modify: `NotchyPrompter/Sources/AppDelegate.swift`

- [ ] **Step 1: Inject recorder into Pipeline**

Add a property:

```swift
private let sessionRecorder: SessionRecorder
```

Extend `init` to accept it:

```swift
init(store: SettingsStore,
     vm: OverlayViewModel,
     modeStore: ModeStore,
     contextStore: ContextStore,
     sessionRecorder: SessionRecorder) {
    self.store = store
    self.vm = vm
    self.modeStore = modeStore
    self.contextStore = contextStore
    self.sessionRecorder = sessionRecorder
}
```

In `start()`, after `vm.setStatus("starting…")`:

```swift
let activeID = store.activeModeID ?? modeStore.watchingBuiltIn.id
let initial = modeStore.mode(by: activeID) ?? modeStore.watchingBuiltIn
sessionRecorder.startSession(initialMode: initial)
```

In `handleLLM`, right after `let trimmed = text.trimmingCharacters(...)` (inside the transcribe path in `run`), record the transcript event BEFORE calling `handleLLM`:

Actually in `run(capture:transcriber:client:)`, inside the `for await chunk` loop, right after `let text = try await transcriber.transcribe(chunk)` and the `trimmed` line:

```swift
sessionRecorder.recordTranscript(trimmed,
    durationMs: Int((Double(chunk.count) / 16000.0) * 1000.0))
```

In `handleLLM`, after the final reply is appended to history, record the reply:

```swift
sessionRecorder.recordReply(reply)
```

(Only when `!reply.isEmpty`.)

In `stop()`, after `vm.isRunning = false`, persist the session:

```swift
Task { [sessionRecorder] in
    do {
        let session = try sessionRecorder.endSession()
        // Auto-summary is handled in Phase 7; leave a hook here:
        await self.postSessionHook?(session)
    } catch {
        NSLog("session end: %@", error.localizedDescription)
    }
}
```

Add a property for the hook:

```swift
var postSessionHook: ((Session) async -> Void)?
```

- [ ] **Step 2: Wire in `AppDelegate`**

Add:

```swift
private let sessionRecorder = SessionRecorder()
```

Update pipeline construction:

```swift
let p = Pipeline(store: store, vm: vm,
                 modeStore: modeStore, contextStore: contextStore,
                 sessionRecorder: sessionRecorder)
self.pipeline = p
```

- [ ] **Step 3: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: builds.

- [ ] **Step 4: Run tests**

Run: `cd NotchyPrompter && swift test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add NotchyPrompter/Sources
git commit -m "Record transcript and reply events during pipeline; write on stop"
```

---

## Phase 7 — Summary generation

### Task 7.1: `SummaryGenerator`

**Files:**
- Create: `NotchyPrompter/Sources/SummaryGenerator.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/SummaryGenerator.swift
import Foundation

/// One-shot non-streaming LLM call that turns a Session's transcript/reply
/// log into a recap. Reuses the user's configured LLMClient so they don't
/// need a separate key/backend for summaries.
@MainActor
struct SummaryGenerator {
    let client: LLMClient

    /// Renders the session's events as a transcript log suitable for the
    /// summary prompt.
    static func transcriptText(for session: Session) -> String {
        var out: [String] = []
        let df = ISO8601DateFormatter()
        for e in session.events {
            switch e.kind {
            case .mode:
                out.append("[mode: \(e.modeName ?? "?")]")
            case .transcript:
                out.append("[\(df.string(from: e.t))] them: \(e.text ?? "")")
            case .reply:
                out.append("[\(df.string(from: e.t))] me:   \(e.text ?? "")")
            }
        }
        return out.joined(separator: "\n")
    }

    /// Runs a non-streaming summary. Returns the concatenated reply text.
    func run(prompt: String, session: Session) async throws -> String {
        let transcript = Self.transcriptText(for: session)
        let request = LLMRequest(
            chunk: transcript,
            history: [],
            systemPrompt: prompt,
            attachedContexts: [],
            modelOverride: nil,
            maxTokensOverride: 800
        )
        var acc = ""
        for try await delta in client.stream(request) {
            acc += delta
        }
        return acc.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 2: Hook into `Pipeline.stop()`**

In `AppDelegate`, where the pipeline is constructed, set the hook:

```swift
p.postSessionHook = { [store, sessionRecorder, weak self] session in
    guard store.autoSummarizeOnStop else { return }
    guard let client = store.buildClient() else { return }
    let gen = await SummaryGenerator(client: client)
    do {
        let text = try await gen.run(prompt: store.summaryPrompt, session: session)
        try await MainActor.run {
            try sessionRecorder.appendSummary(sessionID: session.id,
                                              prompt: store.summaryPrompt,
                                              text: text)
        }
        _ = self  // suppress unused warning
    } catch {
        NSLog("summary error: \(error.localizedDescription)")
    }
}
```

(Adjust await/async boundaries as the compiler guides.)

- [ ] **Step 3: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: builds.

- [ ] **Step 4: Commit**

```bash
git add NotchyPrompter/Sources
git commit -m "Auto-summarize sessions on Stop when enabled"
```

---

## Phase 8 — Menu bar

### Task 8.1: Mode submenu + session actions

**Files:**
- Modify: `NotchyPrompter/Sources/MenuBarController.swift`

- [ ] **Step 1: Replace the file**

```swift
// Sources/MenuBarController.swift
import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let onSettings: () -> Void
    private let onToggle: () -> Void
    private let onQuit: () -> Void
    private let onSelectMode: (UUID) -> Void
    private let onSummarizeLast: () -> Void
    private let onOpenSessionsFolder: () -> Void
    private let onEditModes: () -> Void
    private weak var vm: OverlayViewModel?
    private let modeStore: ModeStore
    private let settingsStore: SettingsStore
    private let sessionRecorder: SessionRecorder

    init(vm: OverlayViewModel,
         modeStore: ModeStore,
         settingsStore: SettingsStore,
         sessionRecorder: SessionRecorder,
         onSettings: @escaping () -> Void,
         onToggle: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onSelectMode: @escaping (UUID) -> Void,
         onSummarizeLast: @escaping () -> Void,
         onOpenSessionsFolder: @escaping () -> Void,
         onEditModes: @escaping () -> Void) {
        self.vm = vm
        self.modeStore = modeStore
        self.settingsStore = settingsStore
        self.sessionRecorder = sessionRecorder
        self.onSettings = onSettings
        self.onToggle = onToggle
        self.onQuit = onQuit
        self.onSelectMode = onSelectMode
        self.onSummarizeLast = onSummarizeLast
        self.onOpenSessionsFolder = onOpenSessionsFolder
        self.onEditModes = onEditModes
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform.circle",
                                   accessibilityDescription: "NotchyPrompter")
            button.image?.isTemplate = true
        }
        rebuildMenu(running: false)
    }

    func rebuildMenu(running: Bool) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggle = NSMenuItem(title: running ? "Stop Listening" : "Start Listening",
                                action: #selector(toggleSel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Mode submenu
        let activeID = settingsStore.activeModeID
        let activeName = modeStore.modes.first(where: { $0.id == activeID })?.name ?? "?"
        let modeItem = NSMenuItem(title: "Mode: \(activeName)",
                                  action: nil, keyEquivalent: "")
        let modeSub = NSMenu()
        let builtIns = modeStore.modes.filter { $0.isBuiltIn }
        let customs = modeStore.modes.filter { !$0.isBuiltIn }

        for m in builtIns {
            modeSub.addItem(modeMenuItem(m, activeID: activeID))
        }
        if !customs.isEmpty {
            modeSub.addItem(.separator())
            for m in customs {
                modeSub.addItem(modeMenuItem(m, activeID: activeID))
            }
        }
        modeSub.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Modes…", action: #selector(editModesSel), keyEquivalent: "")
        edit.target = self
        modeSub.addItem(edit)
        modeItem.submenu = modeSub
        menu.addItem(modeItem)

        menu.addItem(.separator())

        let summarize = NSMenuItem(title: "Summarize Last Session…",
                                   action: #selector(summarizeSel), keyEquivalent: "")
        summarize.target = self
        summarize.isEnabled = !sessionRecorder.listSessions().isEmpty
        menu.addItem(summarize)

        let openFolder = NSMenuItem(title: "Open Sessions Folder",
                                    action: #selector(openFolderSel), keyEquivalent: "")
        openFolder.target = self
        menu.addItem(openFolder)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(settingsSel), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit NotchyPrompter",
                              action: #selector(quitSel), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    private func modeMenuItem(_ mode: Mode, activeID: UUID?) -> NSMenuItem {
        let i = NSMenuItem(title: mode.name,
                           action: #selector(selectModeSel(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = mode.id.uuidString
        i.state = (mode.id == activeID) ? .on : .off
        return i
    }

    @objc private func toggleSel() { onToggle() }
    @objc private func settingsSel() { onSettings() }
    @objc private func quitSel() { onQuit() }
    @objc private func summarizeSel() { onSummarizeLast() }
    @objc private func openFolderSel() { onOpenSessionsFolder() }
    @objc private func editModesSel() { onEditModes() }
    @objc private func selectModeSel(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String,
              let id = UUID(uuidString: s) else { return }
        onSelectMode(id)
    }
}
```

- [ ] **Step 2: Update `AppDelegate` to pass new dependencies and implement handlers**

Add these helpers and change the `MenuBarController` construction:

```swift
let mb = MenuBarController(
    vm: vm,
    modeStore: modeStore,
    settingsStore: store,
    sessionRecorder: sessionRecorder,
    onSettings: { [weak self] in self?.openSettings() },
    onToggle: { [weak self] in self?.togglePipeline() },
    onQuit: { NSApp.terminate(nil) },
    onSelectMode: { [weak self] id in self?.selectMode(id: id) },
    onSummarizeLast: { [weak self] in self?.summarizeLast() },
    onOpenSessionsFolder: {
        NSWorkspace.shared.selectFile(nil,
                                      inFileViewerRootedAtPath: Paths.sessionsDir.path)
    },
    onEditModes: { [weak self] in self?.openSettingsToModesTab() }
)
self.menuBar = mb
```

Rebuild menu whenever modes change or a new session is recorded:

```swift
modeStore.$modes.sink { [weak self] _ in
    self?.menuBar?.rebuildMenu(running: self?.vm.isRunning ?? false)
}.store(in: &cancellables)
```

Add methods:

```swift
private func selectMode(id: UUID) {
    store.activeModeID = id
    if vm.isRunning, let mode = modeStore.mode(by: id) {
        Task { @MainActor in
            // Reach into the pipeline's recorder via a public hook; see Task 8.2.
            self.pipeline?.recordModeChangeIfRunning(mode)
        }
    }
    menuBar?.rebuildMenu(running: vm.isRunning)
}

private func summarizeLast() {
    guard let latest = sessionRecorder.listSessions().first else { return }
    // Minimal v0.2 UX: open a small window showing the last summary.
    // If none exists, run a fresh one.
    Task { @MainActor in
        do {
            let data = try Data(contentsOf: latest.fileURL)
            let s = try JSONDecoder.iso8601().decode(Session.self, from: data)
            let summary = s.summaries.last?.text
            if let summary {
                showSummaryWindow(text: summary, sessionID: s.id)
            } else if let client = store.buildClient() {
                let gen = SummaryGenerator(client: client)
                let text = try await gen.run(prompt: store.summaryPrompt, session: s)
                try sessionRecorder.appendSummary(sessionID: s.id,
                                                  prompt: store.summaryPrompt,
                                                  text: text)
                showSummaryWindow(text: text, sessionID: s.id)
            }
        } catch {
            NSLog("summarizeLast error: \(error.localizedDescription)")
        }
    }
}

private var summaryWC: NSWindowController?
private func showSummaryWindow(text: String, sessionID: String) {
    let scroll = NSScrollView()
    let tv = NSTextView()
    tv.isEditable = false
    tv.string = text
    scroll.documentView = tv
    scroll.hasVerticalScroller = true
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                       styleMask: [.titled, .closable, .miniaturizable, .resizable],
                       backing: .buffered, defer: false)
    win.title = "Summary — \(sessionID)"
    win.contentView = scroll
    win.center()
    let wc = NSWindowController(window: win)
    summaryWC = wc
    NSApp.activate(ignoringOtherApps: true)
    wc.showWindow(nil)
}

private func openSettingsToModesTab() {
    openSettings()
    // Phase 9's SettingsTabs holds a selection binding we can poke.
    NotificationCenter.default.post(name: .init("OpenModesTab"), object: nil)
}
```

Add a convenience decoder:

```swift
private extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}
```

- [ ] **Step 3: Add `Pipeline.recordModeChangeIfRunning`**

In `Pipeline.swift`:

```swift
func recordModeChangeIfRunning(_ mode: Mode) {
    guard vm.isRunning else { return }
    sessionRecorder.recordModeChange(mode)
}
```

- [ ] **Step 4: Build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: builds.

- [ ] **Step 5: Commit**

```bash
git add NotchyPrompter/Sources
git commit -m "Add menu-bar Mode submenu and session actions"
```

---

## Phase 9 — Settings UI

### Task 9.1: Split `SettingsView` into Backend body + TabView

**Files:**
- Modify: `NotchyPrompter/Sources/SettingsView.swift`
- Create: `NotchyPrompter/Sources/SettingsTabs.swift`

- [ ] **Step 1: Rename existing `SettingsView` to `BackendSettingsView`**

In `SettingsView.swift`, rename `struct SettingsView` → `struct BackendSettingsView`. Keep the body identical.

- [ ] **Step 2: Create `SettingsTabs.swift`**

```swift
// Sources/SettingsTabs.swift
import SwiftUI

enum SettingsTab: String, Hashable {
    case backend, modes, contexts, about
}

struct SettingsTabs: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var vm: OverlayViewModel
    @ObservedObject var modeStore: ModeStore
    @ObservedObject var contextStore: ContextStore
    @State private var tab: SettingsTab = .backend

    var onStart: () -> Void
    var onStop: () -> Void

    var body: some View {
        TabView(selection: $tab) {
            BackendSettingsView(store: store, vm: vm, onStart: onStart, onStop: onStop)
                .tabItem { Label("Backend", systemImage: "cpu") }
                .tag(SettingsTab.backend)

            ModesSettingsView(store: store, modeStore: modeStore, contextStore: contextStore)
                .tabItem { Label("Modes", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.modes)

            ContextsSettingsView(contextStore: contextStore)
                .tabItem { Label("Contexts", systemImage: "doc.text") }
                .tag(SettingsTab.contexts)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 640, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenModesTab"))) { _ in
            tab = .modes
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NotchyPrompter").font(.title2)
            Text("Silent meeting copilot.").foregroundStyle(.secondary)
            Text("Licensed under AGPL-3.0-or-later.")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 3: Update `AppDelegate.openSettings`**

Replace the Settings view construction:

```swift
let view = SettingsTabs(
    store: store,
    vm: vm,
    modeStore: modeStore,
    contextStore: contextStore,
    onStart: { [weak self] in
        self?.pipeline?.start()
        self?.store.autoStartOnLaunch = true
    },
    onStop: { [weak self] in
        self?.pipeline?.stop()
        self?.store.autoStartOnLaunch = false
    }
)
```

- [ ] **Step 4: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: FAIL — `ModesSettingsView` and `ContextsSettingsView` not yet defined. Proceed to 9.2.

### Task 9.2: Implement `ModesSettingsView`

**Files:**
- Create: `NotchyPrompter/Sources/ModesSettingsView.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/ModesSettingsView.swift
import SwiftUI

struct ModesSettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var modeStore: ModeStore
    @ObservedObject var contextStore: ContextStore
    @State private var selected: UUID?

    private var selectedMode: Binding<Mode>? {
        guard let id = selected,
              let idx = modeStore.modes.firstIndex(where: { $0.id == id })
        else { return nil }
        return Binding(
            get: { modeStore.modes[idx] },
            set: { new in try? modeStore.upsert(new) }
        )
    }

    var body: some View {
        HSplitView {
            modeList
                .frame(minWidth: 180, idealWidth: 200)
            Group {
                if let bind = selectedMode {
                    ModeEditor(mode: bind,
                               contextStore: contextStore,
                               store: store,
                               modeStore: modeStore)
                        .padding()
                } else {
                    Text("Select a mode").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selected == nil { selected = modeStore.watchingBuiltIn.id }
        }
    }

    private var modeList: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                Section("Built-in") {
                    ForEach(modeStore.modes.filter { $0.isBuiltIn }) { m in
                        row(m).tag(m.id)
                    }
                }
                Section("Custom") {
                    ForEach(modeStore.modes.filter { !$0.isBuiltIn }) { m in
                        row(m).tag(m.id)
                    }
                }
            }
            HStack {
                Button {
                    let new = Mode(
                        id: UUID(), name: "New mode", systemPrompt: "",
                        attachedContextIDs: [], modelOverride: nil,
                        maxTokens: nil, isBuiltIn: false, defaults: nil
                    )
                    try? modeStore.upsert(new)
                    selected = new.id
                } label: { Image(systemName: "plus") }

                Button {
                    guard let id = selected,
                          let copy = try? modeStore.duplicate(id: id) else { return }
                    selected = copy.id
                } label: { Image(systemName: "plus.square.on.square") }
                .disabled(selected == nil)

                Button {
                    guard let id = selected,
                          let mode = modeStore.mode(by: id),
                          !mode.isBuiltIn else { return }
                    try? modeStore.delete(id: id)
                    selected = modeStore.modes.first?.id
                } label: { Image(systemName: "trash") }
                .disabled(selected.flatMap { modeStore.mode(by: $0)?.isBuiltIn } ?? true)

                Spacer()
            }
            .buttonStyle(.bordered)
            .padding(8)
        }
    }

    private func row(_ m: Mode) -> some View {
        HStack {
            if store.activeModeID == m.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Text(m.name)
            if m.isBuiltIn {
                Image(systemName: "lock").foregroundStyle(.secondary)
            }
            if m.isDirty {
                Image(systemName: "pencil.circle").foregroundStyle(.orange)
            }
        }
    }
}

private struct ModeEditor: View {
    @Binding var mode: Mode
    @ObservedObject var contextStore: ContextStore
    @ObservedObject var store: SettingsStore
    @ObservedObject var modeStore: ModeStore

    var body: some View {
        Form {
            HStack {
                TextField("Name", text: $mode.name)
                Button("Make Active") { store.activeModeID = mode.id }
                    .disabled(store.activeModeID == mode.id)
            }

            Section("System prompt") {
                TextEditor(text: $mode.systemPrompt)
                    .frame(minHeight: 140)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Attached context packs") {
                if contextStore.packs.isEmpty {
                    Text("No context packs yet. Add one in the Contexts tab.")
                        .foregroundStyle(.secondary)
                }
                ForEach(contextStore.packs) { pack in
                    Toggle(pack.title, isOn: binding(for: pack.id))
                }
                if mode.attachedContextIDs.count > 3 {
                    Text("⚠︎ Up to 3 contexts are cached individually. Additional contexts are concatenated into a single cached block.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Overrides (optional)") {
                TextField("Model override (blank = global)",
                          text: Binding(
                            get: { mode.modelOverride ?? "" },
                            set: { mode.modelOverride = $0.isEmpty ? nil : $0 }
                          ))
                Stepper("Max tokens: \(mode.maxTokens.map(String.init) ?? "global")",
                        value: Binding(
                            get: { mode.maxTokens ?? 0 },
                            set: { mode.maxTokens = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...800, step: 20)
            }

            if mode.isBuiltIn {
                Section {
                    Button("Reset to Default") {
                        try? modeStore.resetToDefaults(id: mode.id)
                    }
                    .disabled(!mode.isDirty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { mode.attachedContextIDs.contains(id) },
            set: { on in
                if on {
                    if !mode.attachedContextIDs.contains(id) {
                        mode.attachedContextIDs.append(id)
                    }
                } else {
                    mode.attachedContextIDs.removeAll { $0 == id }
                }
            }
        )
    }
}
```

- [ ] **Step 2: Verify build (ContextsSettingsView still missing)**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: FAIL — `ContextsSettingsView` not defined.

### Task 9.3: Implement `ContextsSettingsView`

**Files:**
- Create: `NotchyPrompter/Sources/ContextsSettingsView.swift`

- [ ] **Step 1: Create the file**

```swift
// Sources/ContextsSettingsView.swift
import SwiftUI

struct ContextsSettingsView: View {
    @ObservedObject var contextStore: ContextStore
    @State private var selected: UUID?

    private var selectedPack: Binding<ContextPack>? {
        guard let id = selected,
              let idx = contextStore.packs.firstIndex(where: { $0.id == id })
        else { return nil }
        return Binding(
            get: { contextStore.packs[idx] },
            set: { new in try? contextStore.save(new) }
        )
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(contextStore.packs) { p in
                        Text(p.title).tag(p.id)
                    }
                }
                HStack {
                    Button {
                        let new = ContextPack(id: UUID(),
                                              title: "New context",
                                              body: "")
                        try? contextStore.save(new)
                        selected = new.id
                    } label: { Image(systemName: "plus") }

                    Button {
                        guard let id = selected else { return }
                        try? contextStore.delete(id: id)
                        selected = contextStore.packs.first?.id
                    } label: { Image(systemName: "trash") }
                    .disabled(selected == nil)

                    Spacer()

                    Button("Reveal") { contextStore.revealInFinder() }
                        .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .frame(minWidth: 180, idealWidth: 200)

            Group {
                if let bind = selectedPack {
                    Form {
                        TextField("Title", text: bind.title)
                        Section("Markdown") {
                            TextEditor(text: bind.body)
                                .frame(minHeight: 300)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                } else {
                    Text("Select or add a context pack")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd NotchyPrompter && swift build -c debug`
Expected: builds successfully.

- [ ] **Step 3: Run tests**

Run: `cd NotchyPrompter && swift test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add NotchyPrompter/Sources
git commit -m "Add tabbed Settings with Modes and Contexts editors"
```

---

## Phase 10 — Manual acceptance

### Task 10.1: Smoke-build the .app and exercise each flow

- [ ] **Step 1: Build the release .app**

Run: `cd NotchyPrompter && ./build.sh`
Expected: `NotchyPrompter.app` rebuilt with no errors.

- [ ] **Step 2: First-run migration check**

Launch. Confirm:
- Settings opens to the Backend tab (existing behaviour preserved).
- `~/Library/Application Support/NotchyPrompter/modes.json` now exists.
- `activeModeID` in UserDefaults matches a mode named "Watching".
- Three built-ins (Watching / Meeting / Custom) visible in Modes tab, two seeded customs (Interview / Presenting) below.

- [ ] **Step 3: Pipe a YouTube session**

Start listening on a YouTube interview. Confirm:
- Overlay shows bullets (Watching mode behaviour is byte-identical to v0.1).
- From the menu bar, switch Mode to Meeting mid-video. Confirm the next overlay is a first-person draft, not a bullet list.
- Stop. Confirm the new session JSON file exists under `sessions/` and contains a `mode` event for each switch.

- [ ] **Step 4: Attach a context pack**

Author a new context pack in Settings with a short résumé paragraph.
Attach it to Meeting mode. Switch to Meeting. Confirm the next LLM call's response reflects the attached content (e.g. uses names/facts from the pack).

- [ ] **Step 5: Session summary**

Stop. Wait ~5–10 s (auto-summary runs on Claude). Open the session JSON file. Confirm `summaries` has one entry. Trigger "Summarize Last Session…" from the menu bar; confirm a small window shows the summary.

- [ ] **Step 6: Ollama path**

Switch backend to Ollama. Start. Confirm the system prompt + context concatenation works (verify by editing Meeting mode's prompt to include a unique string, then checking Ollama's response reflects that instruction).

- [ ] **Step 7: Update CHANGELOG**

Append an `[Unreleased]` section entry to `CHANGELOG.md`:

```markdown
### Added
- **Modes**: selectable from menu bar. Three built-ins (Watching, Meeting, Custom) and two seeded custom examples (Interview, Presenting). Each mode bundles a system prompt and optional attached context packs.
- **Context packs**: markdown files stored under `~/Library/Application Support/NotchyPrompter/contexts/`. Attach per-mode in Settings → Contexts.
- **Session capture**: every Start→Stop cycle is saved as JSON under `~/Library/Application Support/NotchyPrompter/sessions/`, with auto-summary on Stop. "Summarize Last Session…" menu item re-runs with custom prompts.
- **Tabbed Settings**: Backend, Modes, Contexts, About.
```

- [ ] **Step 8: Commit**

```bash
git add CHANGELOG.md
git commit -m "CHANGELOG: document v0.2 modes, contexts, sessions"
```

---

## Self-review

**Spec coverage:**
- Modes data model (Mode, ModeDefaults) — Phase 3 Task 3.1
- ContextPack + on-disk format — Phase 2 Task 2.1
- Default seed data (3 built-ins + 2 seeded customs + default summary prompt) — Phase 3 Task 3.2
- modes.json file location — Phase 1 Task 1.1
- Menu bar submenu with ✓ on active mode, Edit Modes… — Phase 8 Task 8.1
- Settings tabs (Backend / Modes / Contexts / About) — Phase 9
- Modes tab with list, editor, Reset to Default, Add/Duplicate/Delete — Phase 9 Task 9.2
- Contexts tab with editor + Reveal in Finder — Phase 9 Task 9.3
- LLMRequest + protocol change — Phase 4 Task 4.1
- ClaudeClient multi-block caching with 4-breakpoint cap + overflow concat — Phase 4 Task 4.2
- OllamaClient uses system-from-mode + concat contexts — Phase 4 Task 4.3
- Pipeline reads active mode per chunk — Phase 5 Task 5.1
- SessionRecorder event ordering + JSON file — Phase 6 Task 6.2
- Mode switch mid-session stays in session, records mode event — Phase 8 Task 8.1 + Pipeline.recordModeChangeIfRunning
- Same-second filename collision suffix — Phase 6 Task 6.2
- Auto-summary on Stop (toggleable via autoSummarizeOnStop) — Phase 7
- "Summarize Last Session…" + summary window — Phase 8 Task 8.1 (AppDelegate helpers)
- "Open Sessions Folder" menu item — Phase 8 Task 8.1
- Migration (activeModeID defaults to Watching) — Phase 5 Task 5.1 Step 3
- v0.1 byte-identical Watching prompt — SeedData.watchingPrompt
- Unit tests for ContextPack, ModeStore, SessionRecorder, LLMRequest assembly — Phases 2, 3, 4, 6

All spec sections are covered. Two items deliberately deferred:
- The "show" summary window is minimal (scrolling NSTextView); a richer markdown renderer is out of scope.
- About tab is a stub per spec note.

No TBD / TODO placeholders remain. Type names match across tasks (spot-checked: Mode, ContextPack, LLMRequest, SessionEvent, SessionMeta all spelled consistently).

Execution gotcha to watch: `@testable import` of an executable target requires the target to set `-enable-testing` in debug builds; Swift 5.9 does this automatically for `.executableTarget` + `.testTarget` combos on macOS. If a tester hits "executable targets cannot be imported," fall back to the `NotchyPrompterKit` library-target split noted in Task 1.2 Step 3.
