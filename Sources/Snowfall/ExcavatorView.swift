import Cocoa

/// A small floating panel that shows the excavator and catches double-clicks on it.
///
/// The snow overlay lets every click through, so the excavator needs a window of its own. It is a
/// non-activating panel: clicking it does not take focus away from the app you are working in, and
/// clicks on its transparent parts still go through to whatever is underneath.
final class ExcavatorPanel: NSPanel {
    let excavatorView = ExcavatorView(frame: NSRect(x: 0, y: 0, width: Excavator.viewWidth, height: Excavator.viewHeight))

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Excavator.viewWidth, height: Excavator.viewHeight),
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
        contentView = excavatorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Draws the excavator with Core Graphics. Drawn facing right and mirrored when facing left.
final class ExcavatorView: NSView {
    var look = Excavator.Look(facingLeft: true, armLift: 1, bucketTip: 0, heap: 0, trackOffset: 0) {
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
        drawTracks(ctx)
        drawBody(ctx)
        drawArm(ctx)
    }

    // MARK: - Parts (facing right, ground at y = 0)

    private func drawTracks(_ ctx: CGContext) {
        let track = CGRect(x: 36, y: 1, width: 58, height: 12)
        let trackPath = CGPath(roundedRect: track, cornerWidth: 6, cornerHeight: 6, transform: nil)
        fillAndOutline(ctx, trackPath, Palette.dark)

        // Tread plates running round the track as it drives.
        ctx.saveGState()
        ctx.addPath(trackPath)
        ctx.clip()
        ctx.setFillColor(Palette.steel)
        let offset = CGFloat(look.trackOffset)
        var x = track.minX - 5 + offset
        while x < track.maxX + 5 {
            ctx.fill(CGRect(x: x, y: track.maxY - 1.6, width: 2.2, height: 1.6))
            ctx.fill(CGRect(x: track.maxX + track.minX - x - 2.2, y: track.minY, width: 2.2, height: 1.6))
            x += 5
        }
        ctx.restoreGState()

        for cx in stride(from: 43.0, through: 87.0, by: 11.0) {
            ctx.setFillColor(Palette.steelLight)
            ctx.fillEllipse(in: CGRect(x: cx - 3.6, y: 3.4, width: 7.2, height: 7.2))
            ctx.setFillColor(Palette.dark)
            ctx.fillEllipse(in: CGRect(x: cx - 1.3, y: 5.7, width: 2.6, height: 2.6))
        }
    }

