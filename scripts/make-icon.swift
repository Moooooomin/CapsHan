import AppKit

// Usage: swift make-icon.swift <output.iconset>
// Draws the app icon ("가A" on a blue rounded square) at every size iconutil needs.
let outputDirectory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(pixels)
    // macOS icon grid: the body sits inside a 100/1024 margin.
    let body = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 100 / 1024, dy: side * 100 / 1024)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.01)
    shadow.shadowBlurRadius = side * 0.02
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.24, green: 0.33, blue: 0.86, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.42, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.80, alpha: 1))!
        .draw(in: shape, angle: -90)

    let text = "가A" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: side * 0.34, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2), withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, pixels) in sizes {
    try renderIcon(pixels: pixels).write(to: URL(fileURLWithPath: "\(outputDirectory)/icon_\(name).png"))
}
