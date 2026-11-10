import Foundation

public struct ShellResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var status: Int32
}

public enum Shell {
    public static func run(
        _ argv: [String], cwd: String? = nil, environment: [String: String]? = nil, timeout: TimeInterval = 2
    ) -> ShellResult {
        guard !argv.isEmpty else { return ShellResult(stdout: "", stderr: "", status: 127) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = argv
        if let cwd, FileManager.default.fileExists(atPath: cwd) {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        let readers = DispatchQueue(label: "dev.termguru.shell.read", attributes: .concurrent)
        do { try process.run() } catch {
            return ShellResult(stdout: "", stderr: "\(error)", status: 127)
        }
        // Drain both pipes concurrently so a chatty child cannot block on a full pipe buffer.
        group.enter(); readers.async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); readers.async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        process.waitUntilExit()
        killer.cancel()
        _ = group.wait(timeout: .now() + 1)

        return ShellResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            status: process.terminationStatus
        )
    }
}
