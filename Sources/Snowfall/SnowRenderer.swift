import MetalKit
import QuartzCore

/// Draws a `SnowSimulation` with Metal: every flake in one instanced draw call, the pile as triangles.
/// This keeps CPU use low, which matters for an app that runs all day on a laptop.
final class SnowRenderer: NSObject, MTKViewDelegate {
    let simulation: SnowSimulation

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let flakePipeline: MTLRenderPipelineState
    private let pilePipeline: MTLRenderPipelineState

    private static let buffersInFlight = 3
    private let inFlight = DispatchSemaphore(value: SnowRenderer.buffersInFlight)
    private var flakeBuffers: [MTLBuffer] = []
    private var bufferIndex = 0

    private var pileBuffer: MTLBuffer?
    private var pileVertexCount = 0
    private var pileNeedsRebuild = true

    private var lastTime: CFTimeInterval = 0
    private var frameIndex = 0

    /// Must match `FlakeInstance` in the shader (16 bytes).
    private struct FlakeInstance {
        var position: SIMD2<Float>
        var radius: Float
        var alpha: Float
    }

    /// Must match `PileVertex` in the shader (32 bytes, premultiplied colour).
    private struct PileVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    init?(pixelFormat: MTLPixelFormat, simulation: SnowSimulation) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }
        self.device = device
        self.queue = queue
        self.simulation = simulation

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            flakePipeline = try Self.makePipeline(device, library, "flakeVertex", "flakeFragment", pixelFormat)
            pilePipeline = try Self.makePipeline(device, library, "pileVertex", "pileFragment", pixelFormat)
        } catch {
            NSLog("Snowfall: Metal setup failed: \(error)")
            return nil
        }

        let flakeBytes = SnowSimulation.maxFlakes * MemoryLayout<FlakeInstance>.stride
        for _ in 0..<Self.buffersInFlight {
            guard let buffer = device.makeBuffer(length: flakeBytes, options: .storageModeShared) else { return nil }
            flakeBuffers.append(buffer)
        }
        super.init()
    }

    /// Call after changing the pile from outside (clearing it, moving the Dock shelf).
    func pileChanged() {
        pileNeedsRebuild = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1.0 / 60 : min(max(now - lastTime, 0), 0.05)
        lastTime = now
        advance(dt: Float(dt))

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = encode(pass: pass)
        else { return }
        commands.present(drawable)
        commands.commit()

        // This frame cleared the screen; with nothing left to animate, stop the loop to save battery.
        if simulation.isIdle {
            view.isPaused = true
            lastTime = 0
        }
    }

    /// Moves the snow forward by `dt` seconds.
    func advance(dt: Float) {
        simulation.step(dt: dt)
        frameIndex += 1
        // The pile changes slowly; rebuilding its shape 10 times a second is plenty.
        if pileNeedsRebuild || frameIndex % 6 == 0 {
            rebuildPile()
            pileNeedsRebuild = false
        }
    }

    /// Encodes the current state into `pass`. The caller presents (if needed) and commits.
    func encode(pass: MTLRenderPassDescriptor) -> MTLCommandBuffer? {
        inFlight.wait()
        let flakeBuffer = flakeBuffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % Self.buffersInFlight
        let flakeCount = writeFlakes(into: flakeBuffer)

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else {
            inFlight.signal()
            return nil
        }
        let semaphore = inFlight
        commands.addCompletedHandler { _ in semaphore.signal() }

        var viewSize = SIMD2<Float>(simulation.width, simulation.height)

        if flakeCount > 0 {
            encoder.setRenderPipelineState(flakePipeline)
            encoder.setVertexBuffer(flakeBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: flakeCount)
        }
        if pileVertexCount > 0, let pileBuffer {
            encoder.setRenderPipelineState(pilePipeline)
            encoder.setVertexBuffer(pileBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: pileVertexCount)
        }
        encoder.endEncoding()
        return commands
    }

    private func writeFlakes(into buffer: MTLBuffer) -> Int {
        let flakes = simulation.flakes
        let count = min(flakes.count, SnowSimulation.maxFlakes)
        let out = buffer.contents().bindMemory(to: FlakeInstance.self, capacity: count)
        for i in 0..<count {
            let f = flakes[i]
            out[i] = FlakeInstance(position: SIMD2(f.x, f.y), radius: f.radius, alpha: f.alpha)
        }
        return count
    }

    // MARK: - Pile geometry

    private func rebuildPile() {
        let pile = simulation.pile
        guard !pile.isEmpty else {
            pileVertexCount = 0
            return
        }
        let ground = pile.ground
        let depth = pile.depth
        let n = pile.count
        let w = pile.columnWidth

        // Smoothed depth (1-4-6-4-1 blur over neighbours on the same ground), so straight
        // segments between columns read as a soft curve.
        let weights: [Float] = [1, 4, 6, 4, 1]
        var shown = [Float](repeating: 0, count: n)
        for i in 0..<n where depth[i] > 0 || (i > 0 && depth[i - 1] > 0) || (i < n - 1 && depth[i + 1] > 0) {
            var sum: Float = 0
            for (k, weight) in weights.enumerated() {
                let j = i + k - 2
                let sample = j >= 0 && j < n && ground[j] == ground[i] ? depth[j] : depth[i]
                sum += sample * weight
            }
            shown[i] = sum / 16
        }

        let white = SIMD4<Float>(0.97, 0.97, 0.97, 0.97)
        let rimColor = SIMD4<Float>(0.55 * 0.55, 0.64 * 0.55, 0.76 * 0.55, 0.55)
        let shadow = SIMD4<Float>(0, 0, 0, 0.16)
        let clear = SIMD4<Float>(0, 0, 0, 0)

        var vertices: [PileVertex] = []
        vertices.reserveCapacity(n * 12)

        /// Quad between columns at x0 and x1, each spanning bottom…top, coloured bottom→top.
        func quad(_ x0: Float, _ b0: Float, _ t0: Float, _ x1: Float, _ b1: Float, _ t1: Float,
                  _ bottom0: SIMD4<Float>, _ top0: SIMD4<Float>, _ bottom1: SIMD4<Float>, _ top1: SIMD4<Float>) {
            let p00 = PileVertex(position: SIMD2(x0, b0), color: bottom0)
            let p01 = PileVertex(position: SIMD2(x0, t0), color: top0)
            let p10 = PileVertex(position: SIMD2(x1, b1), color: bottom1)
            let p11 = PileVertex(position: SIMD2(x1, t1), color: top1)
            vertices.append(contentsOf: [p00, p01, p10, p10, p01, p11])
        }

        for i in 0..<(n - 1) {
            // Never bridge a step in the ground (the Dock's edge): that would draw a streak down its side.
            guard ground[i] == ground[i + 1] else { continue }
            let d0 = shown[i]
            let d1 = shown[i + 1]
            guard d0 > 0.1 || d1 > 0.1 else { continue }

            let x0 = (Float(i) + 0.5) * w
            let x1 = x0 + w
            let g = ground[i]
            let top0 = g + d0
            let top1 = g + d1

            // Soft shadow on the Dock just under the snow.
            if g > 0 {
                quad(x0, g - 2, g, x1, g - 2, g, clear, shadow, clear, shadow)
            }
            // The snow itself.
            quad(x0, g, top0, x1, g, top1, white, white, white, white)
            // Faint blue-grey rim fading upwards: an outline on white windows and a soft edge.
            let rim0 = rimColor * min(1, d0 / 2)
            let rim1 = rimColor * min(1, d1 / 2)
            quad(x0, top0, top0 + 1.2, x1, top1, top1 + 1.2, rim0, clear, rim1, clear)
        }

        pileVertexCount = vertices.count
        guard !vertices.isEmpty else { return }
        pileBuffer = device.makeBuffer(
            bytes: vertices, length: vertices.count * MemoryLayout<PileVertex>.stride, options: .storageModeShared
        )
    }

    // MARK: - Metal setup

    private static func makePipeline(
        _ device: MTLDevice, _ library: MTLLibrary, _ vertex: String, _ fragment: String, _ format: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = format
        // Premultiplied alpha blending.
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // Compiled at launch, so building the app needs no Metal compiler (Command Line Tools are enough).
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct FlakeInstance { float2 position; float radius; float alpha; };
    struct FlakeOut { float4 position [[position]]; float2 local; float alpha; };

    vertex FlakeOut flakeVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                const device FlakeInstance *flakes [[buffer(0)]],
                                constant float2 &viewSize [[buffer(1)]]) {
        const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
        FlakeInstance f = flakes[iid];
        float2 corner = corners[vid] * 1.5;          // quad reaches 1.5 × radius, room for the rim
        float2 p = f.position + corner * f.radius;
        FlakeOut out;
        out.position = float4(p / viewSize * 2.0 - 1.0, 0.0, 1.0);
        out.local = corner;                          // in units of the radius
        out.alpha = f.alpha;
        return out;
    }

    fragment float4 flakeFragment(FlakeOut in [[stage_in]]) {
        float core = 1.0 - smoothstep(0.5, 1.0, length(in.local));   // soft white flake
        // Soft blue-grey shade just below it: keeps flakes visible on white windows
        // and makes them look round instead of like flat rings.
        float shade = (1.0 - smoothstep(0.5, 1.4, length(in.local - float2(0.0, -0.3)))) * 0.24;
        float3 shadeColor = float3(0.45, 0.52, 0.63);
        float a = core + shade * (1.0 - core);
        float3 rgb = float3(1.0) * core + shadeColor * shade * (1.0 - core);
        return float4(rgb, a) * in.alpha;                            // premultiplied
    }

    struct PileVertex { float2 position; float4 color; };
    struct PileOut { float4 position [[position]]; float4 color; };

    vertex PileOut pileVertex(uint vid [[vertex_id]],
                              const device PileVertex *vertices [[buffer(0)]],
                              constant float2 &viewSize [[buffer(1)]]) {
        PileOut out;
        out.position = float4(vertices[vid].position / viewSize * 2.0 - 1.0, 0.0, 1.0);
        out.color = vertices[vid].color;
        return out;
    }

    fragment float4 pileFragment(PileOut in [[stage_in]]) {
        return in.color;
    }
    """
}
