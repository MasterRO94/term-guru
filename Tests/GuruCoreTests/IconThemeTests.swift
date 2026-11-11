import Foundation
import Testing
@testable import GuruCore

/// A few entries in the shape of material-icon-theme's `dist/material-icons.json`.
private func makeTheme() throws -> (IconTheme, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest: [String: Any] = [
        "file": "file",
        "folder": "folder",
        "iconDefinitions": Dictionary(uniqueKeysWithValues: [
            "file", "folder", "folder-src", "typescript", "typescript-def", "markdown", "readme", "tune",
            "docker", "nodejs", "git", "python", "zip", "lock", "next", "next_light", "makefile",
        ].map { ($0, ["iconPath": "./../icons/\($0).svg"]) }),
        "fileExtensions": ["ts": "typescript", "d.ts": "typescript-def", "md": "markdown", "env": "tune", "js": "next"],
        "fileNames": ["README.md": "readme", "Makefile": "makefile"],
        "folderNames": ["src": "folder-src"],
        "light": ["fileExtensions": ["md": "next_light"]],
    ]
    try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("material-icons.json"))
    return (try #require(IconTheme(directory: directory)), directory)
}

@Suite struct IconThemeTests {
    @Test func filesMatchNameThenLongestExtension() throws {
        let (theme, _) = try makeTheme()
        #expect(theme.file("readme.MD") == "readme")
        #expect(theme.file("Makefile") == "makefile")
        #expect(theme.file("index.d.ts") == "typescript-def")
        #expect(theme.file("app.ts") == "typescript")
        #expect(theme.file(".env") == "tune")
        #expect(theme.file("photo.unknown") == "file")
        #expect(theme.file("LICENSE") == "file")
    }

    @Test func foldersFallBackToTheDefault() throws {
        let (theme, _) = try makeTheme()
        #expect(theme.folder("src") == "folder-src")
        #expect(theme.folder("Src/") == "folder-src")
        #expect(theme.folder("..") == "folder")
    }

    @Test func lightAppearanceUsesLightVariants() throws {
        let (theme, _) = try makeTheme()
        #expect(theme.file("notes.md", light: true) == "next_light")
        #expect(theme.file("notes.md") == "markdown")
        #expect(theme.file("app.js", light: true) == "next_light")
    }

    @Test func commandsUseAliasesExactNamesButNotGenericIcons() throws {
        let (theme, _) = try makeTheme()
        #expect(theme.command("node") == "nodejs")
        #expect(theme.command("make") == "makefile")
        #expect(theme.command("docker") == "docker")
        #expect(theme.command("zip") == "zip")
        #expect(theme.command("lock") == nil)
        #expect(theme.command("ls") == nil)
    }

    @Test func figBrandTypesOnly() throws {
        let (theme, _) = try makeTheme()
        #expect(theme.fig("docker") == "docker")
        #expect(theme.fig("node") == "nodejs")
        #expect(theme.fig("string") == nil)
        #expect(theme.fig("git") == nil)
    }

    @Test func missingManifestGivesNoTheme() {
        #expect(IconTheme(directory: URL(fileURLWithPath: "/nonexistent")) == nil)
    }
}

@Suite struct CommandIconTests {
    private func request(_ line: String, bin: URL, aliases: [String: String] = [:]) -> EngineRequest {
        EngineRequest(buffer: line, cursor: line.count, cwd: "/", path: bin.path, aliases: aliases)
    }

    private func makeBin(_ box: Sandbox, _ names: String...) throws -> URL {
        let bin = box.root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in names {
            let url = bin.appendingPathComponent(name)
            try Data().write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return bin
    }

    @Test func commandsCarryNameAndSpecIcon() throws {
        let box = try Sandbox(["dock": #"{name:"dock",icon:"🐳"}"#, "plain": #"{name:"plain"}"#])
        let bin = try makeBin(box, "dock", "plain", "nospec")
        let items = box.engine.suggest(request("d", bin: bin)) + box.engine.suggest(request("p", bin: bin))
            + box.engine.suggest(request("nos", bin: bin))
        #expect(items.first { $0.name == "dock" }?.icon == .command("dock", fallback: .emoji("🐳")))
        #expect(items.first { $0.name == "plain" }?.icon == .command("plain", fallback: nil))
        #expect(items.first { $0.name == "nospec" }?.icon == .command("nospec", fallback: nil))
    }

    @Test func aliasesTakeTheirCommandsIcon() throws {
        let box = try Sandbox(["dock": #"{name:"dock",icon:"🐳"}"#])
        let bin = try makeBin(box)
        let items = box.engine.suggest(request("dk", bin: bin, aliases: ["dk": "dock ps -a"]))
        #expect(items.first { $0.name == "dk" }?.icon == .command("dock", fallback: .emoji("🐳")))
    }

    @Test func indexAnswersWithoutLoadingTheSpec() throws {
        // The spec says one icon, the index another: the index wins, so the spec was not loaded.
        let box = try Sandbox(["dock": #"{name:"dock",icon:"🐳"}"#])
        try JSONSerialization.data(withJSONObject: ["dock": "fig://icon?type=docker"])
            .write(to: box.specs.appendingPathComponent(SpecRuntime.iconIndexName))
        let bin = try makeBin(box, "dock")
        let item = box.engine.suggest(request("dock", bin: bin)).first { $0.name == "dock" }
        #expect(item?.icon == .command("dock", fallback: .fig("docker")))
    }
}
