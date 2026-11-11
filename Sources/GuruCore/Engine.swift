import Foundation

public struct EngineRequest: Sendable {
    public var buffer: String
    public var cursor: Int
    public var cwd: String
    public var path: String
    public var aliases: [String: String]

    public init(buffer: String, cursor: Int, cwd: String, path: String, aliases: [String: String] = [:]) {
        self.buffer = buffer; self.cursor = cursor; self.cwd = cwd; self.path = path; self.aliases = aliases
    }
}

/// Turns an edit buffer into ranked suggestions. Not thread-safe: use from one queue.
public final class Engine {
    public var limit = 60
    public var useHistory = true
    /// Overridden by tests that step through cache lifetimes.
    var now: () -> Date = Date.init

    private let specs: SpecRuntime
    private let history: HistoryStore
    private let executables: ExecutableIndex
    private var generatorCache: [String: (items: [SpecSuggestion], at: Date)] = [:]
    /// Stale-while-revalidate entries served this request, re-run by `refreshStale()`.
    private var staleRefreshes: [String: () -> [SpecSuggestion]] = [:]
    /// Per generator and argument position: the word at the last run, its results, and when they were last served.
    private var triggerState: [String: (token: String, items: [SpecSuggestion], used: Date)] = [:]

    private var generatedSpecs: [String: (spec: SpecCommand, at: Date)] = [:]

    private typealias Group = (items: [Suggestion], query: String)

    public init(specs: SpecRuntime, history: HistoryStore = HistoryStore(), executables: ExecutableIndex = ExecutableIndex()) {
        self.specs = specs
        self.history = history
        self.executables = executables
    }

    public func rescan() {
        specs.flushCache()
        executables.invalidate()
        generatorCache.removeAll()
        staleRefreshes.removeAll()
        triggerState.removeAll()
        generatedSpecs.removeAll()
        history.reload(force: true)
    }

    public func suggest(_ request: EngineRequest) -> [Suggestion] {
        let characters = Array(request.buffer)
        let cursor = max(0, min(request.cursor, characters.count))
        // Completing in the middle of a word would clobber the text right of the cursor.
        if cursor < characters.count, !characters[cursor].isWhitespace { return [] }
        let left = String(characters[..<cursor])
        let line = Tokenizer.parse(left)
        var groups: [Group] = []
        switch line.redirect {
        case .file?:
            groups = [FileSuggestions.list(partial: line.partial, rawPartial: line.rawPartial, cwd: request.cwd, foldersOnly: false)]
        case .some(.none):
            return []
        case nil:
            if line.tokens.count == 1, line.partial.isEmpty { return [] }
            history.reload()
            if line.tokens.count == 1 {
                groups.append((commandCandidates(request, replace: line.rawPartial.count), line.partial))
            } else {
                groups += argumentGroups(line, request: request, depth: 0)
            }
            if useHistory { groups.append(historyGroup(left: left)) }
        }

        var merged: [Suggestion] = []
        for group in groups { merged += Fuzzy.rank(group.items, query: group.query, limit: limit) }
        merged.sort { $0.score > $1.score }
        var seen = Set<String>()
        return Array(merged.filter { seen.insert($0.insert).inserted }.prefix(limit))
    }

    /// Re-runs the stale-while-revalidate generators the last requests served from cache; call after replying.
    public func refreshStale() {
        let pending = staleRefreshes
        staleRefreshes.removeAll()
        for (key, produce) in pending { generatorCache[key] = (produce(), now()) }
    }

    // MARK: First word

    private func commandCandidates(_ request: EngineRequest, replace: Int) -> [Suggestion] {
        var items: [Suggestion] = []
        for (name, value) in request.aliases {
            items.append(Suggestion(name: name, insert: name + " ", description: value, kind: .alias,
                                    priority: 62 + boost(name), replace: replace))
        }
        for name in executables.names(path: request.path) {
            items.append(Suggestion(name: name, insert: name + " ", kind: .command,
                                    priority: 50 + boost(name), replace: replace))
        }
        return items
    }

    private func boost(_ command: String) -> Double {
        let count = history.count(firstWord: command)
        return count == 0 ? 0 : min(30, log2(Double(count) + 1) * 5)
    }

