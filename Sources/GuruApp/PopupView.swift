import SwiftUI
import GuruCore

enum PopupMetrics {
    static let rowHeight: CGFloat = 26
    static let maxRowsLimit = 14
    static let listWidth: CGFloat = 320
    static let detailWidth: CGFloat = 250
    static let padding: CGFloat = 6
    static let spacing: CGFloat = 6
    static let corner: CGFloat = 14

    static func listHeight(rows: Int, maxRows: Int) -> CGFloat {
        CGFloat(min(max(rows, 1), maxRows)) * rowHeight + padding * 2
    }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    var onPick: (Int) -> Void

    var body: some View {
        GlassEffectContainer(spacing: PopupMetrics.spacing) {
            HStack(alignment: .top, spacing: PopupMetrics.spacing) {
                list
                if model.showDetails, let item = model.current, !item.description.isEmpty {
                    DetailCard(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                        SuggestionRow(item: item, isSelected: index == model.selected)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(index) }
                    }
                }
                .padding(PopupMetrics.padding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selected) { _, selected in proxy.scrollTo(selected) }
            .onChange(of: model.items) { _, _ in proxy.scrollTo(0, anchor: .top) }
        }
        .frame(width: PopupMetrics.listWidth, height: PopupMetrics.listHeight(rows: model.items.count, maxRows: model.maxRows))
        .glassEffect(.regular, in: .rect(cornerRadius: PopupMetrics.corner))
    }
}

private struct SuggestionRow: View {
    let item: Suggestion
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(item.kind.tint))
                .frame(width: 18)
            Text(item.display)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: PopupMetrics.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: PopupMetrics.corner - PopupMetrics.padding, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DetailCard: View {
    let item: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(item.kind.label, systemImage: item.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.kind.tint)
            Text(item.display)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(2)
            Text(item.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: PopupMetrics.detailWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: PopupMetrics.corner))
    }
}
