import Foundation

public enum SemVer {
    /// Accepts only `X.Y.Z`, with an optional leading `v`.
    public static func normalize(_ raw: String?) -> String? {
        guard var candidate = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let first = candidate.first, first == "v" || first == "V" { candidate.removeFirst() }
        return parts(candidate) == nil ? nil : candidate
    }

    public static func compare(_ a: String, _ b: String) -> Int {
        let left = parts(a) ?? [0, 0, 0], right = parts(b) ?? [0, 0, 0]
        for (l, r) in zip(left, right) where l != r { return l < r ? -1 : 1 }
        return 0
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    private static func parts(_ version: String) -> [Int]? {
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        let numbers = pieces.compactMap { piece in piece.allSatisfy(\.isASCII) && piece.allSatisfy(\.isNumber) ? Int(piece) : nil }
        return numbers.count == 3 ? numbers : nil
    }
}
