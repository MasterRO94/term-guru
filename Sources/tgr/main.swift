import ArgumentParser
import Foundation
import GuruCore

struct Guru: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tgr",
        abstract: "TermGuru: autocomplete popup for your terminal.",
        version: GuruVersion.current,
        subcommands: [
            Doctor.self, Rescan.self, Alias.self, Install.self, Uninstall.self,
            Settings.self, Start.self, Stop.self, Restart.self, Status.self, Logs.self, Specs.self, Update.self,
            Init.self, Complete.self, Relay.self, FigSpec.self, SpecIcons.self,
        ]
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("tgr: \(message)\n".utf8))
    Foundation.exit(1)
}

enum Style {
    static let color = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    static func paint(_ text: String, _ code: String) -> String { color ? "\u{1b}[\(code)m\(text)\u{1b}[0m" : text }
    static func green(_ text: String) -> String { paint(text, "32") }
    static func yellow(_ text: String) -> String { paint(text, "33") }
    static func red(_ text: String) -> String { paint(text, "31") }
    static func dim(_ text: String) -> String { paint(text, "2") }
    static func bold(_ text: String) -> String { paint(text, "1") }
}

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the shell integration loader. Use: eval \"$(tgr init zsh)\"")

    @Argument(help: "zsh or bash", completion: .list(["zsh", "bash"])) var shell: String

    func run() {
        guard ["zsh", "bash"].contains(shell) else { fail("unsupported shell '\(shell)' (zsh, bash)") }
        let script = GuruResources.shell.appendingPathComponent("guru.\(shell)").path
        print("source '\(script.replacingOccurrences(of: "'", with: "'\\''"))'")
    }
}

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check the installation and explain how to fix problems.")

    func run() {
        let checks = GuruCore.Doctor.run(parentShellPID: Int(getppid()))
        for check in checks {
            let mark: String
            switch check.level {
            case .ok: mark = Style.green("✓")
            case .warning: mark = Style.yellow("!")
            case .failure: mark = Style.red("✗")
            case .info: mark = Style.dim("·")
            }
            print("\(mark) \(check.title)\(check.detail.isEmpty ? "" : Style.dim("  \(check.detail)"))")
            if let fix = check.fix, check.level != .ok { print("    \(Style.dim("fix:")) \(fix)") }
        }
        let failures = checks.filter { $0.level == .failure }.count
        let warnings = checks.filter { $0.level == .warning }.count
        print("")
        print(failures + warnings == 0 ? Style.green("Everything looks good.") : "\(failures) problem(s), \(warnings) warning(s).")
        if failures > 0 { Foundation.exit(1) }
    }
}

struct Rescan: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Reload commands on PATH, history and specs (after installing new tools).")

    func run() {
        guard AppControl.request(["rescan"], timeout: 10) == "ok" else { fail("app is not running (tgr start)") }
        print("Rescanned. Aliases refresh on your next prompt.")
    }
}

