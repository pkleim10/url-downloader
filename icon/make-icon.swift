// Renders the Siphon app icon to icon/AppIcon.icns.
// Usage: swift icon/make-icon.swift   (from the project folder)
import AppKit

let canvas: CGFloat = 1024

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(size) / canvas
    ctx.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824pt tile centered on a 1024pt canvas
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.56, blue: 1.00, alpha: 1),
               ending: NSColor(srgbRed: 0.27, green: 0.22, blue: 0.82, alpha: 1))!
        .draw(in: tile, angle: -90)
    // Soft top highlight
    NSGradient(starting: NSColor.white.withAlphaComponent(0.22), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    ctx.restoreGState()

    // Glyph: arrow dropping into a tray
    ctx.saveGState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(srgbRed: 0.10, green: 0.08, blue: 0.40, alpha: 0.35)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -10)
    glyphShadow.shadowBlurRadius = 18
    glyphShadow.set()
    // One layer so the glyph casts a single shadow instead of one per stroke/fill
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.setFill()
    NSColor.white.setStroke()

    let arrow = NSBezierPath()
    let cx: CGFloat = 512
    arrow.move(to: CGPoint(x: cx - 52, y: 760))
    arrow.line(to: CGPoint(x: cx + 52, y: 760))
    arrow.line(to: CGPoint(x: cx + 52, y: 520))
    arrow.line(to: CGPoint(x: cx + 150, y: 520))
    arrow.line(to: CGPoint(x: cx, y: 360))
    arrow.line(to: CGPoint(x: cx - 150, y: 520))
    arrow.line(to: CGPoint(x: cx - 52, y: 520))
    arrow.close()
    arrow.lineJoinStyle = .round
    arrow.lineWidth = 24
    arrow.fill()
    arrow.stroke()

    let tray = NSBezierPath()
    tray.move(to: CGPoint(x: 290, y: 400))
    tray.line(to: CGPoint(x: 290, y: 270))
    tray.line(to: CGPoint(x: 734, y: 270))
    tray.line(to: CGPoint(x: 734, y: 400))
    tray.lineWidth = 64
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    tray.stroke()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconDir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("icon")
let iconset = iconDir.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(size: 1024).write(to: iconDir.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", iconDir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "✓ icon/AppIcon.icns" : "✗ iconutil failed")
