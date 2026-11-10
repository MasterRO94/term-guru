import Foundation

public struct FileLog: Sendable {
    let url: URL

    public init(name: String) {
        try? FileManager.default.createDirectory(at: GuruPaths.logs, withIntermediateDirectories: true)
        url = GuruPaths.logs.appendingPathComponent(name)
    }

    public func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
