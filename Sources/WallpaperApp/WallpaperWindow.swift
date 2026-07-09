//
//  WallpaperWindow.swift
//  A borderless window pinned at the DESKTOP level — above the static system
//  wallpaper, below the Finder desktop icons and every normal window — so its
//  contents read as a live wallpaper. Click-through and never key/main, so it
//  never steals focus or interaction from the desktop.
//
//  This is the same technique every third-party macOS live-wallpaper app uses
//  (Plash, Mural, …): Apple exposes no public wallpaper API, so we own our own
//  desktop-level NSWindow. Verified working on macOS 26 (Tahoe).
//

import AppKit

final class WallpaperWindow: NSWindow {

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        // Desktop level: above the OS wallpaper, below the desktop icons. Derive it
        // at runtime — the raw value differs across OS versions and the CGWindowLevelKey
        // enum's declaration order is NOT its numeric order, so never hardcode.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // One window per screen, so each already redraws on its own Space; we omit
        // .canJoinAllSpaces (it mis-orders against full-screen Spaces on Tahoe).
        // .stationary keeps it put during Mission Control; .ignoresCycle hides it
        // from Cmd-` window cycling; .fullScreenNone keeps it out of full-screen UI.
        collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]

        ignoresMouseEvents = true      // clicks pass through to icons / Finder
        isOpaque = true                // the terrain paints an opaque sky, no blending
        hasShadow = false
        backgroundColor = .black
        animationBehavior = .none
        isReleasedWhenClosed = false   // we manage lifetime ourselves (avoids a UAF)
    }

    // Never participate in key/main focus — this is chrome-free desktop content.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Place (or re-place) the window to cover exactly one screen, ordered at the
    /// back without ever activating the app.
    func pin(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
        orderFrontRegardless()
    }
}

extension NSScreen {
    /// The stable CoreGraphics display id for this screen. Use this as a dictionary
    /// key rather than the NSScreen object or its index, both of which churn when
    /// displays are added/removed or rearranged.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
