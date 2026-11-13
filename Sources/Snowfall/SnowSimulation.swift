import CoreGraphics
import Foundation
import QuartzCore

/// Where snow can settle on top of the Dock, in screen-local points.
struct Shelf: Equatable {
    var minX: Float
    var maxX: Float
    var top: Float
}

/// Everything that moves on one screen: falling flakes, snow lumps, swept-up puffs, and the piles
/// on the bottom of the screen and on top of windows. No drawing here.
final class SnowSimulation {
    struct Particle {
        var x: Float
        var y: Float
        /// Own sideways speed (lumps and puffs); snowflakes drift with wind and sway instead.
        var vx: Float
        /// Downward speed. Negative means flying up (puffs).
        var vy: Float
        /// 0 for snowflakes, which fall at a steady speed.
        let gravity: Float
        let radius: Float
        var alpha: Float
        /// Alpha lost per second (puffs fade away); 0 for everything else.
        let fade: Float
        let swayAmplitude: Float
        let swayFrequency: Float
        let phase: Float
        let windFactor: Float
        /// Snow (pt²) added where it lands; 0 = never lands.
        let area: Float
    }

    /// The top edge of a window, as far as it lies on this screen.
    struct Spot {
        let minX: Float
        let maxX: Float
        let top: Float
        /// Position in the front-to-back window list.
        var index: Int

        init?(frame: CGRect, index: Int, screenWidth: Float, screenHeight: Float) {
            top = Float(frame.maxY)
            // Stay off the rounded corners.
            minX = max(0, Float(frame.minX) + SnowSimulation.cornerInset)
            maxX = min(screenWidth, Float(frame.maxX) - SnowSimulation.cornerInset)
            self.index = index
            // Skip windows whose top is off this screen or in the menu bar, and slivers.
            guard top > 30, top < screenHeight - 2, maxX - minX >= 40 else { return nil }
        }

        func sameEdge(as other: Spot) -> Bool {
            abs(minX - other.minX) < 1 && abs(maxX - other.maxX) < 1 && abs(top - other.top) < 1
        }
    }

    /// Snow lying on top of one window.
    final class Ledge {
        var spot: Spot
        let pile: SnowPile
        /// The window is out of sight (another Space, hidden app): keep its snow but leave it alone.
        var isParked = false
        var parkedAt: CFTimeInterval = 0
        var spillLeft: Float = 0
        var spillRight: Float = 0

        init(spot: Spot) {
            self.spot = spot
            pile = SnowPile(
                originX: spot.minX, baseY: spot.top, width: spot.maxX - spot.minX,
                maxDepth: SnowSimulation.ledgeMaxDepth, openEnds: true
            )
        }
    }

    static let maxSnowflakes = 3000
    static let maxParticles = 4500
    fileprivate static let cornerInset: Float = 14
    fileprivate static let ledgeMaxDepth: Float = 26
    private static let groundMaxDepth: Float = 46
    private static let meltRate: Float = 0.025
    private static let brushRadius: Float = 24

    var isSnowing = true
    var intensity: Intensity = .medium
    var wind: Wind = .breeze
    /// Returns the mouse position (screen-local) while the left button is held down, else nil.
    var cursorProvider: (() -> SIMD2<Float>?)?

    let width: Float
    let height: Float
    /// Snow along the bottom of the screen and on the Dock.
    let base: SnowPile
    private(set) var particles: [Particle] = []
    private var ledges: [CGWindowID: Ledge] = [:]
    /// Ledges of windows currently on screen.
    private(set) var activeLedges: [Ledge] = []

    /// The excavator on the Dock (only on the screen that has the Dock).
    private(set) var excavator: Excavator?

    private var shelf: Shelf?
    private var clock: Float = 0
    private var spawnBudget: Float = 0
    private var snowflakeCount = 0

    /// Nothing falling, nothing lying in sight: the render loop can stop.
    var isIdle: Bool {
        !isSnowing && particles.isEmpty && base.isEmpty && activeLedges.allSatisfy { $0.pile.isEmpty }
            && !(excavator?.isBusy ?? false)
    }

