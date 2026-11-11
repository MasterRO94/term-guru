import Foundation
import Testing
@testable import GuruCore

/// Engine runs against small inline specs in a temporary directory, with no shell history.
final class Sandbox {
    let root: URL
    let specs: URL
    let cwd: URL
    let engine: Engine

    init(_ specFiles: [String: String], history: [String] = []) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let specs = root.appendingPathComponent("specs")
        self.root = root
        self.specs = specs
        cwd = root.appendingPathComponent("cwd")
        let fm = FileManager.default
        try fm.createDirectory(at: specs, withIntermediateDirectories: true)
        try fm.createDirectory(at: cwd, withIntermediateDirectories: true)
        for (name, body) in specFiles {
            try "var spec=\(body);export{spec as default};".write(to: specs.appendingPathComponent("\(name).js"), atomically: true, encoding: .utf8)
        }
        let historyFile = root.appendingPathComponent("history")
        try history.joined(separator: "\n").write(to: historyFile, atomically: true, encoding: .utf8)
        engine = Engine(specs: SpecRuntime(directories: [specs]), history: HistoryStore(files: [historyFile]))
        engine.useHistory = false
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func suggest(_ line: String) -> [Suggestion] {
        engine.suggest(EngineRequest(buffer: line, cursor: line.count, cwd: cwd.path, path: ""))
    }

    func names(_ line: String) -> [String] { suggest(line).map(\.name) }

    func touch(_ paths: String...) throws {
        for path in paths {
            let url = cwd.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data().write(to: url)
            }
        }
    }
}

@Suite struct OptionRuleTests {
    static let spec = """
    {name:"x",options:[
      {name:["-v","--verbose"]},
      {name:"--quiet",exclusiveOn:["--verbose"]},
      {name:"--porcelain"},
      {name:"--porcelain-v2",dependsOn:["--porcelain"]},
      {name:"--long-format",dependsOn:["-l","--long"]},
      {name:["-l","--long"]}
    ]}
    """

    @Test func exclusiveOnHidesConflictsByAnyAlias() throws {
        let box = try Sandbox(["x": Self.spec])
        #expect(box.names("x --").contains("--quiet"))
        #expect(!box.names("x --verbose --").contains("--quiet"))
        #expect(!box.names("x -v --").contains("--quiet"))
    }

    @Test func usedOptionHidesAllItsAliases() throws {
        let box = try Sandbox(["x": Self.spec])
        let names = box.names("x -v -")
        #expect(!names.contains("-v") && !names.contains("--verbose"))
    }

    @Test func dependsOnWaitsForItsOption() throws {
        let box = try Sandbox(["x": Self.spec])
        #expect(!box.names("x --").contains("--porcelain-v2"))
        #expect(box.names("x --porcelain --").contains("--porcelain-v2"))
        #expect(!box.names("x --").contains("--long-format"))
        #expect(box.names("x -l --").contains("--long-format"))
    }
}

@Suite struct GeneratorTests {
    /// Each run bumps a counter; the name matches the typed words so the fuzzy filter keeps it.
    static func counting(_ extra: String) -> String {
        """
        {name:"x",args:{generators:{\(extra)custom:async()=>{globalThis.calls=(globalThis.calls||0)+1;return[{name:"src/abc/#",description:String(globalThis.calls)}]}}}}
        """
    }

    private func runs(_ box: Sandbox, _ line: String) -> String? {
        box.suggest(line).first { $0.name == "src/abc/#" }?.description
    }

