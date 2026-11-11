import Foundation

public struct AppStatus: Sendable {
    public var pid: Int
    public var shellPIDs: [Int]
    public var idePIDs: [Int]
    public var paused: Bool
    public var accessibility: Bool
    public var popupVisible: Bool
}

public enum AppControl {
    public static func request(_ arguments: [String], timeout: TimeInterval = 3) -> String? {
        guard let client = SocketClient() else { return nil }
        guard client.send(Wire.join(["C"] + arguments)) else { return nil }
        return client.readLine(timeout: timeout)
    }

    public static func status() -> AppStatus? {
        guard let reply = request(["status"]),
              let object = try? JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any]
        else { return nil }
        let shells = (object["shells"] as? [[String: Any]] ?? []).compactMap { $0["pid"] as? Int }
        return AppStatus(
            pid: object["pid"] as? Int ?? 0,
            shellPIDs: shells,
            idePIDs: object["ides"] as? [Int] ?? [],
            paused: object["paused"] as? Bool ?? false,
            accessibility: object["accessibility"] as? Bool ?? false,
            popupVisible: object["popup"] as? Bool ?? false
        )
    }

    public static var isRunning: Bool { SocketClient() != nil }

    @discardableResult
    public static func start() -> Bool {
        if isRunning { return true }
        let candidates = [GuruPaths.installedApp, GuruResources.root.deletingLastPathComponent().deletingLastPathComponent()]
        guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/TermGuru").path) })
        else { return false }
        _ = Shell.run(["open", "-g", app.path])
        for _ in 0..<30 {
            if isRunning { return true }
            usleep(100_000)
        }
        return false
    }

    public static func stop() {
        _ = request(["quit"], timeout: 1)
    }
}