struct Alias: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create and manage aliases that load in every shell.",
        subcommands: [Add.self, List.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "tgr alias add gs 'git status'   |   tgr alias add gs --last")

        @Argument(help: "Alias name, or name=command.") var name: String
        @Argument(parsing: .captureForPassthrough, help: "Command the alias runs.") var command: [String] = []
        @Flag(help: "Use the previous command from shell history.") var last = false

        func run() {
            var name = name
            var value = command.joined(separator: " ")
            if let eq = name.firstIndex(of: "="), value.isEmpty {
                value = String(name[name.index(after: eq)...])
                name = String(name[..<eq])
            }
            if last || value == "--last" {
                guard let previous = HistoryStore().lines.first(where: { !$0.hasPrefix("tgr ") }) else {
                    fail("no previous command found in history")
                }
                value = previous
            }
            guard !value.isEmpty else { fail("missing command. Example: tgr alias add gs 'git status'") }
            do { try AliasStore().add(name: name, value: value) } catch { fail("\(error)") }
            print("alias \(Style.bold(name))='\(value)'  \(Style.dim("(active from your next prompt)"))")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List aliases created with guru.")

        @Flag(help: "Print only the names, one per line.") var names = false

        func run() {
            let entries = AliasStore().list()
            if names { entries.forEach { print($0.name) }; return }
            if entries.isEmpty { print("No aliases yet. Try: tgr alias add gs 'git status'"); return }
            let width = entries.map(\.name.count).max() ?? 0
            for entry in entries {
                print("\(Style.bold(entry.name.padding(toLength: width, withPad: " ", startingAt: 0)))  \(entry.value)")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "rm", abstract: "Remove an alias.")

        @Argument(completion: .shellCommand("tgr alias list --names")) var name: String

        func run() {
            do { try AliasStore().remove(name: name) } catch { fail("\(error)") }
            print("Removed \(name). Open shells keep it until you run: unalias \(name)")
        }
    }
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Hook into zsh/bash, install the JetBrains plugin, start at login.")

    @Flag(help: "Comment out other autocomplete tools (Figxit, Kiro CLI) in shell rc files.") var replaceOthers = false

    func run() {
        for shell in ["zsh", "bash"] {
            do {
                let verb = switch try Installer.addIntegration(shell) {
                case .added: "added to"
                case .updated: "updated in"
                case .unchanged: "already in"
                }
                print("\(Style.green("✓")) \(shell): \(verb) ~/\(Installer.rcFile(for: shell).lastPathComponent)")
            } catch { print("\(Style.red("✗")) \(shell): \(error.localizedDescription)") }
        }
        if replaceOthers {
            for line in (try? Installer.disableConflicts()) ?? [] { print("\(Style.yellow("!")) disabled \(line)") }
        } else {
            for conflict in Installer.conflicts() {
                print("\(Style.yellow("!")) ~/\(conflict.file) still loads another tool: \(conflict.line)")
                print("    rerun with --replace-others to comment it out")
            }
        }
        if Installer.hasBundledPlugin {
            for ide in Installer.jetBrainsIDEs() {
                do {
                    try Installer.installPlugin(into: ide)
                    print("\(Style.green("✓")) \(ide.name): caret plugin installed \(Style.dim("(restart the IDE)"))")
                } catch { print("\(Style.red("✗")) \(ide.name): \(error.localizedDescription)") }
            }
        } else {
            print("\(Style.yellow("!")) JetBrains plugin not bundled in this build")
        }
        do {
            try Installer.setLaunchAtLogin(true)
            print("\(Style.green("✓")) starts at login")
        } catch { print("\(Style.red("✗")) login item: \(error.localizedDescription)") }
        print(AppControl.start() ? "\(Style.green("✓")) app running" : "\(Style.red("✗")) could not start the app")
        print("\nOpen a new terminal tab, then run: tgr doctor")
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove shell hooks, JetBrains plugin and login item.")

    func run() {
        for shell in ["zsh", "bash"] where (try? Installer.removeIntegration(shell)) == true {
            print("removed from ~/\(Installer.rcFile(for: shell).lastPathComponent)")
        }
        for ide in Installer.jetBrainsIDEs() where ide.pluginInstalled {
            try? Installer.removePlugin(from: ide)
            print("removed plugin from \(ide.name)")
        }
        try? Installer.setLaunchAtLogin(false)
        AppControl.stop()
        print("Done. Delete \(GuruPaths.installedApp.path) and ~/.local/bin/tgr to finish.")
    }
}

struct Settings: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open the settings window.")
    func run() {
        guard AppControl.start(), AppControl.request(["settings"]) == "ok" else { fail("app is not running") }
    }
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start the app.")
    func run() {
        guard AppControl.start() else { fail("could not start TermGuru.app") }
        print("running")
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Quit the app.")
    func run() { AppControl.stop(); print("stopped") }
}

struct Restart: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Restart the app.")
    func run() {
        AppControl.stop()
        usleep(600_000)
        guard AppControl.start() else { fail("could not start TermGuru.app") }
        print("running")
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Install the newest release: pull the source, rebuild and reinstall.")

    @Flag(help: "Only report whether a newer release exists.") var check = false
    @Flag(name: .customLong("run"), help: .hidden) var detached = false
    @Flag(help: .hidden) var echo = false
    @Option(help: .hidden) var source: String?
    @Option(help: .hidden) var identity: String = "-"
    @Option(help: .hidden) var release: String?

    func run() {
        if detached {
            guard let source, let release else { fail("--run needs --source and --release") }
            let runner = UpdateRunner(source: UpdateSource(path: source, identity: identity), version: release, echo: echo)
            Foundation.exit(runner.run() ? 0 : 1)
        }
        guard SemVer.normalize(GuruVersion.current) != nil else { fail("this is a development build; run Scripts/install.sh") }
        let resolved = UpdateSource.resolve()
        guard let checkout = resolved.source else { fail(resolved.reason ?? "source checkout not found") }
        let latest: String
        switch LatestRelease.fetch(from: checkout) {
        case .found(let version): latest = version
        case .noReleases: fail("origin has no release tags")
        case .unreachable(let reason): fail("could not reach origin\(reason.isEmpty ? "" : ": \(reason)")")
        }
        UpdateStore().mutate { $0.latest = latest; $0.checkedAt = Date() }
        print("installed \(GuruVersion.current)\nlatest    \(latest)")
        guard SemVer.isNewer(latest, than: GuruVersion.current) else { print("up to date"); return }
        if check { print("run `tgr update` to install it"); return }
        if let busy = UpdateStore().currentRun(), busy.state.isBusy { fail("an update to \(busy.version) is already running") }

        let tool: URL
        do { tool = try UpdateLauncher.stage() } catch { fail("could not stage the updater: \(error)") }
        let arguments = [tool.path] + UpdateLauncher.arguments(source: checkout, version: latest, echo: true)
        var argv = arguments.map { strdup($0) } + [nil]
        execv(tool.path, &argv)
        fail("could not start the updater: \(String(cString: strerror(errno)))")
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show what is connected to the app.")

    func run() {
        guard let status = AppControl.status() else { print("not running"); Foundation.exit(1) }
        print("app        pid \(status.pid)\(status.paused ? " (paused)" : "")")
        print("shells     \(status.shellPIDs.isEmpty ? "none" : status.shellPIDs.map(String.init).joined(separator: ", "))")
        print("IDEs       \(status.idePIDs.isEmpty ? "none" : status.idePIDs.map(String.init).joined(separator: ", "))")
        print("popup      \(status.popupVisible ? "visible" : "hidden")")
        if let caret = AppControl.request(["caret"], timeout: 1) { print("IDE caret  \(caret)") }
    }
}

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show recent log lines.")

    @Option(name: .shortAndLong) var lines: Int = 40

    func run() {
        let file = GuruPaths.logs.appendingPathComponent("app.log")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { print("no log at \(file.path)"); return }
        print(text.split(separator: "\n").suffix(lines).joined(separator: "\n"))
    }
}

struct Specs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List commands that have completion specs.")

    @Argument(help: "Filter by name.") var filter: String?

    @Flag(help: "Show the directory each spec loads from.") var source = false

    func run() {
        let specs = SpecRuntime(directories: GuruResources.specDirectories).commandNames()
            .filter { name, _ in filter.map(name.contains) ?? true }
        for name in specs.keys.sorted() {
            print(source ? "\(name)  \(Style.dim(specs[name]!.path))" : name)
        }
        guard filter == nil else { return }
        print(Style.dim("\(specs.count) specs from, in lookup order:"))
        for directory in GuruResources.specDirectories { print(Style.dim("  \(directory.path)")) }
    }
}