    private func historyGroup(left: String) -> Group {
        let typed = String(left.drop { $0 == " " })
        guard typed.count >= 2 else { return ([], "") }
        let items = history.matches(prefix: typed, limit: 3).enumerated().map { index, line in
            Suggestion(name: line, insert: line, description: "History", kind: .history,
                       priority: 38 - Double(index), replace: left.count)
        }
        return (items, typed)
    }

    // MARK: Arguments

    private struct Walk {
        var command: SpecCommand
        /// Command that holds `command` as a subcommand; Fig's `help` template lists its siblings.
        var parent: SpecCommand?
        var persistent: [SpecOption] = []
        var argIndex = 0
        var positionals = 0
        var pending: (option: SpecOption, index: Int)?
        var used = Set<String>()
        var afterDoubleDash = false

        var options: [SpecOption] { command.options + persistent }

        func option(named name: String) -> SpecOption? { options.first { $0.names.contains(name) } }

        var currentArg: SpecArg? {
            if argIndex < command.args.count { return command.args[argIndex] }
            if let last = command.args.last, last.isVariadic { return last }
            return nil
        }
    }

    private func argumentGroups(_ line: ParsedLine, request: EngineRequest, depth: Int) -> [Group] {
        var tokens = line.tokens
        if depth == 0, let alias = request.aliases[tokens[0]] {
            let expanded = Tokenizer.parse(alias).tokens.filter { !$0.isEmpty }
            if !expanded.isEmpty { tokens = expanded + tokens.dropFirst() }
        }
        let commandName = (tokens[0] as NSString).lastPathComponent
        let rawPartial = line.rawPartial
        let partial = tokens[tokens.count - 1]

        guard depth < 4, let root = specs.spec(named: commandName) else {
            return [FileSuggestions.list(partial: partial, rawPartial: rawPartial, cwd: request.cwd, foldersOnly: false)]
        }

        let env = GeneratorContext(cwd: request.cwd, environment: environment(request), searchTerm: partial)
        var walk = Walk(command: resolve(root, tokens: tokens, env: env))
        for index in 1..<(tokens.count - 1) {
            let token = tokens[index]
            if let pending = walk.pending {
                let arg = pending.option.args[pending.index]
                if !(arg.isOptional && token.hasPrefix("-")) {
                    let next = pending.index + 1
                    walk.pending = next < pending.option.args.count ? (pending.option, next) : (arg.isVariadic ? pending : nil)
                    continue
                }
                walk.pending = nil
            }
            if !walk.afterDoubleDash, token == "--" { walk.afterDoubleDash = true; continue }
            if !walk.afterDoubleDash, token.hasPrefix("-"), token != "-" {
                consumeOption(token, in: &walk)
                continue
            }
            if walk.positionals == 0, let sub = walk.command.subcommands.first(where: { $0.names.contains(token) }) {
                walk.persistent += walk.command.options.filter(\.isPersistent)
                walk.parent = walk.command
                walk.command = resolve(sub, tokens: tokens, env: env)
                walk.argIndex = 0
                walk.used = []
                continue
            }
            if walk.currentArg?.isCommand == true {
                let rest = ParsedLine(tokens: Array(tokens[index...]), rawPartial: rawPartial)
                if rest.tokens.count == 1 {
                    return [(commandCandidates(request, replace: rawPartial.count), partial)]
                }
                return argumentGroups(rest, request: request, depth: depth + 1)
            }
            walk.positionals += 1
            if walk.currentArg?.isVariadic != true { walk.argIndex += 1 }
        }

        var groups: [Group] = []
        let replace = rawPartial.count

        func addArg(_ arg: SpecArg, partial: String, rawPartial: String, replace: Int) {
            groups.append((convert(arg.suggestions, kind: .argument, replace: replace), partial))
            for generator in arg.generators {
                // Path-like generators match and replace only the part after their separator.
                var term = partial
                if let separator = generator.queryTermSeparator, let cut = partial.range(of: separator, options: .backwards) {
                    term = String(partial[cut.upperBound...])
                } else if let fn = generator.queryTermFunction, let custom = specs.queryTerm(fn, partial: partial) {
                    term = custom
                }
                let scope = String(partial.dropLast(term.count))
                var items = run(generator, tokens: tokens, env: env, scope: scope)
                // A generator that lists only folders is a folder list, like Fig's own `cd` spec.
                if !items.isEmpty, items.allSatisfy({ $0.type == "folder" }) {
                    let parents = FileSuggestions.parents(partial: partial, replace: replace, cwd: request.cwd)
                    if !parents.isEmpty {
                        items.removeAll { $0.names[0] == "../" }
                        groups.append((parents, partial))
                    }
                }
                groups.append((convert(items, kind: .argument, replace: max(0, replace - scope.count)), term))
            }
            let unfiltered = arg.generators.filter { $0.filterTemplateSuggestions == nil }
            let helpRoot = walk.parent ?? walk.command
            groups += templateGroups(Set(arg.template + unfiltered.flatMap(\.template)), root: helpRoot, command: commandName,
                                     partial: partial, rawPartial: rawPartial, replace: replace, cwd: request.cwd)
            for generator in arg.generators where !generator.template.isEmpty {
                guard let filter = generator.filterTemplateSuggestions else { continue }
                groups += templateGroups(Set(generator.template), root: helpRoot, command: commandName,
                                         partial: partial, rawPartial: rawPartial, replace: replace, cwd: request.cwd)
                    .map { (filterTemplate(filter, $0.items), $0.query) }
            }
        }

        if let pending = walk.pending {
            addArg(pending.option.args[pending.index], partial: partial, rawPartial: rawPartial, replace: replace)
            if !pending.option.args[pending.index].isOptional { return groups }
        }

        if !walk.afterDoubleDash, partial.hasPrefix("-") {
            if let eq = partial.firstIndex(of: "="), let option = walk.option(named: String(partial[..<eq])), let arg = option.args.first {
                let value = String(partial[partial.index(after: eq)...])
                addArg(arg, partial: value, rawPartial: value, replace: value.count)
                return groups
            }
            groups.append((optionCandidates(walk, partial: partial, replace: replace, priority: 50), partial))
            return groups
        }

        if walk.currentArg?.isCommand == true {
            groups.append((commandCandidates(request, replace: replace), partial))
            return groups
        }
        if walk.positionals == 0 {
            var items = walk.command.subcommands.filter { !$0.hidden }.map { sub -> Suggestion in
                let name = sub.names.first { $0.hasPrefix(partial) } ?? sub.name
                return make(name: name, display: sub.names.joined(separator: ", "), insertValue: sub.insertValue,
                            description: sub.description, kind: .subcommand, priority: sub.priority ?? 55, replace: replace,
                            icon: sub.icon)
            }
            items += convert(walk.command.additionalSuggestions, kind: .subcommand, replace: replace)
            groups.append((items, partial))
        }
        if let arg = walk.currentArg {
            addArg(arg, partial: partial, rawPartial: rawPartial, replace: replace)
        }
        if partial.isEmpty {
            groups.append((optionCandidates(walk, partial: partial, replace: replace, priority: 30), partial))
        }
        return groups
    }

