import Foundation

enum Git {
    static func run(_ arguments: [String], in path: String, timeout: TimeInterval = 120) -> ShellResult {
        var environment = ProcessInfo.processInfo.environment
        // The app has no terminal: a prompt for credentials or a host key would hang until the timeout.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
        return Shell.run(["git"] + arguments, cwd: path, environment: environment, timeout: timeout)
    }
}

/// The checkout this build came from; updates are rebuilt there.
public struct UpdateSource: Equatable, Sendable {
    public static let repository = "masterro94/term-guru"
    public static let branch = "main"
    public static let tagPrefix = "v"

    public var path: String
    /// `-` is ad-hoc, which makes macOS drop the Accessibility grant on every rebuild.
    public var identity: String

    public init(path: String, identity: String = "-") {
        self.path = path
        self.identity = identity
    }

    public var isAdHocSigned: Bool { identity == "-" }

    public static func resolve() -> (source: UpdateSource?, reason: String?) {
        let environment = ProcessInfo.processInfo.environment
        let info = NSDictionary(contentsOf: GuruResources.bundleContents.appendingPathComponent("Info.plist"))
        guard let path = environment["GURU_UPDATE_SOURCE"] ?? info?["GuruSourcePath"] as? String, !path.isEmpty else {
            return (nil, "This build does not record its source checkout. Run Scripts/install.sh from the repository once.")
        }
        let source = UpdateSource(path: path, identity: info?["GuruCodesignIdentity"] as? String ?? "-")
        if let reason = validate(path: path, expected: environment["GURU_UPDATE_REMOTE"] ?? repository) { return (nil, reason) }
        return (source, nil)
    }

    static func validate(path: String, expected: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return "The source checkout at \(path) no longer exists. Clone it again and run Scripts/install.sh."
        }
        guard FileManager.default.fileExists(atPath: path + "/.git") else {
            return "\(path) is not a git checkout."
        }
        let remote = Git.run(["remote", "get-url", "origin"], in: path, timeout: 10)
        guard remote.status == 0, normalizeRemote(remote.stdout) == expected.lowercased() else {
            return "\(path) does not track \(expected)."
        }
        return nil
    }

    /// Reduces SSH and HTTPS remotes to a lowercase `owner/name`.
    static func normalizeRemote(_ url: String) -> String? {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        let pieces = value.split(whereSeparator: { $0 == "/" || $0 == ":" })
        guard pieces.count >= 2 else { return nil }
        return pieces.suffix(2).joined(separator: "/")
    }
}
