import Foundation

public enum SuggestionKind: String, Codable, Sendable {
    case command, subcommand, option, argument, file, folder, alias, history, script
}

public enum SuggestionIcon: Equatable, Sendable {
    case emoji(String)
    /// `fig://icon?type=…`; the app maps the type to an SF Symbol.
    case fig(String)
    /// `fig://template?color=…&badge=…`: a rounded square in that hex color with the badge text.
    case template(color: String?, badge: String?)
    /// Lowercased file extension, or "/" for a folder.
    case fileType(String)

    /// Remote URLs give nil: typing must never wait on the network, and fetching would leak the line to a third party.
    public static func parse(_ raw: String) -> SuggestionIcon? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("fig://icon?") {
            return query(value)["type"].map(SuggestionIcon.fig)
        }
        if value.hasPrefix("fig://template") {
            let fields = query(value)
            return .template(color: fields["color"], badge: fields["badge"])
        }
        if value.hasPrefix("fig://path/") {
            let path = String(value.dropFirst("fig://path/".count))
            return path.hasSuffix("/") ? .fileType("/") : fileType(name: (path as NSString).lastPathComponent)
        }
        if value.contains("://") || value.contains("/") { return nil }
        // Emoji, sometimes with a variation selector or ZWJ sequence, are one or two grapheme clusters.
        return value.count <= 2 ? .emoji(value) : nil
    }

    static func fileType(name: String) -> SuggestionIcon {
        let ext = (name as NSString).pathExtension
        // `.env` has no extension to NSString; its name is the type.
        if ext.isEmpty, name.hasPrefix("."), name.count > 1 { return .fileType(name.dropFirst().lowercased()) }
        return .fileType(ext.lowercased())
    }

    private static func query(_ url: String) -> [String: String] {
        guard let mark = url.firstIndex(of: "?") else { return [:] }
        var fields: [String: String] = [:]
        for pair in url[url.index(after: mark)...].split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            let value = String(parts[1])
            fields[String(parts[0])] = value.removingPercentEncoding ?? value
        }
        return fields
    }
}

public struct Suggestion: Equatable, Sendable, Identifiable {
    public var name: String
    /// Text shown in the list when it differs from the matched name.
    public var display: String
    public var insert: String
    public var description: String
    public var kind: SuggestionKind
    public var priority: Double
    /// Characters left of the cursor that the insert replaces.
    public var replace: Int
    /// How far to move the cursor back after inserting (Fig's `{cursor}` marker).
    public var cursorBack: Int
    public var icon: SuggestionIcon?
    public var score: Double = 0

    public var id: String { "\(kind.rawValue):\(name):\(insert)" }

    public init(
        name: String, display: String? = nil, insert: String? = nil, description: String = "", kind: SuggestionKind,
        priority: Double = 50, replace: Int = 0, cursorBack: Int = 0, icon: SuggestionIcon? = nil
    ) {
        self.name = name
        self.display = display ?? name
        self.insert = insert ?? name
        self.description = description
        self.kind = kind
        self.priority = priority
        self.replace = replace
        self.cursorBack = cursorBack
        self.icon = icon
    }
}

public enum Fuzzy {
    /// nil when `query` is not a subsequence of `candidate`. Higher is better.
    public static func score(_ query: String, in candidate: String) -> Double? {
        // Same base as a prefix hit, so unfiltered groups rank against filtered ones by priority alone.
        if query.isEmpty { return 100 }
        let q = Array(query.lowercased()), c = Array(candidate.lowercased())
        guard q.count <= c.count else { return nil }
        if c.starts(with: q) {
            return 100 + (q.count == c.count ? 20 : 0) + (candidate.hasPrefix(query) ? 5 : 0)
        }
        var qi = 0, score = 0.0, streak = 0.0
        for (ci, ch) in c.enumerated() where qi < q.count {
            guard ch == q[qi] else { streak = 0; continue }
            let boundary = ci == 0 || !(c[ci - 1].isLetter || c[ci - 1].isNumber)
            score += 4 + streak * 3 + (boundary ? 8 : 0)
            streak += 1
            qi += 1
        }
        guard qi == q.count else { return nil }
        return min(score, 90) - Double(c.count - q.count) * 0.1
    }

    public static func rank(_ items: [Suggestion], query: String, limit: Int) -> [Suggestion] {
        var seen = Set<String>()
        var scored: [Suggestion] = []
        for var item in items {
            guard let s = score(query, in: item.name) else { continue }
            guard seen.insert(item.insert + "\u{0}" + item.kind.rawValue).inserted else { continue }
            item.score = s + item.priority
            scored.append(item)
        }
        // Stable sort keeps spec order for ties, which is how spec authors expect lists to read.
        let ordered = scored.enumerated().sorted {
            $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
        }
        return ordered.prefix(limit).map(\.element)
    }
}
