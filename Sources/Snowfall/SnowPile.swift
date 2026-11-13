import Foundation

/// The fallen snow, stored as a height field.
///
/// The screen width is cut into thin columns. Each column has a ground height
/// (the bottom of the screen, or the top of the Dock) and a snow depth on top of it.
/// Landed flakes add depth, too-steep slopes slide sideways, and everything slowly melts.
final class SnowPile {
    let columnWidth: Float = 2
    let count: Int

    private(set) var ground: [Float]
    private(set) var depth: [Float]
    /// Maximum depth per column. It varies along the screen so the pile forms drifts.
    private let capacity: [Float]

    /// Largest height difference between neighbouring columns before snow slides (about 33°).
    private let maxStep: Float = 1.3
    /// How fast small bumps settle out (per second). Big drifts stay, single-flake spikes soften.
    private let settleRate: Float = 2.0

    private(set) var isEmpty = true

    init(width: Float, maxDepth: Float) {
        count = max(2, Int((width / columnWidth).rounded(.up)))
        ground = Array(repeating: 0, count: count)
        depth = Array(repeating: 0, count: count)
        capacity = (0..<count).map { i in
            let x = Float(i)
            let wave = 0.5
                + 0.25 * sin(x * 0.011 + 1.3)
                + 0.15 * sin(x * 0.037 + 4.1)
                + 0.10 * sin(x * 0.083)
            return maxDepth * (0.55 + 0.45 * wave)
        }
    }

    func column(at x: Float) -> Int {
        min(count - 1, max(0, Int(x / columnWidth)))
    }

    /// Height of the snow surface (ground + snow) at `x`.
    func surface(at x: Float) -> Float {
        let i = column(at: x)
        return ground[i] + depth[i]
    }

    func setGround(_ height: (Float) -> Float) {
        for i in 0..<count {
            ground[i] = height((Float(i) + 0.5) * columnWidth)
        }
    }

    /// Adds a landed flake of `area` pt², spread over a few columns around `x`.
    func deposit(x: Float, area: Float) {
        let center = column(at: x)
        let spread = 5
        let weightSum = Float((spread + 1) * (spread + 1)) // 1+2+…+(n+1)+…+2+1
        let perWeight = area / columnWidth / weightSum
        for offset in -spread...spread {
            let i = center + offset
            guard i >= 0, i < count else { continue }
            let weight = Float(spread + 1 - abs(offset))
            let room = max(0, 1 - depth[i] / capacity[i]) // growth slows near the limit
            depth[i] += perWeight * weight * room
        }
        isEmpty = false
    }

    func clear() {
        for i in 0..<count { depth[i] = 0 }
        isEmpty = true
    }

    /// Lets snow slide off steep slopes and melts it a little.
    func step(dt: Float, meltRate: Float) {
        guard !isEmpty else { return }

        // Two sweeps in opposite directions so snow does not drift to one side.
        for i in 0..<(count - 1) { relax(from: i, to: i + 1) }
        for i in stride(from: count - 1, to: 0, by: -1) { relax(from: i, to: i - 1) }
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
}