struct Complete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print suggestions for a command line (debugging aid).")

    @Argument(help: "Text left of the cursor.") var line: String
    @Option(help: "Directory holding compiled specs, instead of the usual ones.", completion: .directory) var specs: String?
    @Option var limit: Int = 12
    @Flag(help: "Show which theme icon each row gets.") var icons = false

    func run() {
        let directories = specs.map { [URL(fileURLWithPath: $0)] } ?? GuruResources.specDirectories
        let engine = Engine(specs: SpecRuntime(directories: directories))
        let request = EngineRequest(
            buffer: line, cursor: line.count, cwd: FileManager.default.currentDirectoryPath,
            path: ProcessInfo.processInfo.environment["PATH"] ?? ""
        )
        let theme = icons ? IconTheme(directory: GuruResources.icons) : nil
        let start = Date()
        let items = engine.suggest(request)
        for item in items.prefix(limit) {
            let name = item.display.padding(toLength: 34, withPad: " ", startingAt: 0)
            let icon = icons ? Self.describe(item.icon, theme: theme).padding(toLength: 24, withPad: " ", startingAt: 0) + " " : ""
            print("\(item.kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(icon)\(name) \(item.description.prefix(60))")
        }
        print(String(format: "%d items, %.0f ms", items.count, Date().timeIntervalSince(start) * 1000))
    }

    /// Mirrors the popup's order: a theme logo, else the spec's icon, else the row kind's symbol.
    static func describe(_ icon: SuggestionIcon?, theme: IconTheme?) -> String {
        switch icon {
        case let .emoji(text)?: return text
        case let .template(color, badge)?: return "template \(color ?? "-") \(badge ?? "")"
        case let .fig(type)?: return theme?.fig(type).map { "theme:\($0)" } ?? "fig:\(type)"
        case let .file(name)?: return theme.map { "theme:\($0.file(name))" } ?? "file"
        case let .folder(name)?: return theme.map { "theme:\($0.folder(name))" } ?? "folder"
        case let .command(name, fallback)?:
            return theme?.command(name).map { "theme:\($0)" } ?? describe(fallback, theme: theme)
        case nil: return "-"
        }
    }
}

