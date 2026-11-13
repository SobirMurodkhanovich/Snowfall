import ApplicationServices
import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var windows: [SnowWindow] = []
    private var dockTimer: Timer?
    private var windowTimer: Timer?
    private let tracker = WindowTracker()
    private var trackerPaused = true
    private var lastDock: DockLocator.Dock?
    private var hasCheckedDock = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Snowfall")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        syncWindows()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        // The Dock changes width when apps open and close, so check it now and then.
        dockTimer = Timer.scheduledTimer(
            timeInterval: 2, target: self, selector: #selector(refreshDock), userInfo: nil, repeats: true
        )
        // Window positions, so snow can pile on windows and fall when they close or move.
        windowTimer = Timer.scheduledTimer(
            timeInterval: 0.15, target: self, selector: #selector(pollWindows), userInfo: nil, repeats: true
        )
    }

    // MARK: - Windows

    @objc private func screensChanged() {
        syncWindows()
    }

    /// One snow window per screen. Windows for screens that did not change keep their snow.
    private func syncWindows() {
        let screens = NSScreen.screens
        windows.removeAll { window in
            let keep = screens.contains { $0.frame == window.screenFrame }
            if !keep { window.close() }
            return !keep
        }
        for screen in screens where !windows.contains(where: { $0.screenFrame == screen.frame }) {
            windows.append(SnowWindow(screen: screen))
        }
        applySettings()
        windows.forEach { $0.orderFrontRegardless() }

        hasCheckedDock = false
        refreshDock()
    }

    @objc private func refreshDock() {
        let dock = DockLocator.locate()
        guard !hasCheckedDock || dock != lastDock else { return }
        hasCheckedDock = true
        lastDock = dock
        windows.forEach { $0.setDock(dock) }
        placeSnowplow()
    }

    /// The snowplow lives on the screen with the Dock (or the main screen when the Dock is hidden).
    private func placeSnowplow() {
        var host: SnowWindow?
        if settings.showSnowplow {
            host = windows.first { $0.screenFrame == lastDock?.screenFrame }
                ?? windows.first { $0.screenFrame == NSScreen.screens.first?.frame }
        }
        for window in windows {
            window.setSnowplowEnabled(window === host)
        }
    }

    @objc private func pollWindows() {
        // No need to watch windows while nothing is snowing or lying around.
        guard settings.pileOnWindows, !windows.allSatisfy({ $0.simulation.isIdle }) else {
            if !trackerPaused {
                tracker.reset()
                trackerPaused = true
            }
            return
        }
        trackerPaused = false
        tracker.poll()
        windows.forEach { $0.updateWindows(tracker.windows, closed: tracker.closed) }
    }

    private func applySettings() {
        for window in windows {
            window.simulation.isSnowing = settings.isSnowing
            window.simulation.intensity = settings.intensity
            window.simulation.wind = settings.wind
            window.setAboveWindows(settings.aboveWindows)
            window.wake()
        }
        statusItem.button?.appearsDisabled = !settings.isSnowing
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item(settings.isSnowing ? "Qorni to'xtatish" : "Qor yog'dirish", #selector(toggleSnow)))
        menu.addItem(.separator())

        menu.addItem(header("Qor kuchi"))
        for level in Intensity.allCases {
            let entry = item(level.title, #selector(chooseIntensity(_:)))
            entry.tag = level.rawValue
            entry.state = settings.intensity == level ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        menu.addItem(header("Shamol"))
        for wind in Wind.allCases {
            let entry = item(wind.title, #selector(chooseWind(_:)))
            entry.tag = wind.rawValue
            entry.state = settings.wind == wind ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let above = item("Oynalar ustida yog'sin", #selector(toggleAboveWindows))
        above.state = settings.aboveWindows ? .on : .off
        menu.addItem(above)
        let onWindows = item("Oynalar ustiga yig'ilsin", #selector(togglePileOnWindows))
        onWindows.state = settings.pileOnWindows ? .on : .off
        menu.addItem(onWindows)
        menu.addItem(item("Yig'ilgan qorni tozalash", #selector(clearSnow)))
        let plow = item("Qor kurash mashinasi (2 marta bosing)", #selector(toggleSnowplow))
        plow.state = settings.showSnowplow ? .on : .off
        menu.addItem(plow)
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            menu.addItem(item("Dock'ni aniq o'lchash…", #selector(requestAccessibility)))
        }
        let login = item("Mac yonganda ishga tushsin", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        menu.addItem(header("Snowfall \(version)"))
        let quit = NSMenuItem(title: "Chiqish", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    /// A greyed-out label (works on macOS 13, unlike NSMenuItem.sectionHeader).
    private func header(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    // MARK: - Actions

    @objc private func toggleSnow() {
        settings.isSnowing.toggle()
        applySettings()
    }

    @objc private func chooseIntensity(_ sender: NSMenuItem) {
        settings.intensity = Intensity(rawValue: sender.tag) ?? .medium
        applySettings()
    }

    @objc private func chooseWind(_ sender: NSMenuItem) {
        settings.wind = Wind(rawValue: sender.tag) ?? .breeze
        applySettings()
    }

    @objc private func toggleAboveWindows() {
        settings.aboveWindows.toggle()
        applySettings()
    }

    @objc private func togglePileOnWindows() {
        settings.pileOnWindows.toggle()
        if !settings.pileOnWindows {
            windows.forEach { $0.dropWindowSnow() }
        }
    }

    @objc private func toggleSnowplow() {
        settings.showSnowplow.toggle()
        placeSnowplow()
    }

    @objc private func clearSnow() {
        windows.forEach { $0.clearPile() }
    }

    @objc private func requestAccessibility() {
        // Opens the system prompt that leads to System Settings › Privacy & Security › Accessibility.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Avtomatik ishga tushirishni o'zgartirib bo'lmadi"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
