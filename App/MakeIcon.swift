import AppKit

// Compile the original, opaque artwork into a legacy macOS icon. Older systems
// render ICNS pixels directly, so the rounded silhouette must be in the asset.
// Usage: swift App/MakeIcon.swift App/Resources/AppIcon.png output.iconset
guard CommandLine.arguments.count == 3,
       let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: MakeIcon.swift artwork.png output.iconset")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in sizes {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.clear.setFill()
    canvas.fill(using: .copy)
    // A 1024px legacy canvas has a centered 824px body and transparent margins.
    let inset = CGFloat(pixels) * 100 / 1024
    let body = canvas.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.225
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).addClip()
    artwork.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    // Validate the actual exported pixels, not just the presence of an alpha flag.
    precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
    precondition(bitmap.colorAt(x: pixels / 2, y: pixels / 2)!.alphaComponent > 0.99)
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: directory.appendingPathComponent(name))
}
