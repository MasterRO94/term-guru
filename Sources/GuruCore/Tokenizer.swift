import Foundation

/// What the word under the cursor is the target of, when it follows a redirection operator.
public enum Redirect: Equatable, Sendable {
    /// `>`, `>>`, `<`, `&>` and friends: the target is a path.
    case file
    /// Heredoc delimiters, here-strings and fd dups: nothing useful to suggest.
    case none
}

public struct ParsedLine: Equatable, Sendable {
    /// Words of the command being edited; the last one is the word under the cursor (may be empty).
    /// Redirection operators and their targets are left out, except a target under the cursor.
    public var tokens: [String]
    /// Raw text of the last word as typed, including quotes and escapes.
    public var rawPartial: String
    /// Set when the word under the cursor is a redirection target.
    public var redirect: Redirect? = nil

    public var partial: String { tokens.last ?? "" }
    public var complete: [String] { Array(tokens.dropLast()) }
}

public enum Tokenizer {
    private static let separators: Set<Character> = ["|", ";", "(", ")", "{", "}"]

    /// Splits the text left of the cursor and keeps only the last pipeline segment.
    public static func parse(_ text: String) -> ParsedLine {
        let chars = Array(text)
        var tokens: [String] = []
        var current = ""
        var raw = ""
        var inToken = false
        var quote: Character?
        var escaped = false
        var target: Redirect?

        func finish() {
            if inToken {
                if target != nil { target = nil } else { tokens.append(current) }
            }
            current = ""; raw = ""; inToken = false
        }

        func separate() {
            finish()
            tokens.removeAll()
            target = nil
        }

        var i = 0
        func next(_ offset: Int = 1) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }

        while i < chars.count {
            let ch = chars[i]
            defer { i += 1 }
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
            case "&":
                if next() == ">" {
                    finish()
                    i += next(2) == ">" ? 2 : 1
                    target = .file
                } else {
                    if next() == "&" { i += 1 }
                    separate()
                }
            case ">", "<":
                // A word of only digits right before the operator is its fd, as in 2>err.
                if inToken, target == nil, !current.isEmpty, raw == current, current.allSatisfy { $0.isASCII && $0.isNumber } {
                    current = ""; raw = ""; inToken = false
                } else {
                    finish()
                }
                let (kind, length) = redirectOperator(chars, at: i)
                target = kind
                i += length - 1
            case _ where separators.contains(ch):
                separate()
            default:
                current.append(ch); raw.append(ch); inToken = true
            }
        }

        let trailingRaw = raw
        tokens.append(inToken ? current : "")
        while let first = tokens.first, tokens.count > 1, isAssignment(first) { tokens.removeFirst() }
        return ParsedLine(tokens: tokens, rawPartial: inToken ? trailingRaw : "", redirect: target)
    }

    /// Reads the operator starting at `chars[i]` (`>` or `<`): what its target is and how many characters it spans.
    private static func redirectOperator(_ chars: [Character], at i: Int) -> (Redirect, Int) {
        func at(_ offset: Int) -> Character? { i + offset < chars.count ? chars[i + offset] : nil }
        if chars[i] == "<" {
            switch at(1) {
            case "<": return (.none, at(2) == "<" || at(2) == "-" ? 3 : 2)
            case "&": return (.none, 2)
            case ">": return (.file, 2)
            default: return (.file, 1)
            }
        }
        switch at(1) {
        case "&": return (.none, 2)
        case "|", "!": return (.file, 2)
        case ">": return (.file, at(2).map { "&|!".contains($0) } == true ? 3 : 2)
        default: return (.file, 1)
        }
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
