//
//  PlaybackGovernor.swift
//  Decides WHEN the wallpaper should animate and at what frame rate, so an
//  all-day desktop animation costs almost nothing when nobody can see it.
//
//  Pause when: the display is fully covered by a window, the display sleeps, the
//  screen is locked, the real screensaver is running, or (optionally) on battery.
//  Slow to 15fps on battery / Low Power Mode. Otherwise run at 30fps.
//
//  Why not NSWindow.occlusionState? It is unreliable for desktop-level windows —
//  it reports .visible even when fully covered. So coverage is detected by
//  enumerating the on-screen window list (the approach the Mural live-wallpaper
//  app uses for the same reason).
//

import AppKit
import IOKit.ps

/// Callbacks the governor drives. The owner (AppDelegate) implements these to
/// start/stop the per-screen views and set their frame rate.
protocol PlaybackGovernorDelegate: AnyObject {
    func governorShouldRun(_ run: Bool)
    func governorSetPreferredFPS(_ fps: Int)
}

final class PlaybackGovernor {

    weak var delegate: PlaybackGovernorDelegate?

    /// User setting: pause entirely while on battery (default off — we prefer to
    /// keep it alive at a reduced rate).
    var pauseOnBattery = false { didSet { reevaluate() } }

    /// Set by the owner: is at least one wallpaper window's display currently
    /// covered by a full-screen window? (Owner recomputes on demand.)
    private var allDisplaysCovered = false

    // Environment state.
    private var displayAsleep = false
    private var screenLocked = false
    private var screensaverActive = false
    private var onBattery = false
    private var lowPower = false

    private var running = false
    private var currentFPS = 30

    /// The FPS the governor currently wants (30 normally, 15 on battery / Low Power).
    /// Read by the owner when it builds a new view (e.g. a hot-plugged display) so
    /// the new view starts at the right rate instead of the 30fps default.
    var preferredFPS: Int { currentFPS }

    // A low-frequency safety poll: coverage/battery have no perfect notification,
    // so we re-check periodically — but ONLY while running, so the governor never
    // burns the battery it is trying to save.
    private var safetyTimer: Timer?
    private var coverageProbe: (() -> Bool)?
    private var powerSourceRunLoopSource: CFRunLoopSource?

    init() {
        onBattery = Self.readOnBattery()
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        registerObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        if let src = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        safetyTimer?.invalidate()
    }

    /// The owner supplies a closure that returns true when every wallpaper display
    /// is fully covered (so animation is pointless). Called on start + safety poll.
    func setCoverageProbe(_ probe: @escaping () -> Bool) {
        coverageProbe = probe
    }

    // MARK: Observers

    private func registerObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(powerStateChanged),
                       name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)

        // Display sleep/wake and lock/unlock live on the *workspace* center.
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(self, selector: #selector(displaySlept),
                        name: NSWorkspace.screensDidSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(displayWoke),
                        name: NSWorkspace.screensDidWakeNotification, object: nil)
        wnc.addObserver(self, selector: #selector(activeSpaceChanged),
                        name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // Lock / screensaver are distributed notifications (undocumented but stable).
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLockedNote),
                        name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlockedNote),
                        name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screensaverStarted),
                        name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(screensaverStopped),
                        name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)

        registerPowerSourceCallback()
    }

    /// IOKit push notification for AC↔battery transitions (separate from Low Power
    /// Mode). The callback carries no payload, so we just re-read state.
    private func registerPowerSourceCallback() {
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let me = Unmanaged<PlaybackGovernor>.fromOpaque(context).takeUnretainedValue()
            me.powerSourceChanged()
        }, ctx)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        powerSourceRunLoopSource = src
    }

    // MARK: Notification handlers

    @objc private func powerStateChanged() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        reevaluate()
    }
    private func powerSourceChanged() {
        onBattery = Self.readOnBattery()
        reevaluate()
    }
    @objc private func displaySlept()  { displayAsleep = true;  reevaluate() }
    @objc private func displayWoke()   { displayAsleep = false; reevaluate() }
    @objc private func screenLockedNote()   { screenLocked = true;  reevaluate() }
    @objc private func screenUnlockedNote() { screenLocked = false; reevaluate() }
    @objc private func screensaverStarted() { screensaverActive = true;  reevaluate() }
    @objc private func screensaverStopped() { screensaverActive = false; reevaluate() }
    @objc private func activeSpaceChanged() { refreshCoverage(); reevaluate() }

    // MARK: Coverage

    /// Re-run the owner's coverage probe. Cheap enough to call on space changes and
    /// on the safety poll.
    func refreshCoverage() {
        allDisplaysCovered = coverageProbe?() ?? false
    }

    // MARK: Core decision

    /// Kick a fresh evaluation (call after any external state change, e.g. the app
    /// just built its windows).
    func start() {
        refreshCoverage()
        reevaluate(force: true)
    }

    private var shouldRun: Bool {
        if displayAsleep || screenLocked || screensaverActive { return false }
        if allDisplaysCovered { return false }
        if pauseOnBattery && onBattery { return false }
        return true
    }

    private var targetFPS: Int {
        (onBattery || lowPower) ? 15 : 30
    }

    private func reevaluate(force: Bool = false) {
        let run = shouldRun
        let fps = targetFPS

        if fps != currentFPS {
            currentFPS = fps
            delegate?.governorSetPreferredFPS(fps)
        }

        if run != running || force {
            running = run
            delegate?.governorShouldRun(run)
        }
        updateSafetyTimer()
    }

    // MARK: Safety poll
    //
    // Coverage and battery have no reliable "changed" notification, so we poll.
    // Crucially the poll must run whenever the screen is a *candidate* for showing
    // the wallpaper — i.e. awake and unlocked — NOT only while animating. Otherwise,
    // once a window covers the desktop and we pause, nothing would ever notice the
    // window closing (un-coverage), and the wallpaper would stay frozen. When the
    // display is asleep / locked / in the real screensaver, no window changes can
    // matter, so we stop the poll then (that's the actual battery win).

    private var shouldPoll: Bool {
        !(displayAsleep || screenLocked || screensaverActive)
    }

    private func updateSafetyTimer() {
        if shouldPoll {
            guard safetyTimer == nil else { return }
            let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.refreshCoverage()
                self.onBattery = Self.readOnBattery()
                self.reevaluate()
            }
            t.tolerance = 0.5 // coalesce with other timers to save power
            RunLoop.main.add(t, forMode: .common)
            safetyTimer = t
        } else {
            safetyTimer?.invalidate()
            safetyTimer = nil
        }
    }

    // MARK: Power source read

    static func readOnBattery() -> Bool {
        // IOPSCopyPowerSourcesInfo is a "Copy" (owned → takeRetainedValue), but
        // IOPSGetProvidingPowerSourceType is a "Get" (unowned → takeUnretainedValue).
        // Using takeRetainedValue on the Get result would over-release the CFString.
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
