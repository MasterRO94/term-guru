import Foundation

enum FileSuggestions {
    /// `rawPartial` is the path as typed; only its last component is replaced on insert.
    static func list(partial: String, rawPartial: String, cwd: String, foldersOnly: Bool) -> (items: [Suggestion], query: String) {
        let slash = partial.lastIndex(of: "/")
        let dirPart = slash.map { String(partial[...$0]) } ?? ""
        let query = slash.map { String(partial[partial.index(after: $0)...]) } ?? partial
        let rawQuery = rawPartial.lastIndex(of: "/").map { String(rawPartial[rawPartial.index(after: $0)...]) } ?? rawPartial

        var directory = dirPart.isEmpty ? cwd : (dirPart as NSString).expandingTildeInPath
        if !directory.hasPrefix("/") { directory = (cwd as NSString).appendingPathComponent(directory) }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return ([], query) }
        let showHidden = query.hasPrefix(".")
        var items: [Suggestion] = []
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
                replace: rawQuery.count
            ))
            if items.count >= 2000 { break }
        }
        return (items, query)
    }
}
