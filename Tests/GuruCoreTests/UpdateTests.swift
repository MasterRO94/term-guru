import Foundation
import Testing
@testable import GuruCore

@Suite struct SemVerTests {
    @Test func normalizesOnlyStrictVersions() {
        #expect(SemVer.normalize("v0.1.2") == "0.1.2")
        #expect(SemVer.normalize(" 1.20.3\n") == "1.20.3")
        #expect(SemVer.normalize("dev") == nil)
        #expect(SemVer.normalize("1.2") == nil)
        #expect(SemVer.normalize("1.2.3-beta") == nil)
        #expect(SemVer.normalize(nil) == nil)
    }

    @Test func comparesNumerically() {
        #expect(SemVer.isNewer("0.10.1", than: "0.9.0"))
        #expect(!SemVer.isNewer("0.1.1", than: "0.1.1"))
        #expect(!SemVer.isNewer("0.1.0", than: "0.1.1"))
        #expect(SemVer.compare("1.0.0", "0.99.99") == 1)
    }
}

@Suite struct LatestReleaseTests {
    @Test func picksHighestReleaseTag() {
        let output = """
        aaa\trefs/tags/v0.9.0
        bbb\trefs/tags/v0.10.1
        ccc\trefs/tags/v0.2.0
        ddd\trefs/tags/vnext
        eee\trefs/tags/v1.0.0-rc1
        """
        #expect(LatestRelease.highest(fromLsRemote: output) == "0.10.1")
        #expect(LatestRelease.highest(fromLsRemote: "") == nil)
    }
}

@Suite struct UpdateSourceTests {
    @Test func normalizesRemotes() {
        #expect(UpdateSource.normalizeRemote("git@github.com:MasterRO94/term-guru.git\n") == "masterro94/term-guru")
        #expect(UpdateSource.normalizeRemote("https://github.com/MasterRO94/term-guru") == "masterro94/term-guru")
        #expect(UpdateSource.normalizeRemote("ssh://git@github.com/MasterRO94/term-guru.git/") == "masterro94/term-guru")
        #expect(UpdateSource.normalizeRemote("term-guru") == nil)
    }

    @Test func rejectsCheckoutsOfOtherRepositories() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        #expect(UpdateSource.validate(path: fixture.clone, expected: fixture.slug) == nil)
        #expect(UpdateSource.validate(path: fixture.clone, expected: "someone/else") != nil)
        #expect(UpdateSource.validate(path: fixture.root + "/missing", expected: fixture.slug) != nil)
    }
}

@Suite struct UpdateStoreTests {
    @Test func roundTripsAndClearsRuns() {
        let store = UpdateStore(url: temporaryFile())
        store.mutate { $0.latest = "0.2.0"; $0.run = UpdateRun(state: .installed, version: "0.2.0") }
        #expect(store.load().latest == "0.2.0")
        #expect(store.currentRun()?.state == .installed)
        store.clearRun()
        #expect(store.currentRun() == nil)
        #expect(store.load().latest == "0.2.0")
    }

    @Test func busyRunOfDeadProcessReadsAsFailed() {
        let store = UpdateStore(url: temporaryFile())
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try? finished.run()
        finished.waitUntilExit()
        store.mutate { $0.run = UpdateRun(state: .building, version: "0.2.0", pid: finished.processIdentifier) }
        #expect(store.currentRun()?.state == .failed)

        store.mutate { $0.run = UpdateRun(state: .building, version: "0.2.0", pid: ProcessInfo.processInfo.processIdentifier) }
        #expect(store.currentRun()?.state == .building)
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("guru-update-\(UUID().uuidString).json")
    }
}

@Suite struct PrepareCheckoutTests {
    @Test func fastForwardsToTheReleaseTag() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.release("0.2.0")
        let outcome = PrepareCheckout.run(path: fixture.clone, version: "0.2.0") { _ in }
        #expect(outcome.failure == nil)
        #expect(try String(contentsOfFile: fixture.clone + "/VERSION", encoding: .utf8) == "0.2.0\n")
    }

    @Test func dirtyCheckoutIsLeftUntouched() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.release("0.2.0")
        try "local edit\n".write(toFile: fixture.clone + "/VERSION", atomically: true, encoding: .utf8)
        let outcome = PrepareCheckout.run(path: fixture.clone, version: "0.2.0") { _ in }
        #expect(outcome.failure == .dirty)
        #expect(try String(contentsOfFile: fixture.clone + "/VERSION", encoding: .utf8) == "local edit\n")
    }

    @Test func divergedCheckoutIsNotMerged() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.release("0.2.0")
        try fixture.commit(in: fixture.clone, file: "local.txt", content: "mine\n")
        let head = try fixture.git(["rev-parse", "HEAD"], in: fixture.clone)
        let outcome = PrepareCheckout.run(path: fixture.clone, version: "0.2.0") { _ in }
        #expect(outcome.failure == .diverged)
        #expect(try fixture.git(["rev-parse", "HEAD"], in: fixture.clone) == head)
    }

    @Test func checkoutAheadOfTheTagIsKept() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        try fixture.release("0.2.0")
        _ = try fixture.git(["pull", "--ff-only"], in: fixture.clone)
        try fixture.commit(in: fixture.clone, file: "local.txt", content: "mine\n")
        #expect(PrepareCheckout.run(path: fixture.clone, version: "0.2.0") { _ in }.failure == nil)
    }

    @Test func unreachableOriginFails() throws {
        let fixture = try GitFixture()
        defer { fixture.remove() }
        _ = try fixture.git(["remote", "set-url", "origin", fixture.root + "/gone.git"], in: fixture.clone)
        #expect(PrepareCheckout.run(path: fixture.clone, version: "0.2.0") { _ in }.failure == .failed)
    }
}

/// A bare origin, an upstream working copy that publishes releases, and the user's clone.
struct GitFixture {
    struct Failure: Error { var message: String }

    let root: String
    var origin: String { root + "/acme/origin.git" }
    var upstream: String { root + "/upstream" }
    var clone: String { root + "/clone" }
    let slug = "acme/origin"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("guru-git-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root + "/acme", withIntermediateDirectories: true)
        _ = try git(["init", "--bare", "--initial-branch=main", origin], in: root)
        _ = try git(["clone", origin, upstream], in: root)
        try commit(in: upstream, file: "VERSION", content: "0.1.0\n")
        _ = try git(["push", "origin", "HEAD:main"], in: upstream)
        _ = try git(["clone", origin, clone], in: root)
    }

    func release(_ version: String) throws {
        try commit(in: upstream, file: "VERSION", content: version + "\n")
        _ = try git(["tag", "v" + version], in: upstream)
        _ = try git(["push", "origin", "HEAD:main", "v" + version], in: upstream)
    }

    func commit(in path: String, file: String, content: String) throws {
        try content.write(toFile: path + "/" + file, atomically: true, encoding: .utf8)
        _ = try git(["add", file], in: path)
        _ = try git(["-c", "user.name=Test", "-c", "user.email=test@example.com", "-c", "commit.gpgsign=false", "commit", "-m", file], in: path)
    }

    @discardableResult
    func git(_ arguments: [String], in path: String) throws -> String {
        let result = Shell.run(["git"] + arguments, cwd: path, timeout: 30)
        guard result.status == 0 else { throw Failure(message: result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}