/// bash cannot open unix sockets itself, so its integration talks through this pipe.
struct Relay: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "_relay", shouldDisplay: false)

    func run() {
        guard let client = SocketClient() else { Foundation.exit(1) }
        signal(SIGPIPE, SIG_IGN)
        var descriptors = [
            pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
            pollfd(fd: client.fd, events: Int16(POLLIN), revents: 0),
        ]
        var buffer = [UInt8](repeating: 0, count: 65536)
        while poll(&descriptors, 2, -1) >= 0 {
            for (index, target) in [(0, client.fd), (1, STDOUT_FILENO)] {
                let events = Int32(descriptors[index].revents)
                guard events & (POLLIN | POLLHUP | POLLERR) != 0 else { continue }
                let count = read(descriptors[index].fd, &buffer, buffer.count)
                guard count > 0 else { Foundation.exit(0) }
                var offset = 0
                while offset < count {
                    let written = buffer.withUnsafeBytes { write(target, $0.baseAddress! + offset, count - offset) }
                    guard written > 0 else { Foundation.exit(0) }
                    offset += written
                }
            }
        }
    }
}

Guru.main()

/// Scripts/build.sh pipes `tgr --experimental-dump-help` through this to produce the bundled tgr spec.
struct FigSpec: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "_fig-spec", shouldDisplay: false)

    func run() throws {
        print(try ToolInfoSpec.module(fromDumpHelp: FileHandle.standardInput.readDataToEndOfFile()), terminator: "")
    }
}

/// Scripts/build.sh writes this index into the specs directory, so command names get their spec's icon
/// without loading every spec while the user types.
struct SpecIcons: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "_spec-icons", shouldDisplay: false)

    @Argument(help: "Directory of compiled specs.", completion: .directory) var directory: String

    func run() throws {
        let runtime = SpecRuntime(directories: [URL(fileURLWithPath: directory)])
        var icons: [String: String] = [:]
        for name in runtime.commandNames().keys {
            if let icon = runtime.spec(named: name)?.iconSource { icons[name] = icon }
        }
        let data = try JSONSerialization.data(withJSONObject: icons, options: [.sortedKeys, .prettyPrinted])
        print(String(decoding: data, as: UTF8.self))
    }
}
