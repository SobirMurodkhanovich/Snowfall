import Cocoa

/// A small floating panel that shows the snowplow and catches double-clicks on it.
///
/// The snow overlay lets every click through, so the snowplow needs a window of its own. It is a
/// non-activating panel: clicking it does not take focus away from the app you are working in, and
/// clicks on its transparent parts still go through to whatever is underneath.
final class SnowplowPanel: NSPanel {
    let plowView = SnowplowView(frame: NSRect(x: 0, y: 0, width: Snowplow.viewWidth, height: Snowplow.viewHeight))

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Snowplow.viewWidth, height: Snowplow.viewHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false // the app is never "active", so this must stay off
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = plowView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Draws the light-blue snowplow truck with Core Graphics. Drawn facing right, mirrored when facing left.
final class SnowplowView: NSView {
    var look = Snowplow.Look(facingLeft: true, bladeLift: 1, heap: 0, wheelTurn: 0, beaconOn: false) {
        didSet { if look != oldValue { needsDisplay = true } }
    }
    var onDoubleClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        if look.facingLeft {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        drawHeap(ctx)
        drawChassisAndBox(ctx)
        drawCab(ctx)
        drawPlow(ctx)
        drawWheel(ctx, center: CGPoint(x: 32, y: 9))
        drawWheel(ctx, center: CGPoint(x: 80, y: 9))
    }

    // MARK: - Parts (facing right, ground at y = 0)

    /// Snow pushed along in front of the blade.
    private func drawHeap(_ ctx: CGContext) {
        guard look.heap > 0.01 else { return }
        let width = CGFloat(8 + 34 * look.heap)
        let height = CGFloat(4 + 20 * look.heap)
        let start: CGFloat = 103
        let heap = CGMutablePath()
        heap.move(to: CGPoint(x: start, y: 0))
        heap.addCurve(
            to: CGPoint(x: start + width * 0.45, y: height),
            control1: CGPoint(x: start, y: height * 0.8),
            control2: CGPoint(x: start + width * 0.2, y: height)
        )
        heap.addCurve(
            to: CGPoint(x: start + width, y: 0),
            control1: CGPoint(x: start + width * 0.75, y: height),
            control2: CGPoint(x: start + width * 0.95, y: height * 0.4)
        )
        heap.closeSubpath()
        ctx.addPath(heap)
        ctx.setFillColor(Palette.snow)
        ctx.fillPath()
        ctx.addPath(heap)
        ctx.setStrokeColor(Palette.snowShade)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    private func drawChassisAndBox(_ ctx: CGContext) {
        // Frame rail along the bottom.
        fillAndOutline(ctx, CGPath(rect: CGRect(x: 18, y: 8, width: 78, height: 6), transform: nil), Palette.chassis, lineWidth: 0.8)

        // Exhaust stack behind the cab.
        fillAndOutline(ctx, CGPath(rect: CGRect(x: 58.5, y: 36, width: 2.6, height: 16), transform: nil), Palette.steel, lineWidth: 0.6)

        // Spreader box at the back, with ribs and a darker rim.
        let box = CGRect(x: 14, y: 14, width: 46, height: 22)
        fillAndOutline(ctx, CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil), Palette.blue)
        ctx.setStrokeColor(Palette.blueDark)
        ctx.setLineWidth(1.6)
        for rx in [25.0, 35.0, 45.0] {
            ctx.move(to: CGPoint(x: rx, y: 17))
            ctx.addLine(to: CGPoint(x: rx, y: 33))
        }
        ctx.strokePath()
        fillAndOutline(ctx, CGPath(rect: CGRect(x: 12, y: 34, width: 50, height: 4), transform: nil), Palette.blueDark, lineWidth: 0.8)
        // Orange-and-white warning stripe at the back.
        ctx.setFillColor(Palette.orange)
        ctx.fill(CGRect(x: 14.5, y: 16, width: 3, height: 6))
    }

