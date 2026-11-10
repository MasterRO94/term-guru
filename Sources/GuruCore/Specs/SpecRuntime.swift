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
    private let specsDirectory: URL
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

    public init(specsDirectory: URL) {
        self.specsDirectory = specsDirectory
        context = JSContext()!
        context.exceptionHandler = { _, _ in }
        let exec: @convention(block) (String) -> String = { [unowned self] input in self.execute(input) }
        context.setObject(exec, forKeyedSubscript: "__execNative" as NSString)
        context.evaluateScript(Self.bootstrap)
    }

    public func hasSpec(named name: String) -> Bool {
        guard let url = fileURL(for: name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public func spec(named name: String) -> SpecCommand? {
        if let cached = cache[name] { return cached }
        let loaded = load(name)
        cache[name] = .some(loaded)
        return loaded
    }

    public func flushCache() { cache.removeAll() }

    private func fileURL(for name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("."), !name.contains("..") else { return nil }
        return specsDirectory.appendingPathComponent(name + ".js")
    }

    private func load(_ name: String) -> SpecCommand? {
        guard let url = fileURL(for: name), let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Specs are ES modules ending in `export{x as default,...}`; JavaScriptCore's script mode needs a plain value.
        guard let exportRange = source.range(of: "export{", options: .backwards) else { return nil }
        let exports = source[exportRange.upperBound...].prefix { $0 != "}" }
        guard let binding = exports.split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasSuffix(" as default") })?
            .dropLast(" as default".count)
        else { return nil }
        let script = "__json((function(){\(source[..<exportRange.lowerBound]);return \(binding);})())"
        guard let json = context.evaluateScript(script)?.toString(),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSONObject
        else { return nil }
        return SpecCommand(object)
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
