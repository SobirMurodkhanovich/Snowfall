import Cocoa

struct TrackedWindow {
    let id: CGWindowID
    /// Global Cocoa coordinates (origin at the bottom-left of the main screen).
    let frame: CGRect
}

/// Watches the other apps' windows so snow can pile on top of them.
///
/// Window positions come from the on-screen window list, which needs no permission (only window
/// titles do, and they are not used). When a window vanishes, the tracker waits a moment to tell a
/// real close or minimise (snow falls) from a Space switch or a hidden app (snow is kept).
final class WindowTracker {
    /// Front to back.
    private(set) var windows: [TrackedWindow] = []
    /// Windows found to be closed during the last poll.
    private(set) var closed: Set<CGWindowID> = []

    private var owners: [CGWindowID: pid_t] = [:]
    private var missingSince: [CGWindowID: CFTimeInterval] = [:]
    private var lastSpaceChange: CFTimeInterval = -100
    private let decideAfter: CFTimeInterval = 0.3

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    @objc private func spaceChanged() {
        lastSpaceChange = CACurrentMediaTime()
    }

    /// Forgets everything (used after polling was paused, so nothing looks freshly closed).
    func reset() {
        windows = []
        closed = []
        owners = [:]
        missingSince = [:]
    }

    func poll() {
        closed = []
        // While the screen is locked windows disappear from the list; that is not a close.
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           (session["CGSSessionScreenIsLocked"] as? Bool) == true {
            return
        }

        let now = CACurrentMediaTime()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let myPID = ProcessInfo.processInfo.processIdentifier

        var current: [TrackedWindow] = []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0, // ordinary app windows only
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 120, bounds.height >= 60
            else { continue }
            // Window list uses top-left origin; flip to Cocoa's bottom-left.
            let frame = CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            current.append(TrackedWindow(id: id, frame: frame))
            owners[id] = pid
            missingSince[id] = nil
        }

        let currentIDs = Set(current.map(\.id))
        for window in windows where !currentIDs.contains(window.id) && missingSince[window.id] == nil {
            missingSince[window.id] = now
        }

        for (id, since) in missingSince where now - since >= decideAfter {
            let app = owners[id].flatMap { NSRunningApplication(processIdentifier: $0) }
            let switchedSpace = lastSpaceChange > since - 1.5
            let appHidden = app?.isHidden ?? false
            if !switchedSpace && !appHidden {
                closed.insert(id)
            }
            missingSince[id] = nil
            owners[id] = nil
        }

        windows = current
    }
}
