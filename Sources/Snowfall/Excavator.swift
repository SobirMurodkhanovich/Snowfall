import CoreGraphics
import Foundation

/// A small excavator parked on top of the Dock.
///
/// Double-click it and it lowers its bucket, drives to the far end of the Dock scooping up the
/// snow on the way, tips the snow over the edge and stops. The next double-click sends it back the
/// other way. This class is only the logic; `ExcavatorView` draws it.
final class Excavator {
    enum Phase { case parked, lowering, driving, dumping }

    /// Snow tipped over the edge, to be turned into falling lumps.
    struct Dump {
        let x: Float
        let y: Float
        let area: Float
        let direction: Float
    }

    /// What the view needs to draw a frame. Values are rounded so the view redraws only on visible change.
    struct Look: Equatable {
        var facingLeft: Bool
        var armLift: Float
        var bucketTip: Float
        var heap: Float
        var trackOffset: Float
    }

    /// Size of the drawing (pt). Ground is its bottom edge.
    static let viewWidth: CGFloat = 150
    static let viewHeight: CGFloat = 72
    /// `x` is this far right of the drawing's left edge.
    static let bodyInset: Float = 33
    private static let speed: Float = 80

    private(set) var phase: Phase = .parked
    /// Screen-local position (the drawing's left edge is `x - bodyInset`).
    private(set) var x: Float
    /// Height of the surface it drives on (top of the Dock, or the bottom of the screen).
    private(set) var groundY: Float
    private(set) var facingLeft = true

    private var lane: ClosedRange<Float>
    private var nextRunLeft = true
    /// 0 = bucket down scraping the ground, 1 = raised.
    private var armLift: Float = 1
    /// 0 = bucket level, 1 = tipped forward to empty it.
    private var bucketTip: Float = 0
    /// Snow in the bucket, pt².
    private var load: Float = 0
    private var travelled: Float = 0
    private var dumpClock: Float = 0
    private var hasDumped = false

    init(lane: ClosedRange<Float>, groundY: Float) {
        self.lane = lane
        self.groundY = groundY
        x = lane.upperBound // start at the right end, facing left
        clampToLane()
    }

    var isBusy: Bool { phase != .parked }

    var look: Look {
        func rounded(_ value: Float, _ steps: Float) -> Float { (value * steps).rounded() / steps }
        return Look(
            facingLeft: facingLeft,
            armLift: rounded(armLift, 60),
            bucketTip: rounded(bucketTip, 60),
            heap: rounded(min(1, (load / 6000).squareRoot()), 40),
            trackOffset: rounded(travelled.truncatingRemainder(dividingBy: 5), 4)
        )
    }

    // Facing left the bucket teeth are 10 pt left of `x`, facing right 94 pt right of it.
    // At either end the bucket hangs just past the end of the lane, so the snow drops off the edge.
    private var leftmostX: Float { lane.lowerBound + 6 }
    private var rightmostX: Float { max(leftmostX, lane.upperBound - 90) }

    func setLane(_ newLane: ClosedRange<Float>, groundY newGround: Float) {
        lane = newLane
        groundY = newGround
        clampToLane()
    }

    private func clampToLane() {
        x = min(max(x, leftmostX), rightmostX)
    }

    /// Starts a run (double-click). Ignored while it is already working.
    func start() {
        guard phase == .parked else { return }
        facingLeft = nextRunLeft
        phase = .lowering
    }

    func step(dt: Float, pile: SnowPile) -> Dump? {
        switch phase {
        case .parked:
            return nil

        case .lowering:
            armLift = max(0, armLift - dt * 2.5)
            if armLift == 0 { phase = .driving }
            return nil

        case .driving:
            x += (facingLeft ? -1 : 1) * Self.speed * dt
            travelled += Self.speed * dt
            var arrived = false
            if facingLeft, x <= leftmostX {
                x = leftmostX
                arrived = true
            } else if !facingLeft, x >= rightmostX {
                x = rightmostX
                arrived = true
            }
            // Everything under the tracks and in front of the bucket goes into the bucket.
            load += pile.scrape(from: x - 12, to: x + 96)
            if arrived {
                phase = .dumping
                dumpClock = 0
                hasDumped = false
            }
            return nil

        case .dumping:
            dumpClock += dt
            let t = dumpClock
            armLift = min(1, t / 0.6)
            if t < 0.6 {
                bucketTip = 0
            } else if t < 1.0 {
                bucketTip = (t - 0.6) / 0.4
            } else {
                bucketTip = max(0, 1 - (t - 1.0) / 0.5)
            }

            var dump: Dump?
            if !hasDumped, t >= 0.8 {
                hasDumped = true
                if load > 1 {
                    let edge = facingLeft ? lane.lowerBound - 8 : lane.upperBound + 8
                    dump = Dump(x: edge, y: groundY + 36, area: load, direction: facingLeft ? -1 : 1)
                }
                load = 0
            }
            if t >= 1.7 {
                phase = .parked
                bucketTip = 0
                nextRunLeft = !facingLeft
            }
            return dump
        }
    }
}
