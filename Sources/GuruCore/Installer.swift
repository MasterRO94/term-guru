import Foundation

public enum Installer {
    static let marker = "# TermGuru"
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static func rcFile(for shell: String) -> URL {
        home.appendingPathComponent(shell == "bash" ? ".bashrc" : ".zshrc")
    }

    // A stock macOS PATH lacks ~/.local/bin, where install.sh links tgr; without it the hook would skip silently.
    public static func initLine(for shell: String) -> String {
        #"case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac; command -v tgr >/dev/null 2>&1 && eval "$(tgr init \#(shell))" \#(marker)"#
    }

    public static func hasIntegration(_ shell: String) -> Bool {
        activeLines(in: rcFile(for: shell)).contains { $0.contains("tgr init \(shell)") }
    }

    static func activeLines(in file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }

    public enum IntegrationChange: Sendable { case added, updated, unchanged }

    /// Rewrites an older TermGuru init line in place, or appends one when none is active.
    static func integrated(_ text: String, shell: String) -> (text: String, change: IntegrationChange) {
        let line = initLine(for: shell)
        var lines = text.components(separatedBy: "\n")
        var change = IntegrationChange.added
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.contains("tgr init \(shell)") else { continue }
            guard trimmed.hasSuffix(marker), trimmed != line else { return (text, .unchanged) }
            lines[index] = line
            change = .updated
        }
        if change == .updated { return (lines.joined(separator: "\n"), .updated) }
        var appended = text
        if !appended.isEmpty, !appended.hasSuffix("\n") { appended += "\n" }
        return (appended + "\n" + line + "\n", .added)
    }

    @discardableResult
    public static func addIntegration(_ shell: String) throws -> IntegrationChange {
        let file = rcFile(for: shell)
        let result = integrated((try? String(contentsOf: file, encoding: .utf8)) ?? "", shell: shell)
        if result.change != .unchanged { try result.text.write(to: file, atomically: true, encoding: .utf8) }
        return result.change
    }

    @discardableResult
    public static func removeIntegration(_ shell: String) throws -> Bool {
        let file = rcFile(for: shell)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        let lines = text.components(separatedBy: "\n")
        let kept = lines.filter { !$0.contains("tgr init \(shell)") }
        guard kept.count != lines.count else { return false }
        try kept.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        return true
    }

    /// Other autocomplete tools hooked into the same shell fight over the same keys.
    public static func conflicts() -> [(file: String, line: String)] {
        let patterns = ["figxit", "kiro-cli init", "q init", "fig init", "amazon-q"]
        var found: [(String, String)] = []
        for name in [".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".profile"] {
            for line in activeLines(in: home.appendingPathComponent(name)) {
                let lower = line.lowercased()
                if patterns.contains(where: lower.contains) { found.append((name, line.trimmingCharacters(in: .whitespaces))) }
            }
        }
        return found
    }

    /// Comments out lines of conflicting tools; returns the lines it disabled.
    public static func disableConflicts() throws -> [String] {
        var disabled: [String] = []
        let conflicting = Set(conflicts().map(\.line))
        for name in [".zshrc", ".zprofile", ".bashrc", ".bash_profile", ".profile"] {
            let file = home.appendingPathComponent(name)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var changed = false
            let lines = text.components(separatedBy: "\n").map { line -> String in
                guard conflicting.contains(line.trimmingCharacters(in: .whitespaces)) else { return line }
                changed = true
                disabled.append("\(name): \(line)")
                return "# [disabled by TermGuru] " + line
            }
            if changed { try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8) }
        }
        return disabled
    }

    // MARK: JetBrains

    public struct IDE: Sendable {
        public var name: String
        public var pluginsDirectory: URL
        public var pluginInstalled: Bool
    }

    static var bundledPlugin: URL { GuruResources.root.appendingPathComponent("jetbrains/termguru-caret", isDirectory: true) }

    public static func jetBrainsIDEs() -> [IDE] {
        let base = home.appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return entries.sorted().compactMap { entry in
            // Config folders look like PhpStorm2026.2; anything else here is shared tooling.
            guard entry.range(of: #"^[A-Za-z]+20\d\d\.\d$"#, options: .regularExpression) != nil else { return nil }
            let plugins = base.appendingPathComponent(entry).appendingPathComponent("plugins", isDirectory: true)
            let installed = FileManager.default.fileExists(atPath: plugins.appendingPathComponent("termguru-caret/lib/termguru-caret.jar").path)
            return IDE(name: entry, pluginsDirectory: plugins, pluginInstalled: installed)
        }
    }

    public static func installPlugin(into ide: IDE) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: ide.pluginsDirectory, withIntermediateDirectories: true)
        let target = ide.pluginsDirectory.appendingPathComponent("termguru-caret")
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: bundledPlugin, to: target)
    }

    public static func removePlugin(from ide: IDE) throws {
        let target = ide.pluginsDirectory.appendingPathComponent("termguru-caret")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    public static var hasBundledPlugin: Bool {
        FileManager.default.fileExists(atPath: bundledPlugin.appendingPathComponent("lib/termguru-caret.jar").path)
    }

    // MARK: Login item

    static var launchAgent: URL { home.appendingPathComponent("Library/LaunchAgents/dev.termguru.app.plist") }

    public static var launchesAtLogin: Bool { FileManager.default.fileExists(atPath: launchAgent.path) }

    public static func setLaunchAtLogin(_ enabled: Bool) throws {
        let fm = FileManager.default
        if !enabled {
            if fm.fileExists(atPath: launchAgent.path) { try fm.removeItem(at: launchAgent) }
            return
        }
        let plist: [String: Any] = [
            "Label": "dev.termguru.app",
            "ProgramArguments": ["/usr/bin/open", "-g", GuruPaths.installedApp.path],
            "RunAtLoad": true,
        ]
        try fm.createDirectory(at: launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgent)
    }
}
