import AppKit
let output = CommandLine.arguments[1]
let icon = NSImage(size: NSSize(width: 1024, height: 1024))
icon.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 202, yRadius: 202)
NSGradient(starting: NSColor(white: 0.97, alpha: 1), ending: NSColor(white: 0.84, alpha: 1))!.draw(in: background, angle: -90)
let body = NSBezierPath(roundedRect: NSRect(x: 345, y: 188, width: 334, height: 648), xRadius: 145, yRadius: 145)
NSColor(srgbRed: 0.15, green: 0.17, blue: 0.20, alpha: 1).setFill(); body.fill()
let ring = NSBezierPath(ovalIn: NSRect(x: 387, y: 548, width: 250, height: 250))
NSColor(white: 0.82, alpha: 1).setFill(); ring.fill()
let center = NSBezierPath(ovalIn: NSRect(x: 455, y: 616, width: 114, height: 114))
NSColor(srgbRed: 0.18, green: 0.38, blue: 0.65, alpha: 1).setFill(); center.fill()
NSColor(white: 0.90, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 469, y: 291, width: 86, height: 174), xRadius: 43, yRadius: 43).fill()
icon.unlockFocus()
let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
