import SwiftUI
import GuruCore

final class PopupModel: ObservableObject {
    @Published var items: [Suggestion] = []
    @Published var selected = 0
    @Published var maxRows = 8
    @Published var showDetails = true

    var current: Suggestion? { items.indices.contains(selected) ? items[selected] : nil }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
    }
}

extension SuggestionKind {
    var symbol: String {
        switch self {
        case .command: "terminal"
        case .subcommand: "chevron.right.square"
        case .option: "flag"
        case .argument: "text.cursor"
        case .file: "doc"
        case .folder: "folder"
        case .alias: "link"
        case .history: "clock.arrow.circlepath"
        case .script: "play.square"
        }
    }

    var tint: Color {
        switch self {
        case .command: .blue
        case .subcommand: .indigo
        case .option: .orange
        case .argument: .teal
        case .file: .secondary
        case .folder: .cyan
        case .alias: .pink
        case .history: .purple
        case .script: .green
        }
    }

    var label: String {
        switch self {
        case .command: "Command"
        case .subcommand: "Subcommand"
        case .option: "Option"
        case .argument: "Argument"
        case .file: "File"
        case .folder: "Folder"
        case .alias: "Alias"
        case .history: "History"
        case .script: "Script"
        }
    }
}