    private func templateGroups(
        _ templates: Set<String>, root: SpecCommand, command: String,
        partial: String, rawPartial: String, replace: Int, cwd: String
    ) -> [Group] {
        var groups: [Group] = []
        if templates.contains("filepaths") || templates.contains("folders") {
            groups.append(FileSuggestions.list(partial: partial, rawPartial: rawPartial, cwd: cwd,
                                               foldersOnly: !templates.contains("filepaths")))
        }
        if templates.contains("help") {
            let items = root.subcommands.filter { !$0.hidden && !$0.name.isEmpty }.map { sub in
                make(name: sub.name, display: sub.name, insertValue: nil, description: sub.description,
                     kind: .subcommand, priority: 50, replace: replace, icon: sub.icon)
            }
            groups.append((items, partial))
        }
        if templates.contains("history") {
            let items = history.arguments(command: command, prefix: partial, limit: 10).enumerated().map { index, word in
                Suggestion(name: word, insert: Tokenizer.quote(word) + " ", description: "History", kind: .history,
                           priority: 40 - Double(index) * 0.1, replace: replace)
            }
            groups.append((items, partial))
        }
        return groups
    }

    private func filterTemplate(_ fn: Int, _ items: [Suggestion]) -> [Suggestion] {
        func figName(_ item: Suggestion) -> String {
            item.kind == .folder && !item.name.hasSuffix("/") ? item.name + "/" : item.name
        }
        func figType(_ kind: SuggestionKind) -> String {
            switch kind {
            case .folder: "folder"
            case .file: "file"
            case .subcommand: "subcommand"
            default: "special"
            }
        }
        let objects: [[String: Any]] = items.map {
            ["name": figName($0), "type": figType($0.kind), "description": $0.description, "priority": $0.priority]
        }
        guard let kept = specs.filterTemplate(fn, suggestions: objects) else { return items }
        let byName = Dictionary(items.map { (figName($0), $0) }, uniquingKeysWith: { first, _ in first })
        return kept.compactMap { object in
            guard let name = object["name"] as? String, var item = byName[name] else { return nil }
            // Specs write `priority: matches && 76`, which is `false` for the rest.
            if let priority = object["priority"] as? NSNumber, CFGetTypeID(priority) != CFBooleanGetTypeID() {
                item.priority = priority.doubleValue
            }
            if let description = object["description"] as? String { item.description = description }
            return item
        }
    }

