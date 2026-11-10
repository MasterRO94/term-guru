import Foundation

public struct UpdateRunner {
    static let buildTimeout: TimeInterval = 3600

    let source: UpdateSource
    let version: String
    let store: UpdateStore
    let echo: Bool
    let logURL: URL
    private let logHandle: FileHandle?

    public init(source: UpdateSource, version: String, store: UpdateStore = UpdateStore(), echo: Bool) {
        self.source = source
        self.version = version
        self.store = store
        self.echo = echo
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        try? FileManager.default.createDirectory(at: GuruPaths.logs, withIntermediateDirectories: true)
        logURL = GuruPaths.logs.appendingPathComponent("update-\(version)-\(formatter.string(from: Date())).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)
    }

    @discardableResult
    public func run() -> Bool {
        record(.preparing)
        let checkout = PrepareCheckout.run(path: source.path, version: version, output: emit)
        if let failure = checkout.failure {
            record(failure, error: checkout.error)
            return false
        }

        record(.building)
        let status = install()
        guard status == 0 else {
            record(.failed, error: "Scripts/install.sh exited with status \(status).")
            return false
        }
        let installed = Self.installedVersion()
        guard let installed, SemVer.compare(installed, version) >= 0 else {
            record(.failed, error: "The build installed \(installed ?? "nothing"), not \(version). Is the VERSION file up to date?")
            return false
        }

        // Ad-hoc builds get a new code signature every time, which leaves a stale grant macOS no longer honours.
        if source.isAdHocSigned {
            emit("$ tccutil reset Accessibility \(GuruID.appBundle)")
            _ = Shell.run(["tccutil", "reset", "Accessibility", GuruID.appBundle], timeout: 10)
        }
        store.mutate {
            var run = UpdateRun(state: .installed, version: installed, log: logURL.path)
            run.resetAccessibility = source.isAdHocSigned
            $0.run = run
        }
        if source.isAdHocSigned {
            AppControl.stop()
            usleep(600_000)
            AppControl.start()
        }
        emit("updated to \(installed)")
        return true
    }

    public static func installedVersion() -> String? {
        let plist = GuruPaths.installedApp.appendingPathComponent("Contents/Info.plist")
        return NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String
    }

    private func install() -> Int32 {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        emit("$ Scripts/install.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // A login shell, because the app inherits launchd's bare PATH and the build needs the user's tools.
        process.arguments = ["-lc", "exec Scripts/install.sh"]
        process.currentDirectoryURL = URL(fileURLWithPath: source.path)
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        if !source.isAdHocSigned { environment["CODESIGN_IDENTITY"] = source.identity }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { write(data) }
        }
        do { try process.run() } catch {
            emit("\(error)")
            return 127
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.buildTimeout, execute: killer)
        process.waitUntilExit()
        killer.cancel()
        // Not read to EOF: anything install.sh leaves running would hold the pipe open.
        pipe.fileHandleForReading.readabilityHandler = nil
        return process.terminationStatus
    }

    private func record(_ state: UpdateRunState, error: String? = nil) {
        if let error { emit(error) }
        store.mutate {
            $0.run = UpdateRun(state: state, version: version, pid: ProcessInfo.processInfo.processIdentifier, error: error, log: logURL.path)
        }
    }

    private func emit(_ line: String) {
        write(Data((line + "\n").utf8))
    }

    private func write(_ data: Data) {
        try? logHandle?.write(contentsOf: data)
        if echo { FileHandle.standardOutput.write(data) }
    }
}

public enum UpdateLauncher {
    static var stagedTool: URL { GuruPaths.support.appendingPathComponent("updater/tgr") }

    /// install.sh deletes the bundle, so the updater runs from a copy of `tgr` outside it.
    public static func stage() throws -> URL {
        let bundled = GuruResources.bundleContents.appendingPathComponent("MacOS/tgr")
        let fm = FileManager.default
        try fm.createDirectory(at: stagedTool.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: stagedTool)
        try fm.copyItem(at: bundled, to: stagedTool)
        return stagedTool
    }

    public static func arguments(source: UpdateSource, version: String, echo: Bool) -> [String] {
        ["update", "--run", "--source", source.path, "--identity", source.identity, "--release", version] + (echo ? ["--echo"] : [])
    }

    /// The child survives the app: install.sh stops TermGuru by name, not by process group.
    @discardableResult
    public static func launchDetached(source: UpdateSource, version: String) throws -> Int32 {
        let process = Process()
        process.executableURL = try stage()
        process.arguments = arguments(source: source, version: version, echo: false)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }
}
