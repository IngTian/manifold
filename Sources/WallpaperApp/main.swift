//
//  main.swift
//  Entry point for the Manifold live-wallpaper agent app. No storyboard, no nib —
//  a plain AppKit accessory app assembled in code and built with swiftc.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory policy is also set in didFinishLaunching; setting it here too means we
// never briefly flash a Dock icon during launch.
app.setActivationPolicy(.accessory)
app.run()
