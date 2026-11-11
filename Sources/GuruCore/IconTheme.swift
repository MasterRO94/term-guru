import Foundation

/// Picks Material Icon Theme icons (`Scripts/fetch-icons.sh`) for files, folders, commands and Fig types.
/// Every lookup returns an icon id; `url(_:)` gives its SVG.
public final class IconTheme: @unchecked Sendable {
    private struct Names {
        var extensions: [String: String] = [:]
        var files: [String: String] = [:]
        var folders: [String: String] = [:]

        init(_ object: [String: Any]?) {
            extensions = Self.lowercased(object?["fileExtensions"])
            files = Self.lowercased(object?["fileNames"])
            folders = Self.lowercased(object?["folderNames"])
        }

        private static func lowercased(_ value: Any?) -> [String: String] {
            var out: [String: String] = [:]
            for (key, id) in value as? [String: String] ?? [:] { out[key.lowercased()] = id }
            return out
        }
    }

    public let directory: URL
    private let dark: Names
    private let light: Names
    /// Icon id to its SVG file name, which differs for generated variants (`folder-redis.clone.svg`).
    private let files: [String: String]
    private var ids: Dictionary<String, String>.Keys { files.keys }
    private let defaultFile: String
    private let defaultFolder: String

    public init?(directory: URL) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("material-icons.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        self.directory = directory
        dark = Names(manifest)
        light = Names(manifest["light"] as? [String: Any])
        var files: [String: String] = [:]
        for (id, definition) in manifest["iconDefinitions"] as? [String: [String: Any]] ?? [:] {
            guard let path = definition["iconPath"] as? String else { continue }
            files[id] = (path as NSString).lastPathComponent
        }
        self.files = files
        defaultFile = manifest["file"] as? String ?? "file"
        defaultFolder = manifest["folder"] as? String ?? "folder"
    }

    public func url(_ id: String) -> URL { directory.appendingPathComponent(files[id] ?? id + ".svg") }

    public func file(_ name: String, light useLight: Bool = false) -> String {
        let lower = name.lowercased()
        if let id = lookup(\.files, lower, useLight) { return id }
        // Longest extension first, so `a.d.ts` is a declaration file before it is TypeScript.
        var rest = Substring(lower)
        while let dot = rest.firstIndex(of: ".") {
            rest = rest[rest.index(after: dot)...]
            if !rest.isEmpty, let id = lookup(\.extensions, String(rest), useLight) { return id }
        }
        return variant(defaultFile, useLight)
    }

    public func folder(_ name: String, light useLight: Bool = false) -> String {
        let lower = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return lookup(\.folders, lower, useLight) ?? variant(defaultFolder, useLight)
    }

    /// A tool's logo, or nil for commands the theme has nothing specific for.
    public func command(_ name: String, light useLight: Bool = false) -> String? {
        let lower = name.lowercased()
        let id = Self.commandIcons[lower] ?? (Self.genericIDs.contains(lower) ? nil : lower)
        guard let id, ids.contains(id) else { return nil }
        return variant(id, useLight)
    }

    /// Fig's brand types; generic ones (`string`, `option`…) stay with SF Symbols. `git` marks branches and refs,
    /// which read better as the branch symbol than as the git logo.
    public func fig(_ type: String, light useLight: Bool = false) -> String? {
        guard let id = Self.figIcons[type], ids.contains(id) else { return nil }
        return variant(id, useLight)
    }

    private func lookup(_ table: KeyPath<Names, [String: String]>, _ key: String, _ useLight: Bool) -> String? {
        if useLight, let id = light[keyPath: table][key] { return id }
        return dark[keyPath: table][key].map { variant($0, useLight) }
    }

    private func variant(_ id: String, _ useLight: Bool) -> String {
        useLight && ids.contains(id + "_light") ? id + "_light" : id
    }

    /// Commands whose logo has another name. Any other command whose name is a theme icon id gets that icon.
    static let commandIcons: [String: String] = [
        "node": "nodejs", "nvm": "nodejs", "corepack": "nodejs", "npx": "npm", "pnpx": "pnpm", "bunx": "bun",
        "yarnpkg": "yarn", "tsc": "typescript", "ts-node": "typescript", "tsx": "typescript", "ng": "angular",
        "python3": "python", "pip": "python", "pip3": "python", "pipx": "python", "pyenv": "python",
        "poetry": "python", "uv": "python", "ipython": "python",
        "cargo": "rust", "rustc": "rust", "rustup": "rust", "gofmt": "go", "swiftc": "swift",
        "gem": "ruby", "bundle": "ruby", "bundler": "ruby", "rake": "ruby", "irb": "ruby",
        "javac": "java", "mvn": "maven", "gradlew": "gradle", "kotlinc": "kotlin", "sbt": "scala",
        "mix": "elixir", "iex": "elixir", "erl": "erlang", "ghc": "haskell", "ghci": "haskell",
        "cabal": "haskell", "stack": "haskell", "luarocks": "lua", "rscript": "r", "pwsh": "powershell",
        "composer": "php", "artisan": "laravel", "nix-shell": "nix", "nix-env": "nix",
        "kubectl": "kubernetes", "kubectx": "kubernetes", "kubens": "kubernetes", "k9s": "kubernetes",
        "kind": "kubernetes", "docker-compose": "docker", "tf": "terraform", "az": "azure",
        "gcloud": "gcp", "gsutil": "gcp", "make": "makefile", "gmake": "makefile",
        "code": "vscode", "vi": "vim", "nvim": "vim",
    ]

    /// Theme ids that name a kind of file, not a tool: a command called `lock` is not a lock file.
    static let genericIDs: Set<String> = [
        "file", "folder", "document", "console", "settings", "lock", "key", "image", "video", "audio",
        "readme", "license", "tune", "certificate", "log", "font", "table", "template", "test",
    ]

    static let figIcons: [String: String] = [
        "docker": "docker", "npm": "npm", "node": "nodejs", "kubernetes": "kubernetes",
        "yarn": "yarn", "gitlab": "gitlab", "android": "android", "php": "php", "md": "markdown",
    ]
}
