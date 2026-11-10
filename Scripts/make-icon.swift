import AppKit
import SwiftUI
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let iconset = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

func fill(_ ctx: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32) {
    let box = path.boundingBoxOfPath
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1]
    )!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ hex: UInt32) {
    ctx.addPath(path)
    ctx.setFillColor(color(hex))
    ctx.fillPath()
}

func render(_ pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)

    // Apple's macOS icon grid: 824pt body centred on a 1024pt canvas.
    let body = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    ctx.saveGState()
    // Shadow offsets are in device space, where y points up.
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: color(0x000000, 0.35))
    fill(ctx, body, 0x0B1120)
    ctx.restoreGState()
    fill(ctx, body, top: 0x24324A, bottom: 0x0B1120)

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.addPath(body)
    ctx.setStrokeColor(color(0xFFFFFF, 0.10))
    ctx.setLineWidth(6)
    ctx.strokePath()
    ctx.restoreGState()

    // Artwork below is laid out in a 130-unit square.
    let unit: CGFloat = 824 / 130
    ctx.translateBy(x: 100, y: 100)
    ctx.scaleBy(x: unit, y: unit)
    ctx.translateBy(x: -3, y: -6)

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(9)
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.move(to: CGPoint(x: 24, y: 30))
    ctx.addLine(to: CGPoint(x: 44, y: 44))
    ctx.addLine(to: CGPoint(x: 24, y: 58))
    ctx.strokePath()

    fill(ctx, rounded(CGRect(x: 54, y: 50, width: 24, height: 8), 4), top: 0x7DD3FC, bottom: 0x38BDF8)

    let popup = rounded(CGRect(x: 44, y: 70, width: 68, height: 44), 9)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3 * unit * scale), blur: 7 * unit * scale, color: color(0x000000, 0.45))
    fill(ctx, popup, 0x2B3A52)
    ctx.restoreGState()
    fill(ctx, popup, top: 0x334560, bottom: 0x263347)
    ctx.addPath(popup)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.setLineWidth(0.8)
    ctx.strokePath()

    fill(ctx, rounded(CGRect(x: 50, y: 76, width: 56, height: 11), 4), top: 0x60A5FA, bottom: 0x2563EB)
    fill(ctx, rounded(CGRect(x: 54, y: 79.5, width: 30, height: 4), 2), 0xFFFFFF)
    fill(ctx, rounded(CGRect(x: 54, y: 93, width: 36, height: 4.5), 2.25), 0x94A3B8)
    fill(ctx, rounded(CGRect(x: 54, y: 103, width: 46, height: 4.5), 2.25), 0x94A3B8)

    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = iconset.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("failed to write \(url.path)\n".utf8))
        exit(1)
    }
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    write(render(points), "icon_\(points)x\(points).png")
    write(render(points * 2), "icon_\(points)x\(points)@2x.png")
}
