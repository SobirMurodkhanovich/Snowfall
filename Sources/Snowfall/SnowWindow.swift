import Cocoa
import MetalKit

/// A transparent, click-through window that covers one screen and shows the snow.
final class SnowWindow: NSWindow {
    let simulation: SnowSimulation
    let screenFrame: CGRect
    private let metalView: MTKView
    private var renderer: SnowRenderer?
    private var plowPanel: SnowplowPanel?

    init(screen: NSScreen) {
        screenFrame = screen.frame
        simulation = SnowSimulation(width: Float(screen.frame.width), height: Float(screen.frame.height))
        metalView = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true // clicks go through to whatever is underneath
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 60
        metalView.autoresizingMask = [.width, .height]
        metalView.layer?.isOpaque = false
        contentView = metalView

        renderer = SnowRenderer(pixelFormat: metalView.colorPixelFormat, simulation: simulation)
        metalView.delegate = renderer
        if renderer == nil { metalView.isPaused = true }
        renderer?.onFrame = { [weak self] in self?.syncSnowplow() }

        // Holding the left mouse button over snow sweeps it away. Reading the global mouse
        // state needs no permission, and clicks still go through to the windows underneath.
        let frame = screenFrame
        simulation.cursorProvider = {
            guard NSEvent.pressedMouseButtons & 1 != 0 else { return nil }
            let mouse = NSEvent.mouseLocation
            guard frame.contains(mouse) else { return nil }
            return SIMD2(Float(mouse.x - frame.minX), Float(mouse.y - frame.minY))
        }

        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Keep the window over the whole screen, menu bar area included.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Above all app windows (but under the Dock and menus), or only on the desktop.
    func setAboveWindows(_ above: Bool) {
        if above {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        } else {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    override func close() {
        plowPanel?.close()
        plowPanel = nil
        super.close()
    }

    // MARK: - Snowplow

    /// Shows or hides the snowplow on this screen.
    func setSnowplowEnabled(_ enabled: Bool) {
        simulation.setSnowplowEnabled(enabled)
        guard enabled else {
            plowPanel?.close()
            plowPanel = nil
            return
        }
        if plowPanel == nil {
            let panel = SnowplowPanel()
            panel.plowView.onDoubleClick = { [weak self] in
                self?.simulation.startSnowplow()
                self?.wake()
            }
            plowPanel = panel
        }
        // Just above the Dock (and below menus), so double-clicks always reach it.
        plowPanel?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        syncSnowplow()
        plowPanel?.orderFrontRegardless()
    }

    /// Moves the snowplow's panel to where the simulation has it, and updates its drawing.
    private func syncSnowplow() {
        guard let panel = plowPanel, let plow = simulation.snowplow else { return }
        let origin = CGPoint(
            x: (screenFrame.minX + CGFloat(plow.viewOriginX)).rounded(),
            y: (screenFrame.minY + CGFloat(plow.groundY)).rounded()
        )
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        panel.plowView.look = plow.look
    }

    /// Restarts the render loop after it paused itself.
    func wake() {
        guard renderer != nil else { return }
        metalView.isPaused = false
    }

    func clearPile() {
        simulation.clearAll()
        renderer?.pileChanged()
        wake()
    }

    /// Passes the current windows (global coordinates, front to back) on to the simulation.
    func updateWindows(_ windows: [TrackedWindow], closed: Set<CGWindowID>) {
        let local = windows.map { (id: $0.id, frame: $0.frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)) }
        if simulation.updateWindows(local, closed: closed) {
            renderer?.pileChanged()
        }
        if !simulation.isIdle { wake() }
    }

    /// Lets the snow on every window fall down.
    func dropWindowSnow() {
        simulation.dropAllLedges()
        renderer?.pileChanged()
        wake()
    }

    func setDock(_ dock: DockLocator.Dock?) {
        var shelf: Shelf?
        if let dock, dock.screenFrame == screenFrame {
            shelf = Shelf(
                minX: Float(dock.minX - screenFrame.minX),
                maxX: Float(dock.maxX - screenFrame.minX),
                top: Float(dock.top - screenFrame.minY)
            )
        }
        simulation.setShelf(shelf)
        renderer?.pileChanged()
        syncSnowplow()
    }
}
