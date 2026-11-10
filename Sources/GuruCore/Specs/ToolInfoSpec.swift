import Foundation

/// Converts swift-argument-parser `--experimental-dump-help` JSON into a Fig spec module.
public enum ToolInfoSpec {
    public enum ConversionError: Error, CustomStringConvertible {
        case invalidJSON

        public var description: String { "input is not `--experimental-dump-help` JSON" }
    }

    public static func module(fromDumpHelp data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject,
              let command = root["command"] as? JSONObject
        else { throw ConversionError.invalidJSON }
        let spec = convert(command, isRoot: true)
        let json = try JSONSerialization.data(withJSONObject: spec, options: [.sortedKeys, .withoutEscapingSlashes])
        // SpecRuntime looks for exactly `export{`.
        return "var spec=\(String(decoding: json, as: UTF8.self));export{spec as default};\n"
    }

    static func convert(_ command: JSONObject, isRoot: Bool) -> JSONObject {
        var spec: JSONObject = [:]
        let name = command["commandName"] as? String ?? ""
        let aliases = stringList(command["aliases"])
        spec["name"] = aliases.isEmpty ? name as Any : [name] + aliases
        if let abstract = nonEmpty(command["abstract"]) { spec["description"] = abstract }

        let subcommands = objectList(command["subcommands"]).filter(isDisplayed).map { convert($0, isRoot: false) }
        if !subcommands.isEmpty { spec["subcommands"] = subcommands }

        let arguments = objectList(command["arguments"]).filter(isDisplayed)
        let options = arguments
            .filter { $0["kind"] as? String != "positional" }
            // ArgumentParser repeats --version on every subcommand, where it only prints the root version.
            .filter { isRoot || $0["valueName"] as? String != "version" }
            .map(option)
        if !options.isEmpty { spec["options"] = options }

        let args = arguments.filter { $0["kind"] as? String == "positional" }.map(arg)
        if !args.isEmpty { spec["args"] = args }
        return spec
    }

    static func option(_ info: JSONObject) -> JSONObject {
        var spec: JSONObject = [:]
        let names = objectList(info["names"]).compactMap(flagName)
        spec["name"] = names.count == 1 ? names[0] as Any : names
        if let abstract = nonEmpty(info["abstract"]) { spec["description"] = abstract }
        if info["isRepeating"] as? Bool == true { spec["isRepeatable"] = true }
        if info["kind"] as? String == "option" { spec["args"] = arg(info) }
        return spec
    }

    static func arg(_ info: JSONObject) -> JSONObject {
        var spec: JSONObject = ["name": info["valueName"] as? String ?? "value"]
        // For an option, `isOptional` means the option may be left out; its value is still required.
        if info["kind"] as? String == "positional" {
            if let abstract = nonEmpty(info["abstract"]) { spec["description"] = abstract }
            if info["isOptional"] as? Bool == true { spec["isOptional"] = true }
            if info["isRepeating"] as? Bool == true { spec["isVariadic"] = true }
        }
        if let value = nonEmpty(info["defaultValue"]) { spec["default"] = value }

        let descriptions = info["allValueDescriptions"] as? [String: String] ?? [:]
        let values = stringList(info["allValues"])
        if !values.isEmpty {
            spec["suggestions"] = values.map { value -> Any in
                guard let description = descriptions[value], !description.isEmpty else { return value }
                return ["name": value, "description": description]
            }
        }
        completion(info["completionKind"] as? JSONObject).forEach { spec[$0.key] = $0.value }
        return spec
    }

    /// Swift's synthesized Codable encodes `.list(values:)` as `{"list":{"values":[…]}}`.
    static func completion(_ kind: JSONObject?) -> JSONObject {
        guard let kind else { return [:] }
        if let list = kind["list"] as? JSONObject { return ["suggestions": stringList(list["values"])] }
        if kind["file"] != nil { return ["template": "filepaths"] }
        if kind["directory"] != nil { return ["template": "folders"] }
        if let shell = kind["shellCommand"] as? JSONObject, let command = shell["command"] as? String {
            return ["generators": ["script": ["/bin/sh", "-c", command], "splitOn": "\n"]]
        }
        return [:]
    }

    static func flagName(_ name: JSONObject) -> String? {
        guard let value = name["name"] as? String, !value.isEmpty else { return nil }
        switch name["kind"] as? String {
        case "long": return "--" + value
        case "short", "longWithSingleDash": return "-" + value
        default: return nil
        }
    }

    static func isDisplayed(_ object: JSONObject) -> Bool { object["shouldDisplay"] as? Bool ?? true }

    static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}
