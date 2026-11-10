import Foundation

public struct ParsedLine: Equatable, Sendable {
    /// Words of the command being edited; the last one is the word under the cursor (may be empty).
    public var tokens: [String]
    /// Raw text of the last word as typed, including quotes and escapes.
    public var rawPartial: String

    public var partial: String { tokens.last ?? "" }
    public var complete: [String] { Array(tokens.dropLast()) }
}

public enum Tokenizer {
    private static let operators: Set<Character> = ["|", "&", ";", "(", ")", "{", "}"]

    /// Splits the text left of the cursor and keeps only the last pipeline segment.
    public static func parse(_ text: String) -> ParsedLine {
        var tokens: [String] = []
        var current = ""
        var raw = ""
        var inToken = false
        var quote: Character?
        var escaped = false

        func finish() {
            if inToken { tokens.append(current) }
            current = ""; raw = ""; inToken = false
        }

        for ch in text {
            if escaped {
                current.append(ch); raw.append(ch); escaped = false
                continue
            }
            if let q = quote {
                raw.append(ch)
                if ch == q { quote = nil } else if ch == "\\" && q == "\"" { escaped = true } else { current.append(ch) }
                continue
            }
            switch ch {
            case "\\":
                escaped = true; inToken = true; raw.append(ch)
            case "'", "\"":
                quote = ch; inToken = true; raw.append(ch)
            case " ", "\t", "\n":
                finish()
            case _ where operators.contains(ch):
                finish()
                tokens.removeAll()
            default:
                current.append(ch); raw.append(ch); inToken = true
            }
        }

        let trailingRaw = raw
        if inToken { tokens.append(current) } else { tokens.append("") }
        while let first = tokens.first, tokens.count > 1, isAssignment(first) { tokens.removeFirst() }
        return ParsedLine(tokens: tokens, rawPartial: inToken ? trailingRaw : "")
    }

    private static func isAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "="), eq != token.startIndex else { return false }
        return token[..<eq].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    public static func quote(_ value: String) -> String {
        let special = CharacterSet(charactersIn: " \t\n'\"\\$`!*?[]{}()<>|&;#~")
        guard value.unicodeScalars.contains(where: special.contains) else { return value }
        var out = ""
        for scalar in value.unicodeScalars {
            if special.contains(scalar) { out.append("\\") }
            out.unicodeScalars.append(scalar)
        }
        return out
    }
}