    private func drawBody(_ ctx: CGContext) {
        // Turntable between tracks and house.
        ctx.setFillColor(Palette.steel)
        ctx.fill(CGRect(x: 46, y: 13, width: 38, height: 3.5))

        // Counterweight at the back, then the engine house.
        let counterweight = CGRect(x: 28, y: 17, width: 14, height: 14)
        fillAndOutline(ctx, CGPath(roundedRect: counterweight, cornerWidth: 5, cornerHeight: 5, transform: nil), Palette.yellowDark)
        let house = CGRect(x: 32, y: 16, width: 56, height: 16)
        fillAndOutline(ctx, CGPath(roundedRect: house, cornerWidth: 3, cornerHeight: 3, transform: nil), Palette.yellow)
        ctx.setFillColor(Palette.yellowDark)
        ctx.fill(CGRect(x: 33, y: 17, width: 54, height: 3))
        ctx.setFillColor(Palette.yellowLight)
        ctx.fill(CGRect(x: 34, y: 29.3, width: 52, height: 1.2))

        // Engine grille.
        ctx.setStrokeColor(Palette.outline)
        ctx.setLineWidth(1)
        for gx in stride(from: 38.0, through: 48.5, by: 3.5) {
            ctx.move(to: CGPoint(x: gx, y: 22))
            ctx.addLine(to: CGPoint(x: gx, y: 27.5))
        }
        ctx.strokePath()

        // Exhaust pipe.
        fillAndOutline(ctx, CGPath(rect: CGRect(x: 41, y: 32, width: 3, height: 8), transform: nil), Palette.dark, lineWidth: 0.6)

        // Cab with its window and a small reflection.
        let cab = CGRect(x: 58, y: 31, width: 22, height: 24)
        fillAndOutline(ctx, CGPath(roundedRect: cab, cornerWidth: 3, cornerHeight: 3, transform: nil), Palette.yellow)
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: 61, y: 35))
        glass.addLine(to: CGPoint(x: 77, y: 35))
        glass.addLine(to: CGPoint(x: 77, y: 51))
        glass.addLine(to: CGPoint(x: 65, y: 51))
        glass.addLine(to: CGPoint(x: 61, y: 46))
        glass.closeSubpath()
        fillAndOutline(ctx, glass, Palette.glass, lineWidth: 0.8)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.7))
        ctx.setLineWidth(1.4)
        ctx.move(to: CGPoint(x: 66, y: 39))
        ctx.addLine(to: CGPoint(x: 70, y: 47))
        ctx.strokePath()

        // Orange beacon on the roof.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.45, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 67, y: 55, width: 4, height: 2.5))
    }

    private func drawArm(_ ctx: CGContext) {
        let lift = CGFloat(look.armLift)
        func between(_ down: CGPoint, _ up: CGPoint) -> CGPoint {
            CGPoint(x: down.x + (up.x - down.x) * lift, y: down.y + (up.y - down.y) * lift)
        }
        let shoulder = CGPoint(x: 82, y: 26)
        let elbow = between(CGPoint(x: 98, y: 44), CGPoint(x: 103, y: 60))
        let wrist = between(CGPoint(x: 110, y: 14), CGPoint(x: 117, y: 40))

        // Hydraulic ram under the boom, then boom and stick.
        let ramEnd = CGPoint(x: shoulder.x + (elbow.x - shoulder.x) * 0.55, y: shoulder.y + (elbow.y - shoulder.y) * 0.55)
        thickLine(ctx, CGPoint(x: 74, y: 30), ramEnd, width: 2.6, color: Palette.steelLight)
        thickLine(ctx, shoulder, elbow, width: 7, color: Palette.yellow)
        thickLine(ctx, elbow, wrist, width: 5, color: Palette.yellowDark)

        drawBucket(ctx, at: wrist)

        ctx.setFillColor(Palette.steel)
        for pin in [shoulder, elbow, wrist] {
            ctx.fillEllipse(in: CGRect(x: pin.x - 1.8, y: pin.y - 1.8, width: 3.6, height: 3.6))
        }
    }

    private func drawBucket(_ ctx: CGContext, at wrist: CGPoint) {
        ctx.saveGState()
        ctx.translateBy(x: wrist.x, y: wrist.y)
        // Curled back while lifted so the snow stays in; tipped forward to empty it.
        ctx.rotate(by: CGFloat(0.45 * look.armLift - 2.3 * look.bucketTip))

        // Snow heaped above the bucket's opening (the line from the hinge to the teeth).
        if look.heap > 0.02 {
            let height = CGFloat(3 + 11 * look.heap)
            let heap = CGMutablePath()
            heap.move(to: CGPoint(x: 0.5, y: -0.5))
            heap.addQuadCurve(
                to: CGPoint(x: 16.5, y: -9.5),
                control: CGPoint(x: 8.5 + 0.507 * height * 2, y: -5 + 0.862 * height * 2)
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

        let shell = CGMutablePath()
        shell.move(to: .zero)
        shell.addLine(to: CGPoint(x: -3, y: -6))
        shell.addQuadCurve(to: CGPoint(x: 8, y: -13), control: CGPoint(x: -3, y: -14))
        shell.addLine(to: CGPoint(x: 17, y: -10))
        shell.closeSubpath()
        fillAndOutline(ctx, shell, Palette.steel)
        thickLine(ctx, CGPoint(x: 14.5, y: -9), CGPoint(x: 18.5, y: -11), width: 1.4, color: Palette.steelLight)

        ctx.restoreGState()
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
        static let yellow = CGColor(srgbRed: 0.98, green: 0.74, blue: 0.06, alpha: 1)
        static let yellowDark = CGColor(srgbRed: 0.86, green: 0.58, blue: 0.03, alpha: 1)
        static let yellowLight = CGColor(srgbRed: 1.0, green: 0.86, blue: 0.36, alpha: 1)
        static let outline = CGColor(srgbRed: 0.22, green: 0.17, blue: 0.06, alpha: 0.9)
        static let dark = CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        static let steel = CGColor(srgbRed: 0.45, green: 0.46, blue: 0.50, alpha: 1)
        static let steelLight = CGColor(srgbRed: 0.68, green: 0.70, blue: 0.74, alpha: 1)
        static let glass = CGColor(srgbRed: 0.62, green: 0.84, blue: 0.97, alpha: 1)
        static let snow = CGColor(srgbRed: 0.99, green: 0.99, blue: 1.0, alpha: 1)
        static let snowShade = CGColor(srgbRed: 0.72, green: 0.80, blue: 0.90, alpha: 1)
    }
}