    /// Where the excavator drives: along the top of the Dock, or the bottom of the screen.
    private var lane: ClosedRange<Float> {
        guard let shelf, shelf.maxX > shelf.minX else { return 0...width }
        return shelf.minX...shelf.maxX
    }

    init(width: Float, height: Float) {
        self.width = width
        self.height = height
        base = SnowPile(width: width, maxDepth: Self.groundMaxDepth)
    }

    func setShelf(_ newShelf: Shelf?) {
        guard newShelf != shelf else { return }
        shelf = newShelf
        base.setGround { x in
            guard let s = newShelf, x >= s.minX, x <= s.maxX else { return 0 }
            return s.top
        }
        excavator?.setLane(lane, groundY: shelf?.top ?? 0)
    }

    func setExcavatorEnabled(_ enabled: Bool) {
        if enabled, excavator == nil {
            excavator = Excavator(lane: lane, groundY: shelf?.top ?? 0)
        } else if !enabled {
            excavator = nil
        }
    }

    /// Double-click on the excavator.
    func startExcavator() {
        excavator?.start()
    }

    func clearAll() {
        base.clear()
        ledges.values.forEach { $0.pile.clear() }
    }

    // MARK: - Windows

    /// Updates snow-holding window tops. `windows` lists every on-screen window front to back,
    /// with frames in this screen's coordinates. `closed` holds windows that were really closed
    /// (not just moved to another Space). Returns true if anything that is drawn changed.
    @discardableResult
    func updateWindows(_ windows: [(id: CGWindowID, frame: CGRect)], closed: Set<CGWindowID>) -> Bool {
        let now = CACurrentMediaTime()
        var spots: [CGWindowID: Spot] = [:]
        for (index, window) in windows.enumerated() {
            spots[window.id] = Spot(frame: window.frame, index: index, screenWidth: width, screenHeight: height)
        }
        let present = Set(windows.map(\.id))
        var changed = false
        var closing: [CGWindowID: Ledge] = [:]

        for (id, ledge) in ledges {
            if let spot = spots[id] {
                if ledge.spot.sameEdge(as: spot) {
                    ledge.spot.index = spot.index
                    if ledge.isParked { ledge.isParked = false; changed = true }
                    continue
                }
                // The window moved or was resized: its snow falls off.
                if !ledge.isParked { drop(ledge) }
                ledges[id] = nil
                changed = true
            } else if present.contains(id) {
                // Moved off this screen or up into the menu bar.
                if !ledge.isParked { drop(ledge) }
                ledges[id] = nil
                changed = true
            } else if closed.contains(id) {
                closing[id] = ledge
                ledges[id] = nil
            } else if !ledge.isParked {
                // Gone from sight, not (yet) known to be closed: keep the snow for now.
                ledge.isParked = true
                ledge.parkedAt = now
                changed = true
            } else if now - ledge.parkedAt > 30 * 60 {
                ledges[id] = nil
            }
        }

        for (id, spot) in spots where ledges[id] == nil {
            // A new window in exactly the same place as one that just vanished
            // (switching Finder tabs, for example) keeps the snow.
            if let (oldID, old) = closing.first(where: { $0.value.spot.sameEdge(as: spot) }) {
                closing[oldID] = nil
                old.isParked = false
                old.spot = spot
                ledges[id] = old
            } else if let (oldID, old) = ledges.first(where: {
                $0.value.isParked && now - $0.value.parkedAt < 2 && $0.value.spot.sameEdge(as: spot)
            }) {
                ledges[oldID] = nil
                old.isParked = false
                old.spot = spot
                ledges[id] = old
            } else {
                ledges[id] = Ledge(spot: spot)
            }
            changed = true
        }

        // Closed windows: the snow on them falls down.
        for ledge in closing.values {
            drop(ledge)
            changed = true
        }

        activeLedges = ledges.values.filter { !$0.isParked }

        // Hide the parts of each window top that are behind windows in front of it.
        for ledge in activeLedges {
            let spot = ledge.spot
            let covers: [(Float, Float)] = windows[..<spot.index].compactMap { window in
                let f = window.frame
                guard Float(f.minY) < spot.top + 8, Float(f.maxY) > spot.top - 2 else { return nil }
                return (Float(f.minX), Float(f.maxX))
            }
            if ledge.pile.setVisibility({ x in !covers.contains { x >= $0.0 && x <= $0.1 } }) {
                changed = true
            }
        }
        return changed
    }