    private func drawCab(_ ctx: CGContext) {
        let cab = CGMutablePath()
        cab.move(to: CGPoint(x: 62, y: 14))
        cab.addLine(to: CGPoint(x: 97, y: 14))
        cab.addLine(to: CGPoint(x: 97, y: 27))
        cab.addLine(to: CGPoint(x: 90, y: 29))
        cab.addLine(to: CGPoint(x: 85, y: 48))
        cab.addLine(to: CGPoint(x: 62, y: 48))
        cab.closeSubpath()
        fillAndOutline(ctx, cab, Palette.blue)

        // Roof highlight and door handle.
        ctx.setStrokeColor(Palette.blueLight)
        ctx.setLineWidth(1.4)
        ctx.move(to: CGPoint(x: 64.5, y: 45.8))
        ctx.addLine(to: CGPoint(x: 83.5, y: 45.8))
        ctx.strokePath()
        ctx.setFillColor(Palette.outline)
        ctx.fill(CGRect(x: 70, y: 27, width: 4, height: 1.2))

        // Side window with a reflection, and the windshield seen edge-on.
        let window = CGMutablePath()
        window.move(to: CGPoint(x: 66, y: 31))
        window.addLine(to: CGPoint(x: 82, y: 31))
        window.addLine(to: CGPoint(x: 80.5, y: 44))
        window.addLine(to: CGPoint(x: 66, y: 44))
        window.closeSubpath()
        fillAndOutline(ctx, window, Palette.glass, lineWidth: 0.8)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.setLineWidth(1.4)
        ctx.move(to: CGPoint(x: 69, y: 34))
        ctx.addLine(to: CGPoint(x: 72, y: 41))
        ctx.strokePath()
        ctx.setStrokeColor(Palette.glass)
        ctx.setLineWidth(2.4)
        ctx.move(to: CGPoint(x: 88.4, y: 31))
        ctx.addLine(to: CGPoint(x: 84.8, y: 46))
        ctx.strokePath()

        // Grille and headlight.
        ctx.setStrokeColor(Palette.outline)
        ctx.setLineWidth(0.8)
        for gy in [18.0, 20.5, 23.0] {
            ctx.move(to: CGPoint(x: 93, y: gy))
            ctx.addLine(to: CGPoint(x: 96.5, y: gy))
        }
        ctx.strokePath()
        ctx.setFillColor(Palette.headlight)
        ctx.fillEllipse(in: CGRect(x: 93.5, y: 24.5, width: 3.4, height: 2.6))

        // Beacon on the roof, flashing while it works.
        let beacon = CGRect(x: 71, y: 48, width: 7, height: 4)
        if look.beaconOn {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 0.35))
            ctx.fillEllipse(in: beacon.insetBy(dx: -5, dy: -5))
        }
        fillAndOutline(
            ctx, CGPath(roundedRect: beacon, cornerWidth: 2, cornerHeight: 2, transform: nil),
            look.beaconOn ? Palette.beaconOn : Palette.beaconOff, lineWidth: 0.8
        )
    }

    private func drawPlow(_ ctx: CGContext) {
        let lift = CGFloat(8 * look.bladeLift)

        // Bumper and push arms.
        fillAndOutline(ctx, CGPath(rect: CGRect(x: 92, y: 10, width: 8, height: 5), transform: nil), Palette.steel, lineWidth: 0.8)
        thickLine(ctx, CGPoint(x: 96, y: 13), CGPoint(x: 104, y: 7 + lift), width: 3, color: Palette.steel)

        // Curved orange blade with a steel cutting edge.
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 109, y: lift))
        blade.addQuadCurve(to: CGPoint(x: 111, y: 24 + lift), control: CGPoint(x: 100, y: 9 + lift))
        blade.addLine(to: CGPoint(x: 107, y: 25 + lift))
        blade.addQuadCurve(to: CGPoint(x: 104, y: 1 + lift), control: CGPoint(x: 96, y: 10 + lift))
        blade.closeSubpath()
        fillAndOutline(ctx, blade, Palette.orange)
        thickLine(ctx, CGPoint(x: 104.5, y: 0.8 + lift), CGPoint(x: 109, y: 0.4 + lift), width: 1.6, color: Palette.steelLight)
    }

    private func drawWheel(_ ctx: CGContext, center: CGPoint) {
        // Fender arch above the wheel.
        ctx.setStrokeColor(Palette.blueDark)
        ctx.setLineWidth(3)
        ctx.addArc(center: center, radius: 11, startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
        ctx.strokePath()

        ctx.setFillColor(Palette.tire)
        ctx.fillEllipse(in: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18))
        ctx.setFillColor(Palette.steelLight)
        ctx.fillEllipse(in: CGRect(x: center.x - 4.6, y: center.y - 4.6, width: 9.2, height: 9.2))

        // Wheel nuts turn as it drives (clockwise when moving right).
        ctx.setFillColor(Palette.chassis)
        for k in 0..<3 {
            let angle = -CGFloat(look.wheelTurn) + CGFloat(k) * 2 * .pi / 3
            let nut = CGPoint(x: center.x + cos(angle) * 2.6, y: center.y + sin(angle) * 2.6)
            ctx.fillEllipse(in: CGRect(x: nut.x - 1, y: nut.y - 1, width: 2, height: 2))
        }
    }

    // MARK: - Helpers

    private func fillAndOutline(_ ctx: CGContext, _ path: CGPath, _ fill: CGColor, lineWidth: CGFloat = 1) {
        ctx.addPath(path)
        ctx.setFillColor(fill)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(Palette.outline)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
    }

    private func thickLine(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, width: CGFloat, color: CGColor) {
        ctx.setStrokeColor(Palette.outline)
        ctx.setLineWidth(width + 2)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
    }

    private enum Palette {
        static let blue = CGColor(srgbRed: 0.56, green: 0.80, blue: 0.95, alpha: 1)
        static let blueDark = CGColor(srgbRed: 0.38, green: 0.63, blue: 0.84, alpha: 1)
        static let blueLight = CGColor(srgbRed: 0.82, green: 0.94, blue: 1.0, alpha: 1)
        static let outline = CGColor(srgbRed: 0.10, green: 0.20, blue: 0.32, alpha: 0.9)
        static let chassis = CGColor(srgbRed: 0.22, green: 0.24, blue: 0.27, alpha: 1)
        static let tire = CGColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1)
        static let steel = CGColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1)
        static let steelLight = CGColor(srgbRed: 0.76, green: 0.79, blue: 0.83, alpha: 1)
        static let glass = CGColor(srgbRed: 0.20, green: 0.33, blue: 0.46, alpha: 1)
        static let orange = CGColor(srgbRed: 1.0, green: 0.55, blue: 0.10, alpha: 1)
        static let headlight = CGColor(srgbRed: 1.0, green: 0.95, blue: 0.70, alpha: 1)
        static let beaconOn = CGColor(srgbRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
        static let beaconOff = CGColor(srgbRed: 0.78, green: 0.47, blue: 0.16, alpha: 1)
        static let snow = CGColor(srgbRed: 0.99, green: 0.99, blue: 1.0, alpha: 1)
        static let snowShade = CGColor(srgbRed: 0.72, green: 0.80, blue: 0.90, alpha: 1)
    }
}
