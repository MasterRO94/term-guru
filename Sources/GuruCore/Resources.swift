import Foundation

public enum GuruResources {
    static var executable: URL {
        // argv[0] is a bare name when launched through PATH, so it cannot locate the bundle.
        var size = UInt32(MAXPATHLEN)
        var buffer = [CChar](repeating: 0, count: Int(size))
        if _NSGetExecutablePath(&buffer, &size) != 0 {
            buffer = [CChar](repeating: 0, count: Int(size))
            _NSGetExecutablePath(&buffer, &size)
        }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }

    static var bundleContents: URL { executable.deletingLastPathComponent().deletingLastPathComponent() }

    /// Bundle resources when running from TermGuru.app, repo `Resources/` during development.
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["GURU_RESOURCES"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let bundled = bundleContents.appendingPathComponent("Resources")
        if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("shell").path) { return bundled }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }

    /// Fig specs plus the generated `tgr` spec; `Scripts/fetch-specs.sh` replaces this directory.
    public static var specs: URL { root.appendingPathComponent("specs", isDirectory: true) }
    /// Hand-written specs tracked in the repository.
    public static var customSpecs: URL { root.appendingPathComponent("custom-specs", isDirectory: true) }
    public static var specDirectories: [URL] { [GuruPaths.userSpecs, customSpecs, specs] }
    public static var shell: URL { root.appendingPathComponent("shell", isDirectory: true) }
}

public enum GuruVersion {
    /// build.sh stamps the VERSION file into the bundle; a bare `swift build` binary has no bundle.
    public static let current: String = {
        let plist = GuruResources.bundleContents.appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: plist), let version = info["CFBundleShortVersionString"] as? String {
            return version
        }
        return "dev"
    }()
}