    @Test func stringTriggerRerunsOnNewPathLevel() throws {
        let box = try Sandbox(["x": Self.counting(#"trigger:"/","#)])
        #expect(runs(box, "x src/a") == "1")
        #expect(runs(box, "x src/ab") == "1")
        #expect(runs(box, "x src/ab/") == "2")
        #expect(runs(box, "x src/ab/") == "2")
    }

    @Test func functionAndObjectTriggers() throws {
        let function = try Sandbox(["x": Self.counting("trigger:(n,o)=>n.length>o.length+1,")])
        #expect(runs(function, "x s") == "1")
        #expect(runs(function, "x sr") == "1")
        #expect(runs(function, "x src") == "2")

        let change = try Sandbox(["x": Self.counting(#"trigger:{on:"change"},"#)])
        #expect(runs(change, "x s") == "1")
        #expect(runs(change, "x s") == "1")
        #expect(runs(change, "x sr") == "2")

        let threshold = try Sandbox(["x": Self.counting(#"trigger:{on:"threshold",length:2},"#)])
        #expect(runs(threshold, "x s") == "1")
        #expect(runs(threshold, "x src") == "1")
        #expect(runs(threshold, "x src/") == "2")
    }

    @Test func specTTLOutlivesTheDefault() throws {
        let box = try Sandbox(["x": Self.counting("cache:{ttl:60000},"), "y": Self.counting("").replacingOccurrences(of: "\"x\"", with: "\"y\"")])
        var clock = Date()
        box.engine.now = { clock }
        #expect(runs(box, "x s") == "1")
        #expect(runs(box, "y s") == "2")
        clock += 10
        #expect(runs(box, "x s") == "1")
        #expect(runs(box, "y s") == "3")
        clock += 55
        #expect(runs(box, "x s") == "4")
    }

    @Test func staleWhileRevalidateServesStaleThenRefreshes() throws {
        let box = try Sandbox(["x": Self.counting(#"cache:{strategy:"stale-while-revalidate",ttl:1000},"#)])
        var clock = Date()
        box.engine.now = { clock }
        #expect(runs(box, "x s") == "1")
        clock += 2
        #expect(runs(box, "x s") == "1")
        box.engine.refreshStale()
        #expect(runs(box, "x s") == "2")
    }

    @Test func cacheKeepsDirectoriesApart() throws {
        let box = try Sandbox(["x": Self.counting(#"cache:{ttl:60000,cacheByDirectory:false},"#)])
        #expect(runs(box, "x s") == "1")
        let other = box.root.path
        let items = box.engine.suggest(EngineRequest(buffer: "x s", cursor: 3, cwd: other, path: ""))
        #expect(items.first { $0.name == "src/abc/#" }?.description == "2")
    }
}

@Suite struct TemplateTests {
    @Test func filterTemplateSuggestionsKeepsWhatItReturns() throws {
        let box = try Sandbox(["x": #"{name:"x",args:{generators:{template:"filepaths",filterTemplateSuggestions:s=>s.filter(f=>f.name.endsWith(".json")).map(f=>({...f,priority:f.name==="b.json"?90:false}))}}}"#])
        try box.touch("a.json", "b.json", "c.txt", "sub/")
        let items = box.suggest("x ")
        #expect(items.map(\.name) == ["b.json", "a.json"])
        #expect(items[0].priority == 90)
        #expect(items[1].priority == 45)
    }

    @Test func helpListsSiblingSubcommands() throws {
        let box = try Sandbox(["x": #"{name:"x",subcommands:[{name:"build",description:"Build it"},{name:"run"},{name:"secret",hidden:true},{name:"help",args:{template:"help"}}]}"#])
        let items = box.suggest("x help ")
        #expect(Set(items.map(\.name)) == ["build", "run", "help"])
        #expect(items.allSatisfy { $0.kind == .subcommand })
        #expect(items.first { $0.name == "build" }?.description == "Build it")
    }

    /// Real shape: an optional `help` argument beside options, and a nested one from `generateSpec` (`cargo deny help`).
    @Test func helpWithOptionalArgAndGeneratedSubcommands() throws {
        let box = try Sandbox(["x": #"""
        {name:"x",options:[{name:"--color"},{name:"-Z"}],subcommands:[
          {name:"build",description:"Compile"},{name:"bench"},
          {name:"help",args:{template:"help",isOptional:true},options:[{name:"--config"}]}],
         generateSpec:async()=>({name:"x",subcommands:[{name:"deny",subcommands:[
          {name:"check"},{name:"fetch"},{name:"help",args:{template:"help",isOptional:true}}]}]})}
        """#])
        let items = box.suggest("x help ")
        let subcommands = items.filter { $0.kind == .subcommand }.map(\.name)
        #expect(Set(subcommands) == ["build", "bench", "help", "deny"])
        #expect(items.first?.kind == .subcommand)
        #expect(box.names("x help b").sorted() == ["bench", "build"])
        #expect(Set(box.suggest("x deny help ").filter { $0.kind == .subcommand }.map(\.name)) == ["check", "fetch", "help"])
    }

    @Test func historyListsEarlierArguments() throws {
        let box = try Sandbox(
            ["ssh": #"{name:"ssh",args:{generators:{template:"history"}}}"#],
            history: ["ssh me@box", "ls", "ssh -p 22 deploy@prod", "sshfs nope"]
        )
        let items = box.suggest("ssh ")
        #expect(items.contains { $0.name == "me@box" && $0.kind == .history })
        #expect(items.contains { $0.name == "deploy@prod" })
        #expect(!items.contains { $0.name == "nope" || $0.name == "-p" })
        #expect(box.names("ssh de") == ["deploy@prod"])
    }
}

@Suite struct IconTests {
    @Test func parsesEachForm() {
        #expect(SuggestionIcon.parse("⭐️") == .emoji("⭐️"))
        #expect(SuggestionIcon.parse("\u{1F4E6}") == .emoji("📦"))
        #expect(SuggestionIcon.parse("fig://icon?type=git") == .fig("git"))
        #expect(SuggestionIcon.parse("fig://template?color=2ecc71&badge=🔥") == .template(color: "2ecc71", badge: "🔥"))
        #expect(SuggestionIcon.parse("fig://template?badge=%F0%9F%91%A4") == .template(color: nil, badge: "👤"))
        #expect(SuggestionIcon.parse("fig://path/Sources/") == .folder("Sources"))
        #expect(SuggestionIcon.parse("fig://path/a/README.md") == .file("README.md"))
    }

    @Test func remoteAndEmptyGiveNil() {
        #expect(SuggestionIcon.parse("https://raw.githubusercontent.com/expo/expo-cli/master/assets/fig/true.png") == nil)
        #expect(SuggestionIcon.parse("") == nil)
        #expect(SuggestionIcon.parse("fig://icon?") == nil)
        #expect(SuggestionIcon.parse("not an icon") == nil)
    }

    @Test func specIconsReachSuggestions() throws {
        let box = try Sandbox(["x": #"{name:"x",subcommands:[{name:"go",icon:"fig://icon?type=command"}],options:[{name:"--star",icon:"⭐️"}],args:{suggestions:[{name:"pkg",icon:"📦"},{name:"far",icon:"https://example.com/a.png"}]}}"#])
        let items = box.suggest("x ")
        #expect(items.first { $0.name == "go" }?.icon == .fig("command"))
        #expect(items.first { $0.name == "pkg" }?.icon == .emoji("📦"))
        #expect(items.first { $0.name == "far" }?.icon == nil)
        #expect(box.suggest("x --").first { $0.name == "--star" }?.icon == .emoji("⭐️"))
    }

    @Test func filesCarryTheirName() throws {
        let box = try Sandbox([:])
        try box.touch("README.md", "Makefile", "docs/")
        let items = FileSuggestions.list(partial: "", rawPartial: "", cwd: box.cwd.path, foldersOnly: false).items
        #expect(items.first { $0.name == "README.md" }?.icon == .file("README.md"))
        #expect(items.first { $0.name == "Makefile" }?.icon == .file("Makefile"))
        #expect(items.first { $0.name == "docs" }?.icon == .folder("docs"))
    }

    static let gitSpec = GuruResources.specs.appendingPathComponent("git.js")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: gitSpec.path), "needs Resources/specs (Scripts/fetch-specs.sh)"))
    func currentGitBranchHasStar() throws {
        let box = try Sandbox([:])
        for argv in [["init", "-q", "-b", "trunk"], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"], ["branch", "side"]] {
            #expect(Shell.run(["git"] + argv, cwd: box.cwd.path, environment: ProcessInfo.processInfo.environment, timeout: 5).status == 0)
        }
        let engine = Engine(specs: SpecRuntime(directories: [GuruResources.specs]), history: HistoryStore(files: []))
        let items = engine.suggest(EngineRequest(buffer: "git checkout ", cursor: 13, cwd: box.cwd.path, path: ProcessInfo.processInfo.environment["PATH"] ?? ""))
        #expect(items.first { $0.name == "trunk" }?.icon == .emoji("⭐️"))
        #expect(items.first { $0.name == "side" }?.icon != .emoji("⭐️"))
    }
}

@Suite struct ParentFolderTests {
    @Test func listsNextLevelsWithResolvedPaths() throws {
        let box = try Sandbox([:])
        try box.touch("a/b/")
        let cwd = box.cwd.appendingPathComponent("a/b").path
        let items = FileSuggestions.list(partial: "../", rawPartial: "../", cwd: cwd, foldersOnly: true).items
        let up2 = try #require(items.first { $0.name == "../../" })
        #expect(up2.description == box.cwd.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        #expect(up2.insert == "../../" && up2.replace == 3 && up2.priority == 44)
        #expect(!items.contains { $0.name == "../" })
        #expect(items.filter { $0.name.hasPrefix("../") }.count <= FileSuggestions.parentLevels - 1)
    }

    @Test func stopsAtRootAndOnlyForFolderLists() {
        #expect(FileSuggestions.parents(partial: "", replace: 0, cwd: "/").isEmpty)
        #expect(FileSuggestions.parents(partial: "..", replace: 2, cwd: "/usr").map(\.name) == ["../"])
        #expect(FileSuggestions.parents(partial: "", replace: 0, cwd: "/a/b/c/d/e/f/g").count == 5)
        #expect(FileSuggestions.parents(partial: "src", replace: 3, cwd: "/a/b").isEmpty)
        #expect(FileSuggestions.parents(partial: "", replace: 0, cwd: NSHomeDirectory() + "/x").first?.description == "~")
        #expect(!FileSuggestions.list(partial: "", rawPartial: "", cwd: "/usr", foldersOnly: false).items.contains { $0.name == "../" })
    }
}

@Suite struct SettingsTests {
    @Test func detailsPositionRoundTripsAndDefaultsToSide() throws {
        var settings = GuruSettings()
        settings.detailsPosition = .below
        let decoded = try JSONDecoder().decode(GuruSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.detailsPosition == .below)
        let old = try JSONDecoder().decode(GuruSettings.self, from: Data(#"{"maxRows":10,"showDetails":true}"#.utf8))
        #expect(old.detailsPosition == .side && old.maxRows == 10)
        #expect(DetailsPosition.side.toggled == .below && DetailsPosition.below.toggled == .side)
    }
}
