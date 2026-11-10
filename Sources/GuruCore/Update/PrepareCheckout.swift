import Foundation

public enum PrepareCheckout {
    public struct Outcome: Equatable, Sendable {
        /// `nil` when the checkout now contains the release.
        public var failure: UpdateRunState?
        public var error: String?
    }

    /// Fast-forwards the checkout to the release tag. Never pulls, stashes or rewrites local work.
    public static func run(path: String, version: String, output: (String) -> Void) -> Outcome {
        func git(_ arguments: [String]) -> ShellResult {
            output("$ git \(arguments.joined(separator: " "))")
            let result = Git.run(arguments, in: path)
            let text = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { output(text) }
            return result
        }

        let status = git(["status", "--porcelain=v1", "--untracked-files=no"])
        guard status.status == 0 else { return Outcome(failure: .failed, error: "git status failed in \(path).") }
        let dirty = status.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dirty.isEmpty else {
            return Outcome(failure: .dirty, error: "Uncommitted changes in \(path):\n\(dirty)\n\nCommit or stash them, then update again.")
        }

        guard git(["fetch", "--prune", "--tags", "origin"]).status == 0 else {
            return Outcome(failure: .failed, error: "Could not reach origin.")
        }

        let branch = git(["rev-parse", "--abbrev-ref", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch != UpdateSource.branch, git(["switch", UpdateSource.branch]).status != 0 {
            return Outcome(failure: .failed, error: "Could not switch \(path) to \(UpdateSource.branch).")
        }

        let tag = "refs/tags/\(UpdateSource.tagPrefix)\(version)"
        guard git(["merge", "--ff-only", tag]).status == 0 else {
            return Outcome(
                failure: .diverged,
                error: "\(UpdateSource.branch) in \(path) has commits that \(UpdateSource.tagPrefix)\(version) does not, so it cannot fast-forward.\n\nInspect them with: git log --oneline \(UpdateSource.tagPrefix)\(version)..\(UpdateSource.branch)"
            )
        }
        return Outcome(failure: nil, error: nil)
    }
}
