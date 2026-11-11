import Foundation

enum FileSuggestions {
    static let parentLevels = 5

    /// `rawPartial` is the path as typed; only its last component is replaced on insert.
    static func list(partial: String, rawPartial: String, cwd: String, foldersOnly: Bool) -> (items: [Suggestion], query: String) {
        let slash = partial.lastIndex(of: "/")
        let dirPart = slash.map { String(partial[...$0]) } ?? ""
        let query = slash.map { String(partial[partial.index(after: $0)...]) } ?? partial
        let rawQuery = rawPartial.lastIndex(of: "/").map { String(rawPartial[rawPartial.index(after: $0)...]) } ?? rawPartial

        var directory = dirPart.isEmpty ? cwd : (dirPart as NSString).expandingTildeInPath
        if !directory.hasPrefix("/") { directory = (cwd as NSString).appendingPathComponent(directory) }

        var items = foldersOnly ? parents(partial: partial, replace: rawPartial.count, cwd: cwd) : []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return (items, query) }
        let showHidden = query.hasPrefix(".")
        for entry in entries.sorted() {
            if entry.hasPrefix("."), !showHidden { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: (directory as NSString).appendingPathComponent(entry), isDirectory: &isDir)
            if foldersOnly, !isDir.boolValue { continue }
            let quoted = Tokenizer.quote(entry)
            items.append(Suggestion(
                name: entry,
                display: isDir.boolValue ? entry + "/" : entry,
                insert: isDir.boolValue ? quoted + "/" : quoted + " ",
                kind: isDir.boolValue ? .folder : .file,
                priority: isDir.boolValue ? 46 : 45,
                replace: rawQuery.count,
                icon: isDir.boolValue ? .fileType("/") : SuggestionIcon.fileType(name: entry)
            ))
            if items.count >= 2000 { break }
        }
        return (items, query)
    }

    /// `../`, `../../`… for an empty word, `.`, `..` or a `../` chain: the next levels up, never past `/`.
    static func parents(partial: String, replace: Int, cwd: String) -> [Suggestion] {
        var rest = Substring(partial)
        var depth = 0
        while rest.hasPrefix("../") { rest = rest.dropFirst(3); depth += 1 }
        guard rest.isEmpty || rest == "." || rest == ".." else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var path = URL(fileURLWithPath: cwd).standardizedFileURL.path
        for _ in 0..<depth where path != "/" { path = (path as NSString).deletingLastPathComponent }
        var items: [Suggestion] = []
        for level in (depth + 1)...max(depth + 1, parentLevels) where level <= parentLevels && path != "/" {
            path = (path as NSString).deletingLastPathComponent
            let name = String(repeating: "../", count: level)
            let shown = path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
            items.append(Suggestion(name: name, insert: name, description: shown, kind: .folder,
                                    priority: 44, replace: replace, icon: .fileType("/")))
        }
        return items
    }
}
