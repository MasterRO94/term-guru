import Foundation

/// Command history from the shells' own history files; used for ranking and whole-line suggestions.
public final class HistoryStore {
    public private(set) var lines: [String] = []
    private var firstWordCounts: [String: Int] = [:]
    private var stamps: [String: Date] = [:]
    private var lastCheck = Date.distantPast
    private let files: [URL]

    public init(files: [URL]? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.files = files ?? [home.appendingPathComponent(".zsh_history"), home.appendingPathComponent(".bash_history")]
        reload(force: true)
    }

    public func reload(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastCheck) > 5 else { return }
        lastCheck = Date()
        var current: [String: Date] = [:]
        for file in files {
            current[file.path] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        guard force || current != stamps else { return }
        stamps = current

        var all: [String] = []
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            all += Self.parse(String(decoding: data, as: UTF8.self))
        }
        // Keep the newest occurrence of each line, newest first.
        var seen = Set<String>()
        lines = all.reversed().filter { seen.insert($0).inserted }
        firstWordCounts = [:]
        for line in all {
            if let word = line.split(separator: " ").first { firstWordCounts[String(word), default: 0] += 1 }
        }
    }

    static func parse(_ text: String) -> [String] {
        var result: [String] = []
        var pending = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(raw)
            if pending.isEmpty, line.hasPrefix(": "), let semi = line.firstIndex(of: ";") {
                line = String(line[line.index(after: semi)...])
            }
            if line.hasSuffix("\\") {
                pending += line.dropLast() + "\n"
                continue
            }
            let full = (pending + line).trimmingCharacters(in: .whitespaces)
            pending = ""
            if !full.isEmpty, !full.contains("\n") { result.append(full) }
        }
        return result
    }

    public func count(firstWord: String) -> Int { firstWordCounts[firstWord] ?? 0 }

    public func matches(prefix: String, limit: Int) -> [String] {
        guard !prefix.isEmpty else { return [] }
        var out: [String] = []
        for line in lines where line.count > prefix.count && line.hasPrefix(prefix) {
            out.append(line)
            if out.count == limit { break }
        }
        return out
    }
}
