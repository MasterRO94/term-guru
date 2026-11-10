import Foundation

public enum EnterAction: String, Codable, Sendable, CaseIterable {
    case insert, execute
}

public struct GuruSettings: Codable, Equatable, Sendable {
    public var maxRows = 8
    public var historySuggestions = true
    public var showDetails = true
    public var enterAction = EnterAction.insert
    public var checkForUpdates = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxRows = try container.decodeIfPresent(Int.self, forKey: .maxRows) ?? 8
        historySuggestions = try container.decodeIfPresent(Bool.self, forKey: .historySuggestions) ?? true
        showDetails = try container.decodeIfPresent(Bool.self, forKey: .showDetails) ?? true
        enterAction = try container.decodeIfPresent(EnterAction.self, forKey: .enterAction) ?? .insert
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
    }

    public static func load() -> GuruSettings {
        guard let data = try? Data(contentsOf: GuruPaths.settings),
              let settings = try? JSONDecoder().decode(GuruSettings.self, from: data)
        else { return GuruSettings() }
        return settings
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: GuruPaths.config, withIntermediateDirectories: true)
        try? data.write(to: GuruPaths.settings, options: .atomic)
    }
}
