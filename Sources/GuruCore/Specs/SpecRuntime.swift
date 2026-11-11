import Foundation
import JavaScriptCore

public struct GeneratorContext: Sendable {
    public var cwd: String
    public var environment: [String: String]
    public var searchTerm: String

    public init(cwd: String, environment: [String: String], searchTerm: String) {
        self.cwd = cwd; self.environment = environment; self.searchTerm = searchTerm
    }
}

/// Loads compiled Fig completion specs and runs their JavaScript generators. Not thread-safe: use from one queue.
public final class SpecRuntime {
    private let context: JSContext
    /// Searched in order, so earlier directories override later ones.
    public let directories: [URL]
    private var cache: [String: SpecCommand?] = [:]
    private var execContext = GeneratorContext(cwd: "/", environment: [:], searchTerm: "")

    private static let bootstrap = """
    globalThis.__fns = [];
    globalThis.__json = (value) => JSON.stringify(value, (k, v) => typeof v === 'function' ? { __fn: __fns.push(v) - 1 } : v) ?? 'null';
    globalThis.__exec = (input) => {
      try { return Promise.resolve(JSON.parse(__execNative(JSON.stringify(input)))); }
      catch (e) { return Promise.reject(e); }
    };
    globalThis.__settled = null;
    globalThis.__call = (id, args) => {
      globalThis.__settled = null;
      try {
        Promise.resolve(__fns[id](...args)).then(
          (r) => { globalThis.__settled = __json(r); },
          () => { globalThis.__settled = 'null'; });
      } catch (e) { globalThis.__settled = 'null'; }
    };
    """

    public convenience init(specsDirectory: URL) {
        self.init(directories: [specsDirectory])
    }

    public init(directories: [URL]) {
        self.directories = directories
        context = JSContext()!
        context.exceptionHandler = { _, _ in }
        let exec: @convention(block) (String) -> String = { [unowned self] input in self.execute(input) }
        context.setObject(exec, forKeyedSubscript: "__execNative" as NSString)
        context.evaluateScript(Self.bootstrap)
    }

    public func hasSpec(named name: String) -> Bool { fileURL(for: name) != nil }

    public func spec(named name: String) -> SpecCommand? {
        if let cached = cache[name] { return cached }
        let loaded = load(name)
        cache[name] = .some(loaded)
        return loaded
    }

    public func flushCache() { cache.removeAll() }

    public func fileURL(for name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("."), !name.contains("..") else { return nil }
        return directories.lazy
            .map { $0.appendingPathComponent(name + ".js") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Top-level command names with a spec, each mapped to the directory it loads from.
    public func commandNames() -> [String: URL] {
        var names: [String: URL] = [:]
        for directory in directories.reversed() {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            for file in files where file.hasSuffix(".js") { names[String(file.dropLast(3))] = directory }
        }
        return names
    }

    private func load(_ name: String) -> SpecCommand? {
        guard let url = fileURL(for: name), let source = try? String(contentsOf: url, encoding: .utf8),
              let body = Self.scriptBody(module: source)
        else { return nil }
        let script = "__json((function(){\(body)})())"
        guard let json = context.evaluateScript(script)?.toString(),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSONObject
        else { return nil }
        return SpecCommand(object)
    }

    private static let namedExport = try! NSRegularExpression(pattern: #"export\s*\{([^}]*)\}"#)
    private static let defaultExport = try! NSRegularExpression(pattern: #"export\s+default\s"#)

    /// JavaScriptCore's script mode has no `export`, so the module's default export becomes a function's return value.
    static func scriptBody(module source: String) -> String? {
        let whole = NSRange(source.startIndex..., in: source)
        if let match = namedExport.matches(in: source, range: whole).last,
           let range = Range(match.range, in: source), let list = Range(match.range(at: 1), in: source) {
            let entries: [[Substring]] = source[list].split(separator: ",").map { $0.split(whereSeparator: \.isWhitespace) }
            guard let entry = entries.first(where: { $0.count == 3 && $0[1] == "as" && $0[2] == "default" }) else { return nil }
            let binding = entry[0]
            return "\(source[..<range.lowerBound]);return \(binding);"
        }
        if let match = defaultExport.matches(in: source, range: whole).last, let range = Range(match.range, in: source) {
            return "\(source[..<range.lowerBound]);return \(source[range.upperBound...])"
        }
        return nil
    }

    // MARK: Generators

    public func resolveScript(_ fn: Int, tokens: [String]) -> ScriptSource? {
        guard let json = call(fn, [tokens]), let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        else { return nil }
        return ScriptSource(value)
    }

    public func queryTerm(_ fn: Int, partial: String) -> String? {
        guard let json = call(fn, [partial]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? String
    }

    public func trigger(_ fn: Int, newToken: String, oldToken: String) -> Bool? {
        guard let json = call(fn, [newToken, oldToken]) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? Bool
    }

    /// Fig's `filterTemplateSuggestions`: gets `{name, type, …}` objects, returns the ones to keep.
    public func filterTemplate(_ fn: Int, suggestions: [[String: Any]]) -> [[String: Any]]? {
        guard let json = call(fn, [suggestions]),
              let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed) as? [Any]
        else { return nil }
        return value.compactMap { $0 as? JSONObject }
    }

    public func postProcess(_ fn: Int, output: String, tokens: [String]) -> [SpecSuggestion] {
        suggestions(from: call(fn, [output, tokens]))
    }

    public func custom(_ fn: Int, tokens: [String], context generator: GeneratorContext) -> [SpecSuggestion] {
        execContext = generator
        let info: [String: Any] = [
            "currentWorkingDirectory": generator.cwd,
            "environmentVariables": generator.environment,
            "currentProcess": "zsh",
            "sshPrefix": "",
            "searchTerm": generator.searchTerm,
            "isDangerous": false,
        ]
        guard let exec = context.objectForKeyedSubscript("__exec") else { return [] }
        return suggestions(from: call(fn, [tokens, exec, info]))
    }

    public func generateSpec(_ fn: Int, tokens: [String], context generator: GeneratorContext) -> SpecCommand? {
        execContext = generator
        guard let exec = context.objectForKeyedSubscript("__exec"),
              let json = call(fn, [tokens, exec]),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSONObject
        else { return nil }
        return SpecCommand(object)
    }

    public func setContext(_ generator: GeneratorContext) { execContext = generator }

    private func call(_ fn: Int, _ arguments: [Any]) -> String? {
        context.objectForKeyedSubscript("__call")?.call(withArguments: [fn, arguments])
        // Microtasks drain when the outermost call returns; generators only await our synchronous __exec.
        let settled = context.objectForKeyedSubscript("__settled")
        guard let settled, settled.isString else { return nil }
        return settled.toString()
    }

    private func suggestions(from json: String?) -> [SpecSuggestion] {
        guard let json, let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        else { return [] }
        return SpecSuggestion.list(value)
    }

    private func execute(_ input: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(input.utf8)) as? JSONObject,
              let command = object["command"] as? String
        else { return #"{"stdout":"","stderr":"bad input","status":1}"# }
        var environment = execContext.environment
        for (key, value) in object["env"] as? [String: String] ?? [:] { environment[key] = value }
        let timeout = ((object["timeout"] as? NSNumber)?.doubleValue).map { min($0 / 1000, 3) } ?? 2
        let result = Shell.run(
            [command] + stringList(object["args"]),
            cwd: object["cwd"] as? String ?? execContext.cwd,
            environment: environment,
            timeout: timeout
        )
        let payload: [String: Any] = ["stdout": result.stdout, "stderr": result.stderr, "status": Int(result.status)]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
