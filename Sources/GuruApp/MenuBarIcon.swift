import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Same 130-unit layout as Scripts/make-icon.swift, cropped to the artwork.
            ctx.scaleBy(x: 0.2, y: 0.2)
            ctx.translateBy(x: -23, y: -27)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            ctx.setLineWidth(9)
            ctx.move(to: CGPoint(x: 28, y: 32))
            ctx.addLine(to: CGPoint(x: 46, y: 45))
            ctx.addLine(to: CGPoint(x: 28, y: 58))
            ctx.strokePath()

            ctx.addPath(CGPath(roundedRect: CGRect(x: 56, y: 50, width: 24, height: 8), cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()

            ctx.setLineWidth(6)
            ctx.addPath(CGPath(roundedRect: CGRect(x: 47, y: 71, width: 62, height: 40), cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.strokePath()

            ctx.addPath(CGPath(roundedRect: CGRect(x: 57, y: 80, width: 42, height: 9), cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 57, y: 95, width: 28, height: 7), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TermGuru"
        return image
    }
}
