import SwiftUI
import GuruCore

/// SF Symbols for `fig://icon?type=…`. Brand types with no symbol (docker, npm, node, kubernetes…) are left out.
enum FigIcons {
    static let symbols: [String: String] = [
        "git": "arrow.triangle.branch",
        "commit": "smallcircle.filled.circle",
        "string": "textformat",
        "characters": "character.textbox",
        "asterisk": "asterisk",
        "package": "shippingbox",
        "box": "shippingbox",
        "command": "terminal",
        "commandkey": "command",
        "option": "flag",
        "alert": "exclamationmark.triangle",
        "cpu": "cpu",
        "apple": "apple.logo",
        "gear": "gearshape",
        "folder": "folder",
        "file": "doc",
        "txt": "doc.plaintext",
        "md": "doc.richtext",
        "invite": "person.badge.plus",
    ]
}

/// SF Symbols by lowercased file extension; "/" is a folder.
enum FileIcons {
    static let symbols: [String: String] = {
        var table: [String: String] = [
            "/": "folder",
            "swift": "swift",
            "json": "curlybraces.square",
            "md": "doc.richtext", "markdown": "doc.richtext",
            "txt": "doc.plaintext",
            "pdf": "doc.text",
            "env": "key",
            "html": "chevron.left.forwardslash.chevron.right", "xml": "chevron.left.forwardslash.chevron.right",
            "yml": "text.alignleft", "yaml": "text.alignleft", "toml": "text.alignleft",
            "csv": "tablecells", "tsv": "tablecells",
            "sql": "cylinder.split.1x2",
        ]
        for ext in ["js", "mjs", "cjs", "ts", "jsx", "tsx"] { table[ext] = "curlybraces" }
        for ext in ["sh", "zsh", "bash", "fish"] { table[ext] = "terminal" }
        for ext in ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "ico", "bmp", "tiff"] { table[ext] = "photo" }
        for ext in ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg"] { table[ext] = "doc.zipper" }
        for ext in ["mp4", "mov", "mkv", "webm"] { table[ext] = "film" }
        for ext in ["mp3", "wav", "flac", "m4a"] { table[ext] = "music.note" }
        return table
    }()
}

struct SuggestionIconView: View {
    let item: Suggestion
    let isSelected: Bool

    var body: some View {
        switch item.icon {
        case let .emoji(text)?:
            // Emoji keep their own colors on the selected row.
            Text(text).font(.system(size: 12))
        case let .template(color, badge)?:
            TemplateIcon(hex: color, badge: badge)
        case let .fig(type)?:
            symbol(FigIcons.symbols[type])
        case let .fileType(ext)?:
            symbol(FileIcons.symbols[ext])
        case nil:
            symbol(nil)
        }
    }

    private func symbol(_ name: String?) -> some View {
        Image(systemName: name ?? item.kind.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(item.kind.tint))
    }

    static func color(hex: String) -> Color? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }

    static func isLight(hex: String) -> Bool {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard let value = UInt32(digits, radix: 16) else { return false }
        let luma = 0.299 * Double(value >> 16 & 0xff) + 0.587 * Double(value >> 8 & 0xff) + 0.114 * Double(value & 0xff)
        return luma > 160
    }
}

private struct TemplateIcon: View {
    let hex: String?
    let badge: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(hex.flatMap(SuggestionIconView.color(hex:)) ?? Color.gray)
            .overlay(RoundedRectangle(cornerRadius: 3.5, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
            .overlay {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(hex.map(SuggestionIconView.isLight(hex:)) == true ? Color.black : Color.white)
                }
            }
            .frame(width: 14, height: 14)
    }
}
