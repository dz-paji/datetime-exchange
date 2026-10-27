import AppKit

func renderIcon(size: Int, destination: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.38, blue: 0.29, alpha: 1), ending: NSColor(srgbRed: 0.055, green: 0.18, blue: 0.15, alpha: 1))!.draw(in: background, angle: -90)
    let ring = NSBezierPath(ovalIn: NSRect(x: 250, y: 330, width: 524, height: 524))
    NSColor(srgbRed: 0.93, green: 0.98, blue: 0.94, alpha: 1).setStroke()
    ring.lineWidth = 32
    ring.stroke()
    let hands = NSBezierPath()
    hands.move(to: NSPoint(x: 512, y: 752))
    hands.line(to: NSPoint(x: 512, y: 592))
    hands.line(to: NSPoint(x: 646, y: 520))
    hands.lineWidth = 39
    hands.lineCapStyle = .round
    hands.lineJoinStyle = .round
    hands.stroke()
    NSColor(srgbRed: 0.56, green: 0.85, blue: 0.69, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 312, y: 149, width: 400, height: 151), xRadius: 69, yRadius: 69).fill()
    let label = NSAttributedString(string: "+8", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 108, weight: .semibold), .foregroundColor: NSColor(srgbRed: 0.055, green: 0.22, blue: 0.16, alpha: 1)])
    let textSize = label.size()
    label.draw(at: NSPoint(x: (1024 - textSize.width) / 2, y: 149 + (151 - textSize.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    try renderIcon(size: points * scale, destination: directory.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
}
