import Foundation

/// Line protocol shared with the shell hooks. Fields are split by US; newlines inside a field travel as RS.
public enum Wire {
    public static let separator: Character = "\u{1f}"
    public static let newline: Character = "\u{1e}"

    public static func split(_ line: String) -> [String] {
        line.split(separator: separator, omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: String(newline), with: "\n")
        }
    }

    public static func join(_ fields: [String]) -> String {
        fields
            .map { $0.replacingOccurrences(of: "\n", with: String(newline)) }
            .joined(separator: String(separator))
    }
}
