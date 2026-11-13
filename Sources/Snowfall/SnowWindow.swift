import Cocoa
import MetalKit

/// A transparent, click-through window that covers one screen and shows the snow.
final class SnowWindow: NSWindow {
    let simulation: SnowSimulation
    let screenFrame: CGRect
    private let metalView: MTKView
    private var renderer: SnowRenderer?

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

    /// Restarts the render loop after it paused itself.
    func wake() {
        guard renderer != nil else { return }
        metalView.isPaused = false
    }

    func clearPile() {
        simulation.pile.clear()
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
    }
}
