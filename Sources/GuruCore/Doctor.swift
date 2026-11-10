import Foundation

public struct DoctorCheck: Sendable, Identifiable {
    public enum Level: String, Sendable { case ok, warning, failure, info }
    public var level: Level
    public var title: String
    public var detail: String
    public var fix: String?

    public var id: String { title }
}

public enum Doctor {
    public static func run(parentShellPID: Int? = nil) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        func add(_ level: DoctorCheck.Level, _ title: String, _ detail: String = "", fix: String? = nil) {
            checks.append(DoctorCheck(level: level, title: title, detail: detail, fix: fix))
        }
        let fm = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        let status = AppControl.status()
        if let status {
            add(.ok, "App running", "pid \(status.pid)\(status.paused ? ", suggestions paused" : "")")
        } else {
            add(.failure, "App not running", "No answer on \(GuruPaths.socket.path)", fix: "tgr start")
        }

        let specCount = ((try? fm.contentsOfDirectory(atPath: GuruResources.specs.path)) ?? []).filter { $0.hasSuffix(".js") }.count
        specCount > 0
            ? add(.ok, "Completion specs", "\(specCount) commands")
            : add(.failure, "Completion specs missing", GuruResources.specs.path, fix: "Scripts/fetch-specs.sh && Scripts/install.sh")

        // Shells
        Installer.hasIntegration("zsh")
            ? add(.ok, "zsh integration", "~/.zshrc loads tgr")
            : add(.failure, "zsh integration missing", "~/.zshrc does not run `tgr init zsh`", fix: "tgr install")
        let zsh = Shell.run(["zsh", "--version"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !zsh.isEmpty { add(.info, "zsh version", zsh) }

        var modernBash: String?
        for candidate in ["/opt/homebrew/bin/bash", "/usr/local/bin/bash", "/bin/bash"] where fm.isExecutableFile(atPath: candidate) {
            let major = Shell.run([candidate, "-c", "echo $BASH_VERSINFO"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(major), value >= 4 { modernBash = "\(candidate) (v\(major))"; break }
        }
        if let modernBash {
            Installer.hasIntegration("bash")
                ? add(.ok, "bash integration", modernBash)
                : add(.warning, "bash integration missing", "~/.bashrc does not run `tgr init bash`", fix: "tgr install")
        } else {
            add(.warning, "bash too old", "Only system bash 3.2 found; completion needs bash 4 or newer.", fix: "brew install bash")
        }

        if let status, let parentShellPID {
            status.shellPIDs.contains(parentShellPID)
                ? add(.ok, "This shell is connected")
                : add(.warning, "This shell is not connected", "Open a new terminal tab after installing.", fix: "exec $SHELL")
        }

        for conflict in Installer.conflicts() {
            add(.warning, "Conflicting tool in ~/\(conflict.file)", conflict.line, fix: "tgr install --replace-others")
        }

        // JetBrains
        let ides = Installer.jetBrainsIDEs()
        if ides.isEmpty { add(.info, "JetBrains IDEs", "none found") }
        for ide in ides {
            ide.pluginInstalled
                ? add(.ok, "\(ide.name) caret plugin", "installed")
                : add(.warning, "\(ide.name) caret plugin missing", "Popup cannot follow the caret in this IDE.", fix: "tgr install")
        }
        if let status, ides.contains(where: \.pluginInstalled) {
            let running = Shell.run(["pgrep", "-f", "Contents/MacOS/(phpstorm|idea|webstorm|pycharm|goland|rubymine|clion|datagrip|rider)$"]).stdout
                .split(separator: "\n").compactMap { Int($0) }
            let disconnected = running.filter { !status.idePIDs.contains($0) }
            if !disconnected.isEmpty {
                add(.warning, "JetBrains IDE not connected", "pid \(disconnected.map(String.init).joined(separator: ", ")) started before the plugin was installed.", fix: "Restart the IDE")
            } else if !running.isEmpty {
                add(.ok, "JetBrains IDE connected", "pid \(running.map(String.init).joined(separator: ", "))")
            }
        }

        if let status {
            status.accessibility
                ? add(.ok, "Accessibility permission", "caret tracking outside JetBrains IDEs")
                : add(.warning, "Accessibility permission not granted", "Needed to find the caret in Terminal, iTerm and other terminals.",
                      fix: "System Settings › Privacy & Security › Accessibility › enable TermGuru")
        }

        if environment["TERM_PROGRAM"] == "WarpTerminal" {
            add(.warning, "Warp is not supported", "Warp replaces the shell's line editor, so no shell hook can see what you type.")
        }

        Shell.run(["sh", "-c", "command -v tgr"]).status == 0
            ? add(.ok, "tgr on PATH")
            : add(.warning, "tgr not on PATH", "", fix: "Add ~/.local/bin to PATH")

        Installer.launchesAtLogin
            ? add(.ok, "Starts at login")
            : add(.info, "Does not start at login", "", fix: "tgr install")
        return checks
    }
}
