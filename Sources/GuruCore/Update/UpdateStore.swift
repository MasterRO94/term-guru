import Foundation

public enum UpdateRunState: String, Codable, Sendable {
    case preparing, building, installed, dirty, diverged, failed

    public var isBusy: Bool { self == .preparing || self == .building }
}

public struct UpdateRun: Codable, Equatable, Sendable {
    public var state: UpdateRunState
    public var version: String
    public var pid: Int32?
    public var error: String?
    public var log: String?
    public var resetAccessibility = false
    public var updatedAt = Date()

    public init(state: UpdateRunState, version: String, pid: Int32? = nil, error: String? = nil, log: String? = nil) {
        self.state = state
        self.version = version
        self.pid = pid
        self.error = error
        self.log = log
    }
}

public struct UpdateRecord: Codable, Equatable, Sendable {
    public var latest: String?
    public var checkedAt: Date?
    public var notifiedVersion: String?
    public var run: UpdateRun?

    public init() {}
}

/// Shared between the app and the detached `tgr update --run` process, which outlives it.
public struct UpdateStore: Sendable {
    let url: URL

    public init(url: URL = GuruPaths.support.appendingPathComponent("update.json")) {
        self.url = url
    }

    public func load() -> UpdateRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let record = try? decoder.decode(UpdateRecord.self, from: data) else {
            return UpdateRecord()
        }
        return record
    }

    public func mutate(_ change: (inout UpdateRecord) -> Void) {
        var record = load()
        change(&record)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// A busy run whose process is gone was killed partway; report it instead of spinning forever.
    public func currentRun() -> UpdateRun? {
        guard var run = load().run else { return nil }
        if run.state.isBusy, let pid = run.pid, !Self.isAlive(pid) {
            run.state = .failed
            run.error = "The update stopped partway."
        }
        return run
    }

    public func clearRun() {
        mutate { $0.run = nil }
    }

    static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
