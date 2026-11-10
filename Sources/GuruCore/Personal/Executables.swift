import Foundation

public final class ExecutableIndex {
    private var cache: [String: (names: [String], at: Date)] = [:]

    public init() {}

    public func invalidate() { cache.removeAll() }

    public func names(path: String) -> [String] {
        if let hit = cache[path], Date().timeIntervalSince(hit.at) < 120 { return hit.names }
        var seen = Set<String>()
        var names: [String] = []
        let fm = FileManager.default
        for dir in path.split(separator: ":") {
            guard let entries = try? fm.contentsOfDirectory(atPath: String(dir)) else { continue }
            for entry in entries where !entry.hasPrefix(".") && seen.insert(entry).inserted {
                if fm.isExecutableFile(atPath: "\(dir)/\(entry)") { names.append(entry) }
            }
        }
        cache[path] = (names, Date())
        return names
    }
}