    /// Lets the snow on every window fall (used when window piles are switched off).
    func dropAllLedges() {
        for ledge in activeLedges { drop(ledge) }
        ledges.removeAll()
        activeLedges = []
    }

    private func drop(_ ledge: Ledge) {
        for chunk in ledge.pile.takeAll(maxChunks: 240) {
            guard particles.count < Self.maxParticles else { break }
            particles.append(makeLump(x: chunk.x, y: chunk.y, area: chunk.area, vx: Float.random(in: -25...25)))
        }
    }

    // MARK: - Frame step

    func step(dt: Float) {
        clock += dt
        if isSnowing { spawnSnowflakes(dt) }
        if let cursor = cursorProvider?() { sweep(at: cursor) }
        moveParticles(dt)

        if let excavator, excavator.isBusy, let dump = excavator.step(dt: dt, pile: base) {
            // The bucket's snow tumbles over the end of the Dock.
            let lumps = min(160, max(3, Int(dump.area / 50)))
            for _ in 0..<lumps where particles.count < Self.maxParticles {
                particles.append(makeLump(
                    x: dump.x + Float.random(in: -4...4),
                    y: dump.y + Float.random(in: -5...5),
                    area: dump.area / Float(lumps),
                    vx: dump.direction * Float.random(in: 15...55)
                ))
            }
        }

        base.step(dt: dt, meltRate: Self.meltRate)
        for ledge in activeLedges {
            ledge.pile.step(dt: dt, meltRate: Self.meltRate)
            let spill = ledge.pile.takeSpill()
            ledge.spillLeft += spill.left
            ledge.spillRight += spill.right
            // Snow sliding off a window's end drops as a little lump.
            if ledge.spillLeft >= 8 {
                spawnLump(x: ledge.pile.minX - 1, y: ledge.spot.top + 1, area: ledge.spillLeft, vx: -15)
                ledge.spillLeft = 0
            }
            if ledge.spillRight >= 8 {
                spawnLump(x: ledge.pile.maxX + 1, y: ledge.spot.top + 1, area: ledge.spillRight, vx: 15)
                ledge.spillRight = 0
            }
        }
    }

    private func sweep(at cursor: SIMD2<Float>) {
        var removed = base.sweep(x: cursor.x, y: cursor.y, radius: Self.brushRadius)
        for ledge in activeLedges {
            removed += ledge.pile.sweep(x: cursor.x, y: cursor.y, radius: Self.brushRadius)
        }
        guard removed > 0.3 else { return }
        // A little spray of snow where the cursor brushed it away.
        let puffs = min(14, 1 + Int(removed / 5))
        for _ in 0..<puffs where particles.count < Self.maxParticles {
            particles.append(makePuff(
                x: cursor.x + Float.random(in: -Self.brushRadius / 2...Self.brushRadius / 2),
                y: cursor.y + Float.random(in: -6...6)
            ))
        }
    }

    private func spawnSnowflakes(_ dt: Float) {
        spawnBudget += Float(intensity.spawnRate) * width / 1000 * dt
        while spawnBudget >= 1 {
            spawnBudget -= 1
            guard snowflakeCount < Self.maxSnowflakes, particles.count < Self.maxParticles else { continue }
            particles.append(makeSnowflake())
        }
    }

    private func spawnLump(x: Float, y: Float, area: Float, vx: Float) {
        guard particles.count < Self.maxParticles else { return }
        particles.append(makeLump(x: x, y: y, area: area, vx: vx))
    }

