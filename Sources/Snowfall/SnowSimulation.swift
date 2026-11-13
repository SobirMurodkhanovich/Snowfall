import Foundation

/// Where snow can settle on top of the Dock, in screen-local points.
struct Shelf: Equatable {
    var minX: Float
    var maxX: Float
    var top: Float
}

/// Falling flakes plus the pile they build up at the bottom of one screen. No drawing here.
final class SnowSimulation {
    struct Flake {
        var x: Float
        var y: Float
        let radius: Float
        let alpha: Float
        let fallSpeed: Float
        let swayAmplitude: Float
        let swayFrequency: Float
        let phase: Float
        let windFactor: Float
    }

    static let maxFlakes = 3000
    private static let maxDepth: Float = 46
    private static let meltRate: Float = 0.025

    var isSnowing = true
    var intensity: Intensity = .medium
    var wind: Wind = .breeze

    let width: Float
    let height: Float
    let pile: SnowPile
    private(set) var flakes: [Flake] = []

    private var shelf: Shelf?
    private var clock: Float = 0
    private var spawnBudget: Float = 0

    /// Nothing falling, nothing lying: the render loop can stop.
    var isIdle: Bool { !isSnowing && flakes.isEmpty && pile.isEmpty }

    init(width: Float, height: Float) {
        self.width = width
        self.height = height
        pile = SnowPile(width: width, maxDepth: Self.maxDepth)
    }

    func setShelf(_ newShelf: Shelf?) {
        guard newShelf != shelf else { return }
        shelf = newShelf
        pile.setGround { x in
            guard let s = newShelf, x >= s.minX, x <= s.maxX else { return 0 }
            return s.top
        }
    }

    func step(dt: Float) {
        clock += dt
        if isSnowing { spawn(dt) }
        moveFlakes(dt)
        pile.step(dt: dt, meltRate: Self.meltRate)
    }

    private func spawn(_ dt: Float) {
        spawnBudget += Float(intensity.spawnRate) * width / 1000 * dt
        while spawnBudget >= 1 {
            spawnBudget -= 1
            guard flakes.count < Self.maxFlakes else { continue }
            flakes.append(makeFlake())
        }
    }

    private func makeFlake() -> Flake {
        let radius = 1.2 + pow(Float.random(in: 0...1), 2.2) * 3.3
        let nearness = (radius - 1.2) / 3.3 // 0 = small and far, 1 = big and close
        return Flake(
            x: Float.random(in: -12...(width + 12)),
            y: height + 10,
            radius: radius,
            alpha: 0.55 + 0.45 * nearness,
            fallSpeed: 26 + 52 * nearness + Float.random(in: 0...12),
            swayAmplitude: Float.random(in: 6...20),
            swayFrequency: Float.random(in: 0.6...1.8),
            phase: Float.random(in: 0...(2 * .pi)),
            windFactor: 0.6 + 0.6 * nearness
        )
    }

    private func moveFlakes(_ dt: Float) {
        let gust = windSpeed()
        var i = 0
        while i < flakes.count {
            var flake = flakes[i]
            let sway = sin(clock * flake.swayFrequency + flake.phase) * flake.swayAmplitude
            flake.x += (gust * flake.windFactor + sway) * dt
            flake.y -= flake.fallSpeed * dt

            // Wrap around the sides so the snow stays evenly spread.
            if flake.x < -12 {
                flake.x += width + 24
            } else if flake.x > width + 12 {
                flake.x -= width + 24
            }

            let isOverScreen = flake.x >= 0 && flake.x < width
            let landed = isOverScreen && flake.y - flake.radius * 0.5 <= pile.surface(at: flake.x)
            if landed {
                pile.deposit(x: flake.x, area: .pi * flake.radius * flake.radius * 0.5)
            }
            if landed || flake.y < -20 {
                flakes.swapAt(i, flakes.count - 1)
                flakes.removeLast()
                continue
            }

            flakes[i] = flake
            i += 1
        }
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
