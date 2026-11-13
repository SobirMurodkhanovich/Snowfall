import Foundation

/// A strip of fallen snow, stored as a height field.
///
/// The strip is cut into thin columns. Each column has a ground height and a snow depth on top
/// of it. Landed flakes add depth, too-steep slopes slide sideways, and everything slowly melts.
/// The bottom of the screen is one pile; the top edge of every window gets its own.
final class SnowPile {
    let columnWidth: Float = 2
    let count: Int
    /// Left edge and base height of the strip in screen-local points.
    let originX: Float
    let baseY: Float
    /// Snow can slide off both ends (window tops). The screen-bottom pile has closed ends.
    let openEnds: Bool

    private(set) var ground: [Float]
    private(set) var depth: [Float]
    /// false for columns hidden behind a window in front. Snow there is kept, but not drawn or landed on.
    private(set) var visible: [Bool]
    /// Maximum depth per column. It varies along the strip so the pile forms drifts.
    private let capacity: [Float]

    /// Largest height difference between neighbouring columns before snow slides (about 33°).
    private let maxStep: Float = 1.3
    /// How fast small bumps settle out (per second). Big drifts stay, single-flake spikes soften.
    private let settleRate: Float = 2.0

    private(set) var isEmpty = true
    private var spillLeft: Float = 0
    private var spillRight: Float = 0

    init(originX: Float = 0, baseY: Float = 0, width: Float, maxDepth: Float, openEnds: Bool = false) {
        self.originX = originX
        self.baseY = baseY
        self.openEnds = openEnds
        count = max(2, Int((width / columnWidth).rounded(.up)))
        ground = Array(repeating: 0, count: count)
        depth = Array(repeating: 0, count: count)
        visible = Array(repeating: true, count: count)
        // Use screen x for the drift pattern, so neighbouring strips do not all look the same.
        let phase = originX / columnWidth
        capacity = (0..<count).map { i in
            let x = Float(i) + phase
            let wave = 0.5
                + 0.25 * sin(x * 0.011 + 1.3)
                + 0.15 * sin(x * 0.037 + 4.1)
                + 0.10 * sin(x * 0.083)
            return maxDepth * (0.55 + 0.45 * wave)
        }
    }

    var minX: Float { originX }
    var maxX: Float { originX + Float(count) * columnWidth }

    /// Column under screen-local `x`, or nil when `x` is outside the strip.
    func column(at x: Float) -> Int? {
        let i = Int(((x - originX) / columnWidth).rounded(.down))
        return i >= 0 && i < count ? i : nil
    }

    func centerX(of column: Int) -> Float {
        originX + (Float(column) + 0.5) * columnWidth
    }

    /// Height of the snow surface at a column, in screen-local points.
    func surface(at column: Int) -> Float {
        baseY + ground[column] + depth[column]
    }

    func setGround(_ height: (Float) -> Float) {
        for i in 0..<count {
            ground[i] = height(centerX(of: i))
        }
    }

    /// Returns true when any column changed.
    @discardableResult
    func setVisibility(_ isVisible: (Float) -> Bool) -> Bool {
        var changed = false
        for i in 0..<count {
            let value = isVisible(centerX(of: i))
            if value != visible[i] {
                visible[i] = value
                changed = true
            }
        }
        return changed
    }

    /// Adds a landed flake of `area` pt², spread over a few columns around `x`.
    func deposit(x: Float, area: Float) {
        guard let center = column(at: x) else { return }
        let spread = 5
        let weightSum = Float((spread + 1) * (spread + 1)) // 1+2+…+(n+1)+…+2+1
        let perWeight = area / columnWidth / weightSum
        for offset in -spread...spread {
            let i = center + offset
            guard i >= 0, i < count, visible[i] else { continue }
            let weight = Float(spread + 1 - abs(offset))
            let room = max(0, 1 - depth[i] / capacity[i]) // growth slows near the limit
            depth[i] += perWeight * weight * room
        }
        isEmpty = false
    }

    /// Scoops away snow inside a circle (the mouse brush). Returns the removed area in pt².
    func sweep(x cx: Float, y cy: Float, radius r: Float) -> Float {
        guard !isEmpty, cx + r >= minX, cx - r <= maxX else { return 0 }
        let first = max(0, Int(((cx - r - originX) / columnWidth).rounded(.down)))
        let last = min(count - 1, Int(((cx + r - originX) / columnWidth).rounded(.down)))
        guard first <= last else { return 0 }

        var removed: Float = 0
        for i in first...last where visible[i] && depth[i] > 0 {
            let dx = centerX(of: i) - cx
            let reach = r * r - dx * dx
            guard reach > 0 else { continue }
            let dy = reach.squareRoot()
            let bottom = baseY + ground[i]
            let top = bottom + depth[i]
            guard cy + dy > bottom, cy - dy < top else { continue }
            // Everything above the lower edge of the brush goes.
            let newTop = max(bottom, cy - dy)
            removed += (top - newTop) * columnWidth
            depth[i] = newTop - bottom
        }
        return removed
    }

