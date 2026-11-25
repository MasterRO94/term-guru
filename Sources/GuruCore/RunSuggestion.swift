import Foundation

/// Once the word at the cursor is finished, Return should run the line instead of adding to it; this row says so.
public enum RunSuggestion {
    public static func promote(_ items: [Suggestion], buffer: String, cursor: Int) -> [Suggestion] {
        guard let first = items.first else { return items }
        let left = String(buffer.prefix(max(0, cursor)))
        let line = Tokenizer.parse(left)
        var rest = items
        let tabTarget: Suggestion
        let exact = items.filter { $0.replace > 0 && String(left.suffix($0.replace)) == $0.insert.trimmingCharacters(in: .whitespaces) }
        if let match = exact.first {
            tabTarget = match
            rest.removeAll { item in exact.contains(item) }
        } else if line.redirect == nil, line.tokens.count > 1, line.rawPartial.isEmpty {
            tabTarget = first
        } else if line.redirect == nil, line.rawPartial.hasSuffix("/"),
                  let kind = items.first(where: { $0.kind != .history })?.kind, kind == .file || kind == .folder {
            tabTarget = first
        } else {
            return items
        }
        let command = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        // Tab on this row does what it did on the row it displaced.
        let run = Suggestion(name: command, insert: tabTarget.insert, description: "Run the command", kind: .run,
                             replace: tabTarget.replace, cursorBack: tabTarget.cursorBack)
        return [run] + rest
    }
}
