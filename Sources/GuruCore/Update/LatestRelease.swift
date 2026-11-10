import Foundation

public enum LatestRelease {
    public enum Lookup: Equatable, Sendable {
        case found(String)
        case noReleases
        case unreachable(String)
    }

    /// Release tags are the update signal: `Scripts/release.sh` pushes one with every GitHub release.
    public static func fetch(from source: UpdateSource) -> Lookup {
        let pattern = "refs/tags/\(UpdateSource.tagPrefix)*"
        let result = Git.run(["ls-remote", "--tags", "--refs", "origin", pattern], in: source.path, timeout: 20)
        guard result.status == 0 else {
            return .unreachable(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return highest(fromLsRemote: result.stdout).map(Lookup.found) ?? .noReleases
    }

    static func highest(fromLsRemote output: String) -> String? {
        output.split(separator: "\n")
            .compactMap { line -> String? in
                guard let name = line.split(separator: "/").last, name.hasPrefix(UpdateSource.tagPrefix) else { return nil }
                return SemVer.normalize(String(name))
            }
            .max { SemVer.compare($0, $1) < 0 }
    }
}