    private func consumeOption(_ token: String, in walk: inout Walk) {
        let eq = token.firstIndex(of: "=")
        let flag = eq.map { String(token[..<$0]) } ?? token
        if let option = walk.option(named: flag) {
            walk.used.formUnion(option.names)
            if eq == nil, let first = option.args.first, !first.isOptional { walk.pending = (option, 0) }
            return
        }
        // POSIX-style cluster: -xvf behaves like -x -v -f, and only the last flag may take a value.
        guard !token.hasPrefix("--"), token.count > 2 else { return }
        let flags = token.dropFirst().map { "-\($0)" }
        for (offset, short) in flags.enumerated() {
            guard let option = walk.option(named: short) else { continue }
            walk.used.formUnion(option.names)
            if offset == flags.count - 1, let first = option.args.first, !first.isOptional { walk.pending = (option, 0) }
        }
    }

    private func resolve(_ command: SpecCommand, tokens: [String], env: GeneratorContext) -> SpecCommand {
        var resolved = command
        if let path = command.loadSpec, let loaded = specs.spec(named: path) { resolved = loaded }
        guard let fn = resolved.generateSpec else { return resolved }
        let key = "g\(fn)|\(env.cwd)"
        if let hit = generatedSpecs[key], now().timeIntervalSince(hit.at) < 30 { return hit.spec }
        var merged = resolved
        if let generated = specs.generateSpec(fn, tokens: tokens, context: env) {
            merged = SpecCommand(base: resolved, generated: generated)
        }
        if generatedSpecs.count > 50 { generatedSpecs.removeAll() }
        generatedSpecs[key] = (merged, now())
        return merged
    }

    private func optionCandidates(_ walk: Walk, partial: String, replace: Int, priority: Double) -> [Suggestion] {
        walk.options.compactMap { option in
            guard !option.hidden, !option.names.isEmpty else { return nil }
            if !option.isRepeatable, option.names.contains(where: walk.used.contains) { return nil }
            if option.exclusiveOn.contains(where: walk.used.contains) { return nil }
            // Spec authors list aliases here (["-l", "--long"], tar's ["T", "-T", "--files-from"]), so any one will do.
            if !option.dependsOn.isEmpty, !option.dependsOn.contains(where: walk.used.contains) { return nil }
            let name = option.names.first { !partial.isEmpty && $0.hasPrefix(partial) } ?? option.names[0]
            var suggestion = make(name: name, display: option.names.joined(separator: ", "), insertValue: option.insertValue,
                                  description: option.description, kind: .option,
                                  priority: option.priority ?? priority, replace: replace, icon: option.icon)
            if option.insertValue == nil, let separator = option.separator { suggestion.insert = name + separator }
            return suggestion
        }
    }

    private func run(_ generator: SpecGenerator, tokens: [String], env: GeneratorContext, scope: String) -> [SpecSuggestion] {
        specs.setContext(env)
        let position = "\(env.cwd)|\(tokens.dropLast().joined(separator: " "))"
        let token = tokens.last ?? ""
        let stateKey = "\(generator.identity)|\(position)"
        var fired = false
        if let trigger = generator.trigger, let state = triggerState[stateKey],
           now().timeIntervalSince(state.used) < 10 {
            guard fires(trigger, new: token, old: state.token) else {
                triggerState[stateKey]?.used = now()
                return state.items
            }
            fired = true
        }
        let items = produce(generator, tokens: tokens, env: env, scope: scope, position: position, force: fired)
        if generator.trigger != nil {
            if triggerState.count > 200 { triggerState.removeAll() }
            triggerState[stateKey] = (token, items, now())
        }
        return items
    }

