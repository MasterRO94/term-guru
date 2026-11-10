import Foundation
import Testing
@testable import GuruCore

@Suite struct InstallerTests {
    static let legacyLine = #"command -v tgr >/dev/null 2>&1 && eval "$(tgr init zsh)" # TermGuru"#

    @Test func appendsToEmptyFile() {
        let result = Installer.integrated("", shell: "zsh")
        #expect(result.change == .added)
        #expect(result.text == "\n" + Installer.initLine(for: "zsh") + "\n")
    }

    @Test func upgradesLegacyLineInPlace() {
        let text = "export A=1\n\(Self.legacyLine)\nexport B=2\n"
        let result = Installer.integrated(text, shell: "zsh")
        #expect(result.change == .updated)
        #expect(result.text == "export A=1\n\(Installer.initLine(for: "zsh"))\nexport B=2\n")
    }

    @Test func leavesCurrentLineAlone() {
        let text = "x\n\(Installer.initLine(for: "zsh"))\n"
        let result = Installer.integrated(text, shell: "zsh")
        #expect(result.change == .unchanged)
        #expect(result.text == text)
    }

    @Test func leavesHandWrittenHookAlone() {
        let text = #"eval "$(~/bin/tgr init zsh)""# + "\n"
        #expect(Installer.integrated(text, shell: "zsh").change == .unchanged)
    }

    @Test func ignoresCommentedLegacyLine() {
        let text = "# \(Self.legacyLine)\n"
        let result = Installer.integrated(text, shell: "zsh")
        #expect(result.change == .added)
        #expect(result.text.hasPrefix(text))
    }

    @Test func onlyCurrentActiveLineAddsCLIToPath() {
        let current = Installer.initLine(for: "zsh")
        #expect(Installer.addsCLIToPath(text: "x\n  \(current)\n", shell: "zsh"))
        #expect(!Installer.addsCLIToPath(text: "\(Self.legacyLine)\n", shell: "zsh"))
        #expect(!Installer.addsCLIToPath(text: "# \(current)\n", shell: "zsh"))
        #expect(!Installer.addsCLIToPath(text: "\(current)\n", shell: "bash"))
    }

    @Test func initLinePutsLocalBinOnPath() throws {
        for shell in ["zsh", "bash"] {
            let output = try run(shell, Installer.initLine(for: shell).replacingOccurrences(of: "&& eval", with: "&& echo") + "\necho \"$PATH\"")
            #expect(output.contains("/.local/bin:/usr/bin:/bin"))
            let again = try run(shell, "PATH=\"$HOME/.local/bin:/usr/bin:/bin\"\n" + Installer.initLine(for: shell).replacingOccurrences(of: "&& eval", with: "&& echo") + "\necho \"$PATH\"")
            #expect(again.components(separatedBy: ".local/bin").count == 2)
        }
    }

    private func run(_ shell: String, _ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/\(shell)")
        process.arguments = ["-f", "-c", script].filter { shell == "zsh" || $0 != "-f" }
        process.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
