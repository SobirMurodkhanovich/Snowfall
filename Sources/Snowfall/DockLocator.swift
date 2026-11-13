import ApplicationServices
import Cocoa

/// Finds the top edge of the Dock so snow can settle on it.
///
/// macOS gives no public API for the Dock's size. The height comes from the space the Dock
/// reserves at the bottom of its screen. The width is read through Accessibility when the
/// user has allowed it, and otherwise estimated from the Dock's own settings.
enum DockLocator {
    struct Dock: Equatable {
        /// Frame of the screen the Dock is on (global coordinates).
        let screenFrame: CGRect
        /// Left and right edges of the Dock bar and the height of its top edge (global coordinates).
        let minX: CGFloat
        let maxX: CGFloat
        let top: CGFloat
    }

    private static let domain = "com.apple.dock" as CFString
    private static var lastAccessibilitySpan: (minX: CGFloat, maxX: CGFloat)?

    static func locate() -> Dock? {
        CFPreferencesAppSynchronize(domain)
        let orientation = pref("orientation") as? String ?? "bottom"
        let autohide = (pref("autohide") as? NSNumber)?.boolValue ?? false
        // A hidden or side Dock: snow simply settles on the bottom of the screen.
        guard orientation == "bottom", !autohide else { return nil }

        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.minY - $0.frame.minY > 10 }) else {
            return nil
        }
        let reserved = screen.visibleFrame.minY - screen.frame.minY
        let top = screen.frame.minY + reserved - 3

        let span = accessibilitySpan(reservedHeight: reserved) ?? estimatedSpan(on: screen)
        return Dock(screenFrame: screen.frame, minX: span.minX, maxX: span.maxX, top: top)
    }

    // MARK: - Exact width (needs Accessibility permission)

    private static func accessibilitySpan(reservedHeight: CGFloat) -> (minX: CGFloat, maxX: CGFloat)? {
        guard AXIsProcessTrusted(),
              let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }

        let app = AXUIElementCreateApplication(dockApp.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return lastAccessibilitySpan }

        var union: CGRect?
        for child in children where role(of: child) == kAXListRole {
            guard let rect = frame(of: child) else { continue }
            union = union?.union(rect) ?? rect
        }
        guard let rect = union, rect.width > 20 else { return lastAccessibilitySpan }

        // While the mouse magnifies the Dock it grows; keep the resting size instead.
        if rect.height > reservedHeight + 6, let last = lastAccessibilitySpan { return last }

        let span = (minX: rect.minX - 4, maxX: rect.maxX + 4)
        lastAccessibilitySpan = span
        return span
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        // Only x is used; it is the same in Accessibility and Cocoa coordinates.
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Estimated width

    private static func estimatedSpan(on screen: NSScreen) -> (minX: CGFloat, maxX: CGFloat) {
        let tile = CGFloat((pref("tilesize") as? NSNumber)?.doubleValue ?? 48)
        let apps = pref("persistent-apps") as? [[String: Any]] ?? []
        let others = pref("persistent-others") as? [[String: Any]] ?? []
        let showRecents = (pref("show-recents") as? NSNumber)?.boolValue ?? true
        let recentCount = (pref("recent-apps") as? [Any])?.count ?? 0

        let pinned = Set(apps.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String })
        let running = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
            return id != "com.apple.finder" && !pinned.contains(id)
        }.count

        // Finder + pinned apps + folders + Trash.
        var slots = 1 + tileCount(apps) + tileCount(others) + 1
        var separators: CGFloat = 1
        let extraApps = showRecents ? max(running, min(3, recentCount)) : running
        slots += CGFloat(extraApps)
        if showRecents, extraApps > 0 { separators += 1 }

        let width = min(slots * tile + separators * tile * 0.4 + tile * 0.6, screen.frame.width - 8)
        return (minX: screen.frame.midX - width / 2, maxX: screen.frame.midX + width / 2)
    }

    private static func tileCount(_ items: [[String: Any]]) -> CGFloat {
        items.reduce(0) { sum, item in
            sum + ((item["tile-type"] as? String) == "small-spacer-tile" ? 0.5 : 1)
        }
    }

    private static func pref(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }
}
