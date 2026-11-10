import Foundation

typealias JSONObject = [String: Any]

func stringList(_ value: Any?) -> [String] {
    if let s = value as? String { return [s] }
    if let a = value as? [Any] { return a.compactMap { $0 as? String } }
    return []
}

func objectList(_ value: Any?) -> [JSONObject] {
    if let o = value as? JSONObject { return [o] }
    if let a = value as? [Any] { return a.compactMap { $0 as? JSONObject } }
    return []
}

func functionID(_ value: Any?) -> Int? {
    (value as? JSONObject)?["__fn"] as? Int
}

public struct SpecSuggestion: Sendable {
    public var names: [String]
    public var displayName: String?
    public var insertValue: String?
    public var description: String
    public var priority: Double?
    public var hidden: Bool
    public var type: String?

    init?(_ value: Any) {
        if let s = value as? String {
            guard !s.isEmpty else { return nil }
            names = [s]; description = ""; hidden = false
            return
        }
        guard let o = value as? JSONObject else { return nil }
        names = stringList(o["name"])
        displayName = o["displayName"] as? String
        insertValue = o["insertValue"] as? String
        names.removeAll(where: \.isEmpty)
        if names.isEmpty, let fallback = displayName ?? insertValue { names = [fallback] }
        guard !names.isEmpty, !names[0].isEmpty else { return nil }
        description = o["description"] as? String ?? ""
        priority = (o["priority"] as? NSNumber)?.doubleValue
        hidden = o["hidden"] as? Bool ?? false
        type = o["type"] as? String
    }

    static func list(_ value: Any?) -> [SpecSuggestion] {
        (value as? [Any] ?? []).compactMap(SpecSuggestion.init)
    }
}

public enum ScriptSource: Sendable {
    case argv([String])
    case shell(String)
    case function(Int)

    init?(_ value: Any?) {
        if let id = functionID(value) { self = .function(id); return }
        if let s = value as? String, !s.isEmpty { self = .shell(s); return }
        if let a = value as? [Any] {
            let argv = a.compactMap { $0 as? String }
            guard !argv.isEmpty else { return nil }
            self = .argv(argv); return
        }
        if let o = value as? JSONObject, let command = o["command"] as? String {
            self = .argv([command] + stringList(o["args"])); return
        }
        return nil
    }
}

public struct SpecGenerator: Sendable {
    public var template: [String]
    public var script: ScriptSource?
    public var splitOn: String?
    public var postProcess: Int?
    public var custom: Int?
    /// Separator after which the word is matched (e.g. "/" for paths).
    public var queryTermSeparator: String?
    public var queryTermFunction: Int?

    init(_ o: JSONObject) {
        queryTermSeparator = o["getQueryTerm"] as? String
        queryTermFunction = functionID(o["getQueryTerm"])
        template = stringList(o["template"])
        script = ScriptSource(o["script"])
        splitOn = o["splitOn"] as? String
        postProcess = functionID(o["postProcess"])
        custom = functionID(o["custom"])
    }
}

public final class SpecArg: @unchecked Sendable {
    public let name: String
    public let description: String
    public let isOptional: Bool
    public let isVariadic: Bool
    public let isCommand: Bool
    public let suggestions: [SpecSuggestion]
    public let template: [String]
    public let generators: [SpecGenerator]

    init(_ o: JSONObject) {
        name = o["name"] as? String ?? ""
        description = o["description"] as? String ?? ""
        isOptional = o["isOptional"] as? Bool ?? false
        isVariadic = o["isVariadic"] as? Bool ?? false
        isCommand = o["isCommand"] as? Bool ?? false
        suggestions = SpecSuggestion.list(o["suggestions"])
        template = stringList(o["template"])
        generators = objectList(o["generators"]).map(SpecGenerator.init)
    }
}

public final class SpecOption: @unchecked Sendable {
    public let names: [String]
    public let description: String
    public let args: [SpecArg]
    public let isPersistent: Bool
    public let isRepeatable: Bool
    public let separator: String?
    public let insertValue: String?
    public let hidden: Bool
    public let priority: Double?

    init(_ o: JSONObject) {
        names = stringList(o["name"])
        description = o["description"] as? String ?? ""
        args = objectList(o["args"]).map(SpecArg.init)
        isPersistent = o["isPersistent"] as? Bool ?? false
        isRepeatable = (o["isRepeatable"] as? Bool ?? false) || (o["isRepeatable"] as? NSNumber).map { $0.intValue > 1 } ?? false
        if let s = o["requiresSeparator"] as? String {
            separator = s
        } else if (o["requiresSeparator"] as? Bool ?? false) || (o["requiresEquals"] as? Bool ?? false) {
            separator = "="
        } else {
            separator = nil
        }
        insertValue = o["insertValue"] as? String
        hidden = o["hidden"] as? Bool ?? false
        priority = (o["priority"] as? NSNumber)?.doubleValue
    }
}

public final class SpecCommand: @unchecked Sendable {
    public let names: [String]
    public let description: String
    public let subcommands: [SpecCommand]
    public let options: [SpecOption]
    public let args: [SpecArg]
    public let loadSpec: String?
    public let insertValue: String?
    public let hidden: Bool
    public let priority: Double?
    public let additionalSuggestions: [SpecSuggestion]
    public let generateSpec: Int?

    init(_ o: JSONObject) {
        names = stringList(o["name"])
        description = o["description"] as? String ?? ""
        subcommands = objectList(o["subcommands"]).map(SpecCommand.init)
        options = objectList(o["options"]).map(SpecOption.init)
        args = objectList(o["args"]).map(SpecArg.init)
        loadSpec = o["loadSpec"] as? String
        insertValue = o["insertValue"] as? String
        hidden = o["hidden"] as? Bool ?? false
        priority = (o["priority"] as? NSNumber)?.doubleValue
        additionalSuggestions = SpecSuggestion.list(o["additionalSuggestions"])
        generateSpec = functionID(o["generateSpec"])
    }

    /// Static spec extended with what its `generateSpec` produced for the current directory.
    init(base: SpecCommand, generated: SpecCommand) {
        names = base.names
        description = base.description
        subcommands = base.subcommands + generated.subcommands
        options = base.options + generated.options
        args = base.args.isEmpty ? generated.args : base.args
        loadSpec = nil
        insertValue = base.insertValue
        hidden = base.hidden
        priority = base.priority
        additionalSuggestions = base.additionalSuggestions + generated.additionalSuggestions
        generateSpec = nil
    }

    public var name: String { names.first ?? "" }
}
