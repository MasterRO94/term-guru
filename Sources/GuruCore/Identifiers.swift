import Foundation

public enum GuruID {
    public static let appBundle = "dev.termguru.app"
}

public enum GuruPaths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var support: URL {
        home.appendingPathComponent("Library/Application Support/TermGuru", isDirectory: true)
    }
    public static var run: URL { support.appendingPathComponent("run", isDirectory: true) }
    public static var socket: URL {
        // Overridable so integration tests can run a private headless instance.
        if let override = ProcessInfo.processInfo.environment["GURU_SOCKET"] { return URL(fileURLWithPath: override) }
        return run.appendingPathComponent("guru.sock")
    }
    public static var logs: URL { home.appendingPathComponent("Library/Logs/TermGuru", isDirectory: true) }
    public static var config: URL {
        if let override = ProcessInfo.processInfo.environment["GURU_CONFIG"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return home.appendingPathComponent(".config/term-guru", isDirectory: true)
    }
    public static var aliases: URL { config.appendingPathComponent("aliases.sh") }
    public static var settings: URL { config.appendingPathComponent("settings.json") }
    public static var installedApp: URL { home.appendingPathComponent("Applications/TermGuru.app", isDirectory: true) }
}