    private func fires(_ trigger: GeneratorTrigger, new: String, old: String) -> Bool {
        switch trigger {
        case let .string(mark): new.components(separatedBy: mark).count != old.components(separatedBy: mark).count
        case let .function(fn): specs.trigger(fn, newToken: new, oldToken: old) ?? false
        case .change: new != old
        case let .threshold(length): abs(new.count - old.count) > length
        }
    }

    /// `force` skips a cached custom result: custom generators see the word, so a fired trigger needs a fresh run.
    private func produce(
        _ generator: SpecGenerator, tokens: [String], env: GeneratorContext, scope: String, position: String, force: Bool
    ) -> [SpecSuggestion] {
        // The cwd stays in every key even without `cacheByDirectory`: a wrong-directory branch list costs more than a re-run.
        if let custom = generator.custom {
            // Custom generators see the partial word, so cache per word start rather than per keystroke.
            return cached("c\(custom)|\(position)|\(scope)", generator.cache, force: force) { [specs] in
                specs.custom(custom, tokens: tokens, context: env)
            }
        }
        guard var script = generator.script else { return [] }
        if case let .function(fn) = script {
            guard let resolved = specs.resolveScript(fn, tokens: tokens) else { return [] }
            script = resolved
        }
        let argv: [String]
        switch script {
        case let .argv(list): argv = list
        case let .shell(command): argv = ["sh", "-c", command]
        case .function: return []
        }
        let key = "s|\(env.cwd)|\(argv.joined(separator: "\u{0}"))|\(generator.postProcess ?? -1)"
        return cached(key, generator.cache) { [specs] in
            let result = Shell.run(argv, cwd: env.cwd, environment: env.environment, timeout: 2)
            if let postProcess = generator.postProcess {
                return specs.postProcess(postProcess, output: result.stdout, tokens: tokens)
            }
            guard result.status == 0 else { return [] }
            return result.stdout.components(separatedBy: generator.splitOn ?? "\n").compactMap {
                SpecSuggestion($0.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    private func cached(
        _ key: String, _ policy: GeneratorCachePolicy, force: Bool = false, _ produce: @escaping () -> [SpecSuggestion]
    ) -> [SpecSuggestion] {
        if !force, let hit = generatorCache[key] {
            if now().timeIntervalSince(hit.at) < policy.ttl { return hit.items }
            if policy.staleWhileRevalidate {
                staleRefreshes[key] = produce
                return hit.items
            }
        }
        if generatorCache.count > 200 { generatorCache.removeAll() }
        let items = produce()
        generatorCache[key] = (items, now())
        return items
    }

    private func environment(_ request: EngineRequest) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if !request.path.isEmpty { env["PATH"] = request.path }
        env["PWD"] = request.cwd
        return env
    }

    private func convert(_ raw: [SpecSuggestion], kind: SuggestionKind, replace: Int) -> [Suggestion] {
        raw.compactMap { item in
            guard !item.hidden else { return nil }
            var resolved = kind
            var icon = item.icon
            switch item.type {
            case "folder": resolved = .folder; icon = icon ?? .fileType("/")
            case "file": resolved = .file; icon = icon ?? SuggestionIcon.fileType(name: item.names[0])
            case "subcommand": resolved = .subcommand
            case "option": resolved = .option
            default: break
            }
            return make(name: item.names[0], display: item.displayName ?? item.names.joined(separator: ", "),
                        insertValue: item.insertValue, description: item.description, kind: resolved,
                        priority: item.priority ?? 50, replace: replace, icon: icon)
        }
    }

    private func make(
        name: String, display: String, insertValue: String?, description: String,
        kind: SuggestionKind, priority: Double, replace: Int, icon: SuggestionIcon? = nil
    ) -> Suggestion {
        let isPath = kind == .folder || name.hasSuffix("/")
        var insert = insertValue ?? (kind == .argument || isPath ? Tokenizer.quote(name) : name) + (isPath ? "" : " ")
        var back = 0
        if let marker = insert.range(of: "{cursor}") {
            back = insert[marker.upperBound...].count
            insert.removeSubrange(marker)
        }
        return Suggestion(name: name, display: display, insert: insert, description: description, kind: kind,
                          priority: priority, replace: replace, cursorBack: back, icon: icon)
    }
}
