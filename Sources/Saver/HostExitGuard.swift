//
//  HostExitGuard.swift
//  Terminates the `legacyScreenSaver` host process when macOS says the screen
//  saver is stopping.
//
//  WHY THIS EXISTS (measured, not guessed):
//  macOS runs third-party .saver plug-ins out-of-process inside
//  `legacyScreenSaver.appex`. That host over-retains ScreenSaverView instances,
//  does NOT reliably call stopAnimation() on the ones it abandons, and its own
//  animation timer keeps firing forever — Apple's -[ScreenSaverView _oneStep:]
//  gates only on `window != nil`, never on whether that window is on screen.
//  The abandoned view therefore keeps rendering full frames into a window nothing
//  composites: one instance here burned 159 CPU-hours over 9 days at ~50% CPU.
//
//  WHY WE KILL THE HOST INSTEAD OF JUST NOT DRAWING:
//  No window property distinguishes "legitimately on screen" from "abandoned".
//  Measured inside the real host: after dismissal the saver window still reports
//  `isVisible == true`, and `occlusionState.contains(.visible)` is *false* even
//  while the saver is genuinely frontmost at CGShieldingWindowLevel (so gating on
//  occlusion would freeze the real screen saver). xscreensaver's source says the
//  same thing: "That invisible window is both 'visible' and 'onActiveSpace', and
//  has no parentWindow, so its invisibility is not detectable."
//
//  Killing the host is consequently the de-facto standard fix across the
//  ecosystem — xscreensaver (its SONOMA_KLUDGE), Aerial, the Aerial team's
//  ScreenSaverMinimal reference template, webviewscreensaver, and ~30 other
//  shipping savers. Apple has no sanctioned alternative; the relevant feedback
//  reports are still open.
//

import AppKit

/// Watches for "the screen saver is stopping" and exits the hosting process a
/// beat later, so an abandoned-but-still-ticking saver view cannot keep burning
/// CPU indefinitely. Inert unless armed for a real, full-screen, system-hosted run.
final class HostExitGuard {

    /// Host executables we are willing to terminate. Anything else — the
    /// tools/render.swift harness, System Settings itself, a future preview app —
    /// must survive a stray broadcast untouched.
    private static let killableHosts: Set<String> = [
        "legacyScreenSaver", "legacyScreenSaver-x86_64", "ScreenSaverEngine",
    ]

    /// Load-bearing, not arbitrary: exiting synchronously from the willstop
    /// handler races the host's own relaunch (observed 270–700 ms later) and
    /// leaves a black screen on the next activation. A ~2 s delay is what the
    /// shipping savers converged on.
    private static let exitDelay: TimeInterval = 2.0

    /// Below this we don't bother arming: recent macOS spawns 0×0 "ghost" view
    /// instances, and the small System Settings thumbnail (~296×184) isn't worth the
    /// churn. NOTE this is a cheap sanity filter, NOT a reliable "preview vs. real"
    /// test — a preview pane on a big display easily exceeds it. That's acceptable
    /// because the TRIGGER is session-scoped: the screensaver-stopping notifications
    /// are posted when a screen-saver *session* ends, not when a Settings pane
    /// closes, so arming in a preview normally never fires. Worst case (a real
    /// session ends while Settings happens to be open) the thumbnail blanks until
    /// the pane respawns the host — cosmetic and self-healing.
    private static let minRealRunSize = CGSize(width: 400, height: 300)

    /// Called before exiting so we stop our own work even if the exit is
    /// prevented or delayed.
    private let teardown: () -> Void
    private var armed = false
    private var fired = false

    init(teardown: @escaping () -> Void) { self.teardown = teardown }

    /// Arm only for a real, full-screen, system-hosted run. Idempotent, and a
    /// no-op anywhere it could do harm.
    func armIfRealRun(viewSize: CGSize) {
        guard !armed, !fired else { return }
        // Never terminate a process that isn't a screen-saver host.
        guard Self.killableHosts.contains(ProcessInfo.processInfo.processName) else { return }
        // Deliberately NOT `isPreview`: it is unreliable in BOTH directions across
        // macOS versions (reported always-true on some, inverted on others), and
        // trusting it would silently disable this fix on the versions that need it.
        // The size check is only a sanity filter (see minRealRunSize) — safety comes
        // from the trigger being session-scoped, plus the killableHosts check above.
        guard viewSize.width >= Self.minRealRunSize.width,
              viewSize.height >= Self.minRealRunSize.height else { return }
        armed = true

        // `willstop` is the primary signal; `didstop` is a redundant second
        // trigger because willstop delivery is NOT guaranteed (observed missing on
        // some releases). The handler is fire-once, so hearing both is harmless.
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
            dnc.addObserver(self, selector: #selector(hostShouldExit),
                            name: Notification.Name(name), object: nil)
        }
        // Covers the display-sleep path, where willstop never arrives at all.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(hostShouldExit),
            name: NSWorkspace.willSleepNotification, object: nil)
    }

    /// Stop listening. Safe to call repeatedly, and required from `deinit` — this
    /// host leaks view instances, and a selector-based observer would otherwise
    /// keep a dead view registered.
    func disarm() {
        guard armed else { return }
        armed = false
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func hostShouldExit() {
        guard !fired else { return }
        fired = true
        // Deregister immediately: if the host is relaunched and reuses this
        // process, it must not inherit our arm.
        disarm()
        // Shed our own work first, so CPU drops even if the exit never happens.
        teardown()
        // asyncAfter on the main queue (not Timer) because the main queue is
        // drained in common run-loop modes — this still fires while an unlock
        // prompt has the run loop in tracking mode. exit(0) rather than
        // NSApplication.terminate(nil): terminate runs applicationShouldTerminate
        // and friends inside a process that isn't ours to shut down politely.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.exitDelay) { exit(0) }
    }
}
