// Draws the 1024×1024 app icon to the PNG path given as the first argument.
// Used by scripts/make-icon.sh, which turns it into Resources/AppIcon.icns.
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let size = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

// Drop shadow under the tile.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor(srgbRed: 0.07, green: 0.12, blue: 0.27, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()

// Night sky.
NSGradient(
    starting: NSColor(srgbRed: 0.05, green: 0.09, blue: 0.22, alpha: 1),
    ending: NSColor(srgbRed: 0.24, green: 0.43, blue: 0.74, alpha: 1)
)!.draw(in: tile, angle: -90)

// Small falling flakes.
let dots: [(CGFloat, CGFloat, CGFloat)] = [
    (190, 820, 9), (300, 720, 6), (250, 560, 7), (180, 430, 5), (820, 830, 8),
    (730, 740, 5), (850, 600, 10), (780, 450, 6), (420, 860, 5), (620, 880, 7),
    (360, 400, 6), (680, 390, 5), (900, 350, 4), (140, 650, 4), (560, 780, 4),
]
for (x, y, r) in dots {
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
}

// Big snowflake.
if let base = NSImage(systemSymbolName: "snowflake", accessibilityDescription: nil),
   let symbol = base.withSymbolConfiguration(.init(pointSize: 330, weight: .semibold)) {
    let s = symbol.size
    let white = NSImage(size: s, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    white.draw(in: NSRect(x: 512 - s.width / 2, y: 590 - s.height / 2, width: s.width, height: s.height))
}

// Snow pile along the bottom.
let pile = NSBezierPath()
pile.move(to: NSPoint(x: tile.minX, y: tile.minY))
pile.line(to: NSPoint(x: tile.minX, y: 275))
pile.curve(to: NSPoint(x: 450, y: 300),
           controlPoint1: NSPoint(x: 220, y: 335), controlPoint2: NSPoint(x: 340, y: 335))
pile.curve(to: NSPoint(x: tile.maxX, y: 255),
           controlPoint1: NSPoint(x: 580, y: 262), controlPoint2: NSPoint(x: 770, y: 320))
pile.line(to: NSPoint(x: tile.maxX, y: tile.minY))
pile.close()
NSGradient(
    starting: .white,
    ending: NSColor(srgbRed: 0.84, green: 0.90, blue: 0.98, alpha: 1)
)!.draw(in: pile, angle: -90)

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
