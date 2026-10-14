import AppKit

// An original Locus icon; the upstream Search mark is not distributed.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale, s = CGFloat(size)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.09, y: s * 0.09, width: s * 0.82, height: s * 0.82),
            xRadius: s * 0.18, yRadius: s * 0.18).fill()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.26, y: s * 0.26, width: s * 0.11, height: s * 0.48),
            xRadius: s * 0.04, yRadius: s * 0.04).fill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.26, y: s * 0.26, width: s * 0.48, height: s * 0.11),
            xRadius: s * 0.04, yRadius: s * 0.04).fill()
        NSColor(red: 0.73, green: 0.87, blue: 0.59, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: s * 0.52, y: s * 0.52, width: s * 0.16, height: s * 0.16)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
