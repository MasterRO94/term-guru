import AppKit
import SwiftUI
import GuruCore

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PopupController {
    let model = PopupModel()
    var onPick: ((Int) -> Void)?
    private let panel: PopupPanel
    private var caret: CGRect?
    private var anchorX: CGFloat?
    private var anchorKey = ""
    /// Tests run without a window server target; the popup then exists only logically.
    private let headless = ProcessInfo.processInfo.environment["GURU_HEADLESS"] != nil
    private(set) var isVisible = false

    private static let size = CGSize(
        width: PopupMetrics.listWidth + PopupMetrics.spacing + PopupMetrics.detailWidth + 40,
        height: PopupMetrics.listHeight(rows: PopupMetrics.maxRowsLimit, maxRows: PopupMetrics.maxRowsLimit) + 60
    )

    init() {
        panel = PopupPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let root = PopupView(model: model) { [weak self] index in self?.onPick?(index) }
            .padding(20)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: Self.size)
        panel.contentView = host
    }

    func show(_ items: [Suggestion]) {
        model.items = items
        model.selected = 0
        layout()
        isVisible = true
        if !headless, !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        isVisible = false
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// `key` identifies the word being completed; the popup keeps its x while that word is typed.
    func setCaret(_ rect: CGRect, key: String) {
        if key != anchorKey || anchorX == nil {
            anchorKey = key
            anchorX = rect.minX
        }
        caret = rect
        layout()
    }

    /// Panel frame in top-left screen coordinates, as `screencapture -R` expects.
    var captureRect: CGRect { CaretLocator.flip(panel.frame) }

    private func layout() {
        guard let caret else { return }
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(caret.origin) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let inset: CGFloat = 20
        let contentHeight = PopupMetrics.listHeight(rows: model.items.count, maxRows: model.maxRows)
        let contentWidth = PopupMetrics.listWidth + PopupMetrics.spacing + PopupMetrics.detailWidth
        var x = (anchorX ?? caret.minX) - 10
        x = min(max(x, visible.minX + 4), visible.maxX - contentWidth - 4)

        let gap: CGFloat = 4
        let fitsBelow = caret.minY - gap - contentHeight >= visible.minY
        // The hosting view is top-aligned, so the content's top edge sits `inset` below the panel's top.
        let contentTop = fitsBelow ? caret.minY - gap : caret.maxY + gap + contentHeight
        let origin = CGPoint(x: x - inset, y: contentTop + inset - Self.size.height)
        panel.setFrame(CGRect(origin: origin, size: Self.size), display: true)
    }
}