    /// Removes all visible snow between screen-local `x0` and `x1` (the excavator's bucket).
    /// Returns the removed area in pt².
    func scrape(from x0: Float, to x1: Float) -> Float {
        guard !isEmpty, x1 >= minX, x0 <= maxX else { return 0 }
        let first = max(0, Int(((x0 - originX) / columnWidth).rounded(.down)))
        let last = min(count - 1, Int(((x1 - originX) / columnWidth).rounded(.down)))
        guard first <= last else { return 0 }
        var removed: Float = 0
        for i in first...last where visible[i] && depth[i] > 0 {
            removed += depth[i] * columnWidth
            depth[i] = 0
        }
        return removed
    }

    /// Empties the pile and returns its snow as lumps (position and area) that can fall elsewhere.
    func takeAll(maxChunks: Int) -> [(x: Float, y: Float, area: Float)] {
        defer { clear() }
        var total: Float = 0
        for i in 0..<count where visible[i] { total += depth[i] * columnWidth }
        guard total > 2 else { return [] }

        let chunkArea = max(14, total / Float(maxChunks))
        var chunks: [(x: Float, y: Float, area: Float)] = []
        var gathered: Float = 0
        for i in 0..<count where visible[i] && depth[i] > 0 {
            gathered += depth[i] * columnWidth
            if gathered >= chunkArea {
                let y = baseY + ground[i] + Float.random(in: 0...depth[i])
                chunks.append((x: centerX(of: i), y: y, area: gathered))
                gathered = 0
            }
        }
        if gathered > 2, let last = (0..<count).last(where: { visible[$0] && depth[$0] > 0 }) {
            chunks.append((x: centerX(of: last), y: baseY + ground[last] + depth[last] / 2, area: gathered))
        }
        return chunks
    }

    func clear() {
        for i in 0..<count { depth[i] = 0 }
        isEmpty = true
        spillLeft = 0
        spillRight = 0
    }

    /// Snow (pt²) that slid off each open end since the last call.
    func takeSpill() -> (left: Float, right: Float) {
        defer { spillLeft = 0; spillRight = 0 }
        return (spillLeft, spillRight)
    }

    /// Lets snow slide off steep slopes and melts it a little.
    func step(dt: Float, meltRate: Float) {
        guard !isEmpty else { return }

        // Two sweeps in opposite directions so snow does not drift to one side.
        for i in 0..<(count - 1) { relax(from: i, to: i + 1) }
        for i in stride(from: count - 1, to: 0, by: -1) { relax(from: i, to: i - 1) }
        if openEnds {
            spillLeft += spillOver(0)
            spillRight += spillOver(count - 1)
        }
        settle(dt: dt)

        var anySnow = false
        for i in 0..<count where depth[i] > 0 {
            // Deeper snow melts a bit faster, so a full pile disappears in roughly 10 minutes.
            let melt = (meltRate + depth[i] * 0.003) * dt
            depth[i] = min(capacity[i] * 1.1, max(0, depth[i] - melt))
            if depth[i] > 0 { anySnow = true }
        }
        isEmpty = !anySnow
    }

    /// Gentle levelling between neighbours on the same ground, so the surface looks soft.
    private func settle(dt: Float) {
        let k = min(0.25, settleRate * dt)
        for i in 0..<(count - 1) where ground[i] == ground[i + 1] {
            var flow = (depth[i] - depth[i + 1]) * k
            flow = flow > 0 ? min(flow, depth[i]) : max(flow, -depth[i + 1])
            depth[i] -= flow
            depth[i + 1] += flow
        }
    }

    private func relax(from a: Int, to b: Int) {
        guard depth[a] > 0 else { return }
        let excess = (ground[a] + depth[a]) - (ground[b] + depth[b]) - maxStep
        guard excess > 0 else { return }
        let moved = min(depth[a], excess * 0.5)
        depth[a] -= moved
        depth[b] += moved
    }

    /// At an open end the neighbour is empty air: snow piled higher than one step slides off.
    private func spillOver(_ i: Int) -> Float {
        let excess = depth[i] - maxStep
        guard excess > 0 else { return 0 }
        let moved = excess * 0.5
        depth[i] -= moved
        return moved * columnWidth
    }
}
