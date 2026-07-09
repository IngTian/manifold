//
//  AppDelegate.swift
//  Orchestrates the Manifold live wallpaper: one desktop-level window + terrain
//  view per screen, a status-bar menu (theme / walkers / battery / launch-at-login
//  / quit), live light↔dark following, and a PlaybackGovernor that pauses the
//  animation whenever nobody can see it.
//

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, PlaybackGovernorDelegate {

    private let settings = WallpaperSettings()
    private let governor = PlaybackGovernor()

    // One window + view per physical display, keyed by CGDirectDisplayID (stable
    // across NSScreen reshuffles — never key by array index or NSScreen identity).
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var views: [CGDirectDisplayID: TerrainWallpaperView] = [:]

    private var statusItem: NSStatusItem?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // MARK: Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar, no focus theft

        governor.delegate = self
        governor.pauseOnBattery = settings.pauseOnBattery
        governor.setCoverageProbe { [weak self] in self?.allWallpaperDisplaysCovered() ?? false }

        rebuildWindows()
        buildStatusItem()

        // React to display (dis)connection / resolution changes.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // .canJoinAllSpaces already puts the window on every Space (incl. new ones);
        // re-assert its back ordering on each Space switch as a belt-and-suspenders
        // guard so nothing that opened on a freshly-created desktop can leave us
        // stranded. Cheap and idempotent. (Lives on the *workspace* center.)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // Follow live system appearance changes in Auto mode.
        NSApp.addObserver(self, forKeyPath: "effectiveAppearance",
                          options: [.new], context: nil)

        governor.start()
    }

    func applicationWillTerminate(_ note: Notification) {
        for v in views.values { v.stop() }
    }

    // MARK: Window management (per display)

    private func rebuildWindows() {
        let live = Set(NSScreen.screens.compactMap { $0.displayID })

        // Drop windows for displays that went away.
        for id in windows.keys where !live.contains(id) {
            views[id]?.stop()
            windows[id]?.orderOut(nil)
            windows.removeValue(forKey: id)
            views.removeValue(forKey: id)
        }

        // Create / re-pin windows for current displays.
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let palette = resolvedPalette()

            if let win = windows[id], let view = views[id] {
                win.pin(to: screen)
                view.frame = win.contentLayoutRect
                view.setPalette(palette, animated: false)
                view.setFooter(currentFooter())
                continue
            }

            let win = WallpaperWindow(screen: screen)
            let view = TerrainWallpaperView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                            palette: palette,
                                            showWalkers: settings.showWalkers)
            // Start at the governor's current rate, not the 30fps default — else a
            // display hot-plugged while on battery would animate at 30 not 15.
            view.maxFPS = governor.preferredFPS
            view.setFooter(currentFooter())
            view.autoresizingMask = [.width, .height]
            win.contentView = view
            win.pin(to: screen)

            windows[id] = win
            views[id] = view
        }

        // Match current run state for any newly created views.
        applyRunState(governorRunning)
    }

    @objc private func screenParamsChanged() {
        rebuildWindows()
        governor.refreshCoverage()
    }

    /// The user switched to another Space (possibly a brand-new desktop).
    /// .canJoinAllSpaces means the windows already follow us there; we just
    /// re-assert their back ordering so a window that opened on a freshly-created
    /// desktop can't leave us stranded. Never rebuilds — no per-Space window churn.
    @objc private func activeSpaceChanged() {
        for (id, win) in windows {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { continue }
            win.pin(to: screen)
        }
    }

    // MARK: Theme

    /// The palette for the current setting; Auto follows the system appearance.
    private func resolvedPalette() -> Palette {
        switch settings.theme {
        case .light: return .light
        case .dark: return .dark
        case .auto: return isSystemDark() ? .dark : .light
        }
    }

    private func isSystemDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Footer

    /// The signature line to show, or nil when disabled/empty.
    private func currentFooter() -> String? {
        settings.showFooter ? settings.footerMessage : nil
    }

    private func applyFooter() {
        let f = currentFooter()
        for v in views.values { v.setFooter(f) }
    }

    /// Push the resolved palette to every view. A cross-fade is only worth
    /// animating when the wallpaper is actually being drawn (governor running);
    /// while paused (covered / asleep / locked) the animation clock is frozen, so
    /// a "fade" couldn't progress anyway — apply it instantly instead. This keeps
    /// all fade timing inside the renderer (driven by the displayLink) with no
    /// external timers to race the governor.
    private func applyTheme(animated: Bool) {
        let p = resolvedPalette()
        let fade = animated && governorRunning
        for v in views.values { v.setPalette(p, animated: fade) }
    }

    // KVO: system light/dark changed (only matters in Auto).
    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            if settings.theme == .auto { applyTheme(animated: true) }
        }
    }

    // MARK: Coverage probe (for the governor)

    /// True only if EVERY wallpaper display is (near-)fully covered by some normal
    /// window — in which case animating is pointless.
    ///
    /// We judge coverage by AREA FRACTION (≥ the threshold below) rather than exact
    /// containment: no ordinary window ever covers the menu-bar strip or the Dock,
    /// so requiring full containment would essentially never trigger. A maximized or
    /// full-screen window covers ~95–100% and counts; scattered windows each cover
    /// far less, so the wallpaper keeps animating (correct — it's visible between
    /// them). Everything stays in CG top-left coords (CGDisplayBounds and
    /// CGWindowBounds share that space), so there's no bottom-left↔top-left mixup.
    ///
    /// Note: this uses the single largest-covering window, so two side-by-side
    /// half-screen windows read as "not covered" and we keep animating. That errs
    /// toward drawing when uncertain — safe (never freezes while visible), at worst
    /// a little extra CPU in an uncommon layout.
    private static let coverageThreshold: CGFloat = 0.92

    private func allWallpaperDisplaysCovered() -> Bool {
        let ids = Array(windows.keys)
        guard !ids.isEmpty else { return false }
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        // Precompute normal (layer 0), non-self window rects once.
        var rects: [CGRect] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"]
            else { continue }
            rects.append(CGRect(x: x, y: y, width: width, height: height))
        }
        if rects.isEmpty { return false }

        for id in ids {
            let db = CGDisplayBounds(id) // top-left coords, matches CGWindowBounds
            let dbArea = db.width * db.height
            guard dbArea > 0 else { continue }
            let maxCoverage = rects.reduce(CGFloat(0)) { best, r in
                let inter = r.intersection(db)
                guard !inter.isNull else { return best }
                return max(best, (inter.width * inter.height) / dbArea)
            }
            if maxCoverage < Self.coverageThreshold { return false }
        }
        return true
    }

    // MARK: PlaybackGovernorDelegate

    private var governorRunning = false

    func governorShouldRun(_ run: Bool) {
        governorRunning = run
        applyRunState(run)
    }

    func governorSetPreferredFPS(_ fps: Int) {
        for v in views.values { v.maxFPS = fps }
    }

    private func applyRunState(_ run: Bool) {
        for v in views.values {
            if run { v.start() } else { v.stop() }
        }
    }

    // MARK: Status bar menu

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⛰"
        item.button?.toolTip = "Manifold Wallpaper"
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let themeHeader = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeHeader.isEnabled = false
        menu.addItem(themeHeader)
        for t in WallpaperTheme.allCases {
            let mi = NSMenuItem(title: "  " + t.label, action: #selector(pickTheme(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = t.rawValue
            mi.state = (settings.theme == t) ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())

        let walkers = NSMenuItem(title: "Walker particles", action: #selector(toggleWalkers), keyEquivalent: "")
        walkers.target = self
        walkers.state = settings.showWalkers ? .on : .off
        menu.addItem(walkers)

        let battery = NSMenuItem(title: "Pause on battery", action: #selector(toggleBattery), keyEquivalent: "")
        battery.target = self
        battery.state = settings.pauseOnBattery ? .on : .off
        menu.addItem(battery)

        menu.addItem(.separator())

        let footer = NSMenuItem(title: "Show message", action: #selector(toggleFooter), keyEquivalent: "")
        footer.target = self
        footer.state = settings.showFooter ? .on : .off
        menu.addItem(footer)

        let setMsg = NSMenuItem(title: "Set message…", action: #selector(editFooter), keyEquivalent: "")
        setMsg.target = self
        menu.addItem(setMsg)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Manifold Wallpaper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func refreshMenu() { statusItem?.menu = buildMenu() }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        guard let t = WallpaperTheme(rawValue: sender.tag) else { return }
        settings.theme = t
        applyTheme(animated: true)
        refreshMenu()
    }

    @objc private func toggleWalkers() {
        settings.showWalkers.toggle()
        for v in views.values { v.setShowWalkers(settings.showWalkers) }
        refreshMenu()
    }

    @objc private func toggleBattery() {
        settings.pauseOnBattery.toggle()
        governor.pauseOnBattery = settings.pauseOnBattery
        refreshMenu()
    }

    @objc private func toggleFooter() {
        settings.showFooter.toggle()
        applyFooter()
        refreshMenu()
    }

    @objc private func editFooter() {
        let alert = NSAlert()
        alert.messageText = "Signature message"
        alert.informativeText = "A small italic line shown in the bottom-left corner."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = settings.footerMessage
        field.placeholderString = WallpaperSettings.defaultFooter
        alert.accessoryView = field
        // Give the text field focus so the user can type immediately.
        alert.window.initialFirstResponder = field

        // A panel from a menu-bar agent needs the app frontmost to receive the modal.
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            settings.footerMessage = field.stringValue
            // Editing the text implies you want to see it.
            if !settings.showFooter { settings.showFooter = true }
            applyFooter()
            refreshMenu()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Ad-hoc builds can fail here; surface it and deep-link to the settings pane.
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can toggle it manually in System Settings → General → Login Items."
            alert.runModal()
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
