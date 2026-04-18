// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Safety net for small local models (notably Qwen 2B) that ignore the
/// Note-taker prompt's "never attribute" rule and emit bullets like
/// "- The speaker says X" or "- One person claimed Y".
///
/// Strips leading attribution clauses from each bullet. Designed to be
/// conservative: when in doubt, leave the bullet alone. Lines that don't
/// look like bullets (don't start with `-` or `*`) are passed through
/// untouched so prose / empty output / markdown headings survive.
///
/// Wire in at the tail of `Pipeline.handleLLM` before persisting/displaying
/// the reply. Gated by `SettingsStore.stripAttribution` so a user who wants
/// the raw LLM output can disable it.
enum AttributionStripper {
    /// Prefixes we strip from the start of a bullet body (after the leading
    /// "- "). Case-insensitive. Each is optionally followed by one of the
    /// speech verbs + separator. We only strip when a separator is present
    /// (comma, colon, or whitespace before a lowercase letter) so we don't
    /// chew into legitimate content like "The speaker's role in X".
    ///
    /// Matched at the start of a bullet only — never mid-bullet — to avoid
    /// mangling quoted text or embedded references.
    private static let attributionPattern: NSRegularExpression = {
        let verbs = "(?:said|says|claimed|claims|stated|states|explained|"
            + "explains|described|describes|mentioned|mentions|noted|notes|"
            + "argued|argues|discussed|discusses|questioned|questions|asked|"
            + "asks|thinks|thought|believes|believed|wants|wanted|"
            + "suggested|suggests|pointed out|points out|emphasized|"
            + "emphasizes|wondered|wonders)"
        let subjects = "(?:the speakers?|one (?:person|speaker)|another "
            + "(?:person|speaker)|the presenter|the author|the narrator|"
            + "the host|the interviewer|the guest|he|she|they)"
        // e.g. "The speaker says that X", "One person: X", "The speaker — X",
        // "They note X", "The presenter, in their discussion, says X"
        let pattern = "^\(subjects)(?:\\s+\(verbs))?(?:\\s+that)?"
            + "\\s*[,:\\-—–]?\\s*"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Apply the strip to a full LLM reply. Preserves blank lines and
    /// non-bullet lines verbatim.
    static func clean(_ reply: String) -> String {
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false)
        let cleaned = lines.map { cleanLine(String($0)) }
        return cleaned.joined(separator: "\n")
    }

    /// Exposed for tests. Returns the line with attribution stripped if it
    /// looked like a bullet, otherwise returns the line unchanged.
    static func cleanLine(_ line: String) -> String {
        // Match a leading bullet marker: "-", "*", or "•", optionally indented.
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let marker = trimmed.first, marker == "-" || marker == "*" || marker == "\u{2022}" else {
            return line
        }
        // Split into "<indent + marker + space>" and "<body>".
        let leadCount = line.distance(from: line.startIndex,
                                      to: line.index(after: line.firstIndex(of: marker)!))
        var leadEnd = line.index(line.startIndex, offsetBy: leadCount)
        while leadEnd < line.endIndex, line[leadEnd] == " " {
            leadEnd = line.index(after: leadEnd)
        }
        let lead = String(line[..<leadEnd])
        var body = String(line[leadEnd...])
        guard !body.isEmpty else { return line }

        // Apply the regex strip.
        let ns = body as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matched = attributionPattern.firstMatch(in: body, options: [], range: range)
        guard let m = matched, m.range.location == 0, m.range.length > 0 else {
            return line
        }
        body = ns.substring(from: m.range.length)
        // If stripping left nothing useful, drop the whole bullet.
        let rest = body.trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return "" }
        // Re-capitalize the first letter — prompts typically expect sentence case.
        let first = rest.prefix(1).uppercased()
        let tail = rest.dropFirst()
        return lead + first + tail
    }
}
