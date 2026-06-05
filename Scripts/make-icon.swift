import Cocoa

// Renders the DevScreenshot app icon to a 1024×1024 PNG.
// Usage: swift make-icon.swift [output.png]   (default: AppIcon.png)

_ = NSApplication.shared   // initialise AppKit for offscreen drawing in a CLI context

/// SF Symbol rendered as a solid white glyph on a transparent canvas.
func whiteGlyph(_ name: String, pointSize: CGFloat) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let conf = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    let glyph = base.withSymbolConfiguration(conf) ?? base
    let size = glyph.size
    let out = NSImage(size: size)
    out.lockFocus()
    glyph.draw(in: NSRect(origin: .zero, size: size))
    NSColor.white.set()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

let px = 1024
let S = CGFloat(px)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Could not create bitmap") }

let glyph = whiteGlyph("camera.viewfinder", pointSize: S * 0.46)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: S, height: S)
NSBezierPath(roundedRect: rect, xRadius: S * 0.2237, yRadius: S * 0.2237).addClip()

NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.51, blue: 1.00, alpha: 1),   // blue
    NSColor(srgbRed: 0.45, green: 0.30, blue: 0.95, alpha: 1)    // indigo
])!.draw(in: rect, angle: -45)

if let g = glyph {
    let gs = g.size
    g.draw(in: NSRect(x: (S - gs.width) / 2, y: (S - gs.height) / 2, width: gs.width, height: gs.height))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Could not encode PNG") }
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) (\(px)×\(px))")