    private func moveParticles(_ dt: Float) {
        let gust = windSpeed()
        var flakes = 0
        var i = 0
        while i < particles.count {
            var p = particles[i]
            let previousBottom = p.y - p.radius * 0.5

            if p.gravity > 0 { p.vy = min(900, p.vy + p.gravity * dt) }
            let sway = p.swayAmplitude > 0 ? sin(clock * p.swayFrequency + p.phase) * p.swayAmplitude : 0
            p.x += (gust * p.windFactor + sway + p.vx) * dt
            p.y -= p.vy * dt

            // Snowflakes wrap around the sides so the snow stays evenly spread;
            // lumps and puffs that leave the screen are gone.
            var gone = p.y < -20
            if p.x < -12 || p.x > width + 12 {
                if p.gravity == 0 {
                    p.x += p.x < 0 ? width + 24 : -(width + 24)
                } else {
                    gone = true
                }
            }
            if p.fade > 0 {
                p.alpha -= p.fade * dt
                gone = gone || p.alpha <= 0
            }
            if !gone, p.area > 0, land(p, previousBottom: previousBottom) {
                gone = true
            }
            if gone {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
                continue
            }

            if p.gravity == 0 { flakes += 1 }
            particles[i] = p
            i += 1
        }
        snowflakeCount = flakes
    }

    /// Lands `p` on the first surface it crossed this frame. Returns true when it landed.
    private func land(_ p: Particle, previousBottom: Float) -> Bool {
        let bottom = p.y - p.radius * 0.5
        for ledge in activeLedges {
            let pile = ledge.pile
            guard let column = pile.column(at: p.x), pile.visible[column] else { continue }
            let surface = pile.surface(at: column)
            if previousBottom >= surface - 0.5, bottom <= surface {
                pile.deposit(x: p.x, area: p.area)
                return true
            }
        }
        if let column = base.column(at: p.x), bottom <= base.surface(at: column) {
            base.deposit(x: p.x, area: p.area)
            return true
        }
        return false
    }

    // MARK: - Particle kinds

    private func makeSnowflake() -> Particle {
        let radius = 1.2 + pow(Float.random(in: 0...1), 2.2) * 3.3
        let nearness = (radius - 1.2) / 3.3 // 0 = small and far, 1 = big and close
        return Particle(
            x: Float.random(in: -12...(width + 12)), y: height + 10,
            vx: 0, vy: 26 + 52 * nearness + Float.random(in: 0...12), gravity: 0,
            radius: radius, alpha: 0.55 + 0.45 * nearness, fade: 0,
            swayAmplitude: Float.random(in: 6...20), swayFrequency: Float.random(in: 0.6...1.8),
            phase: Float.random(in: 0...(2 * .pi)), windFactor: 0.6 + 0.6 * nearness,
            area: .pi * radius * radius * 0.5
        )
    }

    /// A lump of fallen snow dropping off a window: falls fast and piles up wherever it lands.
    private func makeLump(x: Float, y: Float, area: Float, vx: Float) -> Particle {
        Particle(
            x: x, y: y, vx: vx, vy: Float.random(in: 0...40), gravity: 900,
            radius: min(5, 1.6 + area.squareRoot() * 0.35), alpha: 0.95, fade: 0,
            swayAmplitude: 0, swayFrequency: 0, phase: 0, windFactor: 0.2,
            area: area
        )
    }

    /// Spray from snow swept away by the mouse: flies up a little, then fades out.
    private func makePuff(x: Float, y: Float) -> Particle {
        let life = Float.random(in: 0.5...0.9)
        return Particle(
            x: x, y: y, vx: Float.random(in: -80...80), vy: -Float.random(in: 40...140), gravity: 600,
            radius: Float.random(in: 1.2...2.6), alpha: 0.9, fade: 0.9 / life,
            swayAmplitude: 0, swayFrequency: 0, phase: 0, windFactor: 0.2,
            area: 0
        )
    }

    /// Slowly changing wind: mostly one direction, now and then turning around.
    private func windSpeed() -> Float {
        let base = Float(wind.speed)
        guard base > 0 else { return 0 }
        let t = clock
        let wave = 0.55 * sin(t * 0.07) + 0.30 * sin(t * 0.19 + 1.7) + 0.15 * sin(t * 0.43 + 3.1)
        return base * (0.35 + wave)
    }
}
