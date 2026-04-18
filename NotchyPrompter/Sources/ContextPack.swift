// SPDX-License-Identifier: AGPL-3.0-or-later
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
