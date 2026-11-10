import Foundation

public struct AliasStore {
    public enum AliasError: Error, CustomStringConvertible {
        case invalidName(String)
        case notFound(String)

        public var description: String {
            switch self {
            case let .invalidName(name): "invalid alias name '\(name)' (use letters, digits, _ . : -)"
            case let .notFound(name): "no alias named '\(name)'"
            }
        }
    }

    let file: URL

    public init(file: URL = GuruPaths.aliases) { self.file = file }

    public func list() -> [(name: String, value: String)] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("alias "), let eq = line.firstIndex(of: "=") else { return nil }
            let name = String(line[line.index(line.startIndex, offsetBy: 6)..<eq])
            var value = String(line[line.index(after: eq)...])
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
            }
            return (name, value)
        }
    }

    public func add(name: String, value: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.:-"))
        guard !name.isEmpty, name.unicodeScalars.allSatisfy(allowed.contains), !name.hasPrefix("-") else {
            throw AliasError.invalidName(name)
        }
        var entries = list().filter { $0.name != name }
        entries.append((name, value))
        try write(entries)
    }

    public func remove(name: String) throws {
        let entries = list()
        guard entries.contains(where: { $0.name == name }) else { throw AliasError.notFound(name) }
        try write(entries.filter { $0.name != name })
    }

    private func write(_ entries: [(name: String, value: String)]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = entries.map { "alias \($0.name)='\($0.value.replacingOccurrences(of: "'", with: "'\\''"))'" }
        let text = "# Managed by `tgr alias`. Sourced by the TermGuru shell integration.\n" + body.joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
