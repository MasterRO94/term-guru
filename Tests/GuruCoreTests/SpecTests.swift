import Foundation
import Testing
@testable import GuruCore

@Suite struct SpecLoaderTests {
    @Test func acceptsNamedAndDefaultExports() {
        #expect(SpecRuntime.scriptBody(module: "var e={name:\"a\"};export{e as default};") == "var e={name:\"a\"};;return e;")
        #expect(SpecRuntime.scriptBody(module: "const s = {};\nexport { x as y, s as default };\n") == "const s = {};\n;return s;")
        #expect(SpecRuntime.scriptBody(module: "const s = {};\nexport default s;\n") == "const s = {};\n;return s;\n")
        #expect(SpecRuntime.scriptBody(module: "var e={};export{e as other};") == nil)
        #expect(SpecRuntime.scriptBody(module: "var e={};") == nil)
    }

    @Test func earlierDirectoryOverridesLater() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let user = root.appendingPathComponent("user"), bundled = root.appendingPathComponent("bundled")
        try write("var s={name:\"x\",description:\"bundled\"};export{s as default};", to: bundled.appendingPathComponent("x.js"))
        try write("var s={name:\"y\"};export default s;", to: bundled.appendingPathComponent("y.js"))
        try write("const s = { name: \"x\", description: \"mine\" };\nexport default s;\n", to: user.appendingPathComponent("x.js"))

        let runtime = SpecRuntime(directories: [user, bundled])
        #expect(runtime.spec(named: "x")?.description == "mine")
        #expect(runtime.spec(named: "y")?.name == "y")
        #expect(runtime.spec(named: "z") == nil)
        #expect(runtime.commandNames() == ["x": user, "y": bundled])
    }

    @Test func rejectsPathsOutsideTheDirectories() {
        let runtime = SpecRuntime(directories: [FileManager.default.temporaryDirectory])
        #expect(runtime.fileURL(for: "../etc/passwd") == nil)
        #expect(runtime.fileURL(for: "/etc/passwd") == nil)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

@Suite struct ToolInfoSpecTests {
    static let dump = #"""
    {"serializationVersion":0,"command":{"commandName":"tool","abstract":"A tool.","arguments":[
      {"kind":"flag","names":[{"kind":"long","name":"version"}],"valueName":"version","isOptional":true,"isRepeating":false,"parsingStrategy":"default","shouldDisplay":true}
    ],"subcommands":[
      {"commandName":"run","aliases":["r"],"abstract":"Run it.","arguments":[
        {"kind":"flag","names":[{"kind":"long","name":"version"}],"valueName":"version","isOptional":true,"isRepeating":false,"parsingStrategy":"default","shouldDisplay":true},
        {"kind":"flag","names":[{"kind":"short","name":"v"},{"kind":"long","name":"verbose"}],"valueName":"verbose","abstract":"Talk more.","isOptional":true,"isRepeating":true,"parsingStrategy":"default","shouldDisplay":true},
        {"kind":"option","names":[{"kind":"long","name":"shell"}],"valueName":"shell","isOptional":true,"isRepeating":false,"parsingStrategy":"default","shouldDisplay":true,"completionKind":{"list":{"values":["zsh","bash"]}}},
        {"kind":"option","names":[{"kind":"long","name":"secret"}],"valueName":"secret","isOptional":true,"isRepeating":false,"parsingStrategy":"default","shouldDisplay":false},
        {"kind":"positional","valueName":"target","abstract":"What to run.","isOptional":false,"isRepeating":false,"parsingStrategy":"default","shouldDisplay":true,"completionKind":{"shellCommand":{"command":"ls targets"}}},
        {"kind":"positional","valueName":"files","isOptional":true,"isRepeating":true,"parsingStrategy":"default","shouldDisplay":true,"completionKind":{"file":{"extensions":[]}}}
      ]},
      {"commandName":"_hidden","shouldDisplay":false}
    ]}}
    """#

    @Test func convertsDumpHelpToSpec() throws {
        let module = try ToolInfoSpec.module(fromDumpHelp: Data(Self.dump.utf8))
        #expect(module.hasPrefix("var spec={"))
        #expect(module.hasSuffix("export{spec as default};\n"))

        let root = try #require(try specObject(module))
        #expect(root["name"] as? String == "tool")
        #expect((root["options"] as? [[String: Any]])?.count == 1)
        let subcommands = try #require(root["subcommands"] as? [[String: Any]])
        #expect(subcommands.count == 1)

        let run = subcommands[0]
        #expect(run["name"] as? [String] == ["run", "r"])
        let options = try #require(run["options"] as? [[String: Any]])
        #expect(options.map { $0["name"] as? [String] ?? [$0["name"] as! String] } == [["-v", "--verbose"], ["--shell"]])
        #expect(options[0]["isRepeatable"] as? Bool == true)
        let shellArg = try #require(options[1]["args"] as? [String: Any])
        #expect(shellArg["isOptional"] == nil)
        #expect(shellArg["suggestions"] as? [String] == ["zsh", "bash"])

        let args = try #require(run["args"] as? [[String: Any]])
        let generator = try #require(args[0]["generators"] as? [String: Any])
        #expect(generator["script"] as? [String] == ["/bin/sh", "-c", "ls targets"])
        #expect(args[0]["isOptional"] == nil)
        #expect(args[1]["template"] as? String == "filepaths")
        #expect(args[1]["isOptional"] as? Bool == true)
        #expect(args[1]["isVariadic"] as? Bool == true)
    }

    @Test func generatedModuleLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ToolInfoSpec.module(fromDumpHelp: Data(Self.dump.utf8))
            .write(to: directory.appendingPathComponent("tool.js"), atomically: true, encoding: .utf8)

        let spec = try #require(SpecRuntime(directories: [directory]).spec(named: "tool"))
        #expect(spec.subcommands.first?.names == ["run", "r"])
        #expect(spec.subcommands.first?.args.first?.generators.count == 1)
    }

    @Test func rejectsOtherJSON() {
        #expect(throws: ToolInfoSpec.ConversionError.self) { try ToolInfoSpec.module(fromDumpHelp: Data("[]".utf8)) }
    }

    private func specObject(_ module: String) throws -> [String: Any]? {
        let json = module.dropFirst("var spec=".count).dropLast(";export{spec as default};\n".count)
        return try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    }
}
