import SwiftUI
import GuruCore

/// SF Symbols for `fig://icon?type=…`; brand types get theme logos instead (`IconTheme.fig`).
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

/// SF Symbols by lowercased file extension, for builds without the icon theme.
enum FileIcons {
    static func symbol(forFile name: String) -> String? {
        let ext = (name as NSString).pathExtension
        // `.env` has no extension to NSString; its name is the type.
        return symbols[ext.isEmpty && name.hasPrefix(".") ? String(name.dropFirst()).lowercased() : ext.lowercased()]
    }

    static let symbols: [String: String] = {
        var table: [String: String] = [
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

/// Theme SVGs, decoded once each.
enum ThemeIcons {
    static let theme = IconTheme(directory: GuruResources.icons)
    private static var images: [String: NSImage] = [:]

    static func image(_ id: String) -> NSImage? {
        if let hit = images[id] { return hit }
        guard let theme, let image = NSImage(contentsOf: theme.url(id)) else { return nil }
        images[id] = image
        return image
    }
}

struct SuggestionIconView: View {
    let item: Suggestion
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View { view(for: item.icon) }

    private func view(for icon: SuggestionIcon?) -> AnyView {
        let theme = ThemeIcons.theme
        let light = colorScheme == .light
        switch icon {
        case let .emoji(text)?:
            // Emoji and logos keep their own colors on the selected row.
            return AnyView(Text(text).font(.system(size: 12)))
        case let .template(color, badge)?:
            return AnyView(TemplateIcon(hex: color, badge: badge))
        case let .fig(type)?:
            if let id = theme?.fig(type, light: light), let logo = logo(id) { return logo }
            return symbol(FigIcons.symbols[type])
        case let .file(name)?:
            if let id = theme?.file(name, light: light), let logo = logo(id) { return logo }
            return symbol(FileIcons.symbol(forFile: name))
        case let .folder(name)?:
            if let id = theme?.folder(name, light: light), let logo = logo(id) { return logo }
            return symbol("folder")
        case let .command(name, fallback)?:
            if let id = theme?.command(name, light: light), let logo = logo(id) { return logo }
            return fallback.map { view(for: $0) } ?? symbol(nil)
        case nil:
            return symbol(nil)
        }
    }

    private func logo(_ id: String) -> AnyView? {
        guard let image = ThemeIcons.image(id) else { return nil }
        return AnyView(Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(width: 15, height: 15))
    }

    private func symbol(_ name: String?) -> AnyView {
        AnyView(Image(systemName: name ?? item.kind.symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(item.kind.tint)))
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
