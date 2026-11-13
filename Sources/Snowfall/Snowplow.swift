import CoreGraphics
import Foundation

/// A small light-blue snowplow truck parked on top of the Dock.
///
/// Double-click it and it lowers its blade, drives to the far end of the Dock pushing the snow
/// into a growing heap in front of the blade, shoves the heap over the edge and stops. The next
/// double-click sends it back the other way. This class is only the logic; `SnowplowView` draws it.
final class Snowplow {
    enum Phase { case parked, lowering, driving, unloading, raising }

    /// Snow pushed over the edge this frame, to be turned into falling lumps.
    struct Dump {
        let x: Float
        let y: Float
        let area: Float
        let direction: Float
    }

    /// What the view needs to draw a frame. Values are rounded so the view redraws only on visible change.
    struct Look: Equatable {
        var facingLeft: Bool
        var bladeLift: Float
        var heap: Float
        var wheelTurn: Float
        var beaconOn: Bool
    }

    /// Size of the drawing (pt). Ground is its bottom edge.
    static let viewWidth: CGFloat = 150
    static let viewHeight: CGFloat = 64
    /// Where the truck body starts inside the drawing, facing right / facing left (mirrored).
    static let bodyOffsetFacingRight: Float = 14
    static let bodyOffsetFacingLeft: Float = 52
    private static let speed: Float = 80
    /// Snow (pt²) at which the heap in front of the blade is drawn at full size.
    private static let fullHeap: Float = 8000

    private(set) var phase: Phase = .parked
    /// Left edge of the truck body, screen-local. Stays put when the truck turns around.
    private(set) var x: Float
    /// Height of the surface it drives on (top of the Dock, or the bottom of the screen).
    private(set) var groundY: Float
    private(set) var facingLeft = true

    private var lane: ClosedRange<Float>
    private var nextRunLeft = true
    /// 0 = blade down on the ground, 1 = raised.
    private var bladeLift: Float = 1
    /// Snow pushed along in front of the blade, pt².
    private var load: Float = 0
    private var travelled: Float = 0
    private var clock: Float = 0

    init(lane: ClosedRange<Float>, groundY: Float) {
        self.lane = lane
        self.groundY = groundY
        x = lane.upperBound // start at the right end, facing left
        clampToLane()
    }

    var isBusy: Bool { phase != .parked }

    /// Left edge of the drawing, screen-local.
    var viewOriginX: Float {
        x - (facingLeft ? Self.bodyOffsetFacingLeft : Self.bodyOffsetFacingRight)
    }

    var look: Look {
        func rounded(_ value: Float, _ steps: Float) -> Float { (value * steps).rounded() / steps }
        return Look(
            facingLeft: facingLeft,
            bladeLift: rounded(bladeLift, 40),
            heap: rounded(min(1, (load / Self.fullHeap).squareRoot()), 40),
            wheelTurn: rounded((travelled / 9).truncatingRemainder(dividingBy: 2 * .pi), 24 / (2 * .pi)),
            beaconOn: isBusy && Int(clock * 3) % 2 == 0
        )
    }

    // The blade's edge is 10 pt left of the body facing left, 94 pt right of `x` facing right.
    // At either end the blade sits just past the end of the lane, so the heap drops off the edge.
    private var leftmostX: Float { lane.lowerBound + 8 }
    private var rightmostX: Float { max(leftmostX, lane.upperBound - 92) }

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
        clock += dt
        switch phase {
        case .parked:
            return nil

        case .lowering:
            bladeLift = max(0, bladeLift - dt * 3)
            if bladeLift == 0 { phase = .driving }
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
            // Snow under the truck and in front of the blade joins the heap.
            load += facingLeft ? pile.scrape(from: x - 12, to: x + 84) : pile.scrape(from: x, to: x + 96)
            if arrived { phase = .unloading }
            return nil

        case .unloading:
            // Shove the heap over the edge, a bit every frame (about a second for a full heap).
            guard load > 1 else {
                load = 0
                phase = .raising
                return nil
            }
            let heap = min(1, (load / Self.fullHeap).squareRoot())
            let portion = min(load, max(60, load * dt * 4))
            load -= portion
            let edge = facingLeft ? lane.lowerBound - 6 : lane.upperBound + 6
            return Dump(x: edge, y: groundY + 3 + 10 * heap, area: portion, direction: facingLeft ? -1 : 1)

        case .raising:
            bladeLift = min(1, bladeLift + dt * 2.5)
            if bladeLift == 1 {
                phase = .parked
                nextRunLeft = !facingLeft
            }
            return nil
        }
    }
}
