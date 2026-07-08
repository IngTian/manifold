//
//  render_frames.swift
//  Headless verification harness. It loads the built Manifold.saver bundle,
//  instantiates its NSPrincipalClass exactly the way the ScreenSaver host does
//  (initWithFrame:isPreview:), then drives startAnimation/animateOneFrame and
//  captures draw(_:) output into PNGs at several timestamps.
//
//  This proves the *real shipping bundle* loads and renders — not a re-compiled
//  copy of the sources.
//
//  Usage: swiftc harness -> ./render_frames <path-to-.saver> <outdir> [w h]
//

import AppKit
import ScreenSaver

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { die("usage: render_frames <.saver> <outdir> [w h]") }
let saverPath = args[1]
let outDir = args[2]
let width = args.count > 3 ? Int(args[3])! : 1600
let height = args.count > 4 ? Int(args[4])! : 1000

// Load the bundle and resolve the principal class.
guard let bundle = Bundle(path: saverPath) else { die("cannot open bundle: \(saverPath)") }
guard bundle.load() else { die("bundle.load() failed") }
guard let principal = bundle.principalClass else { die("no principalClass") }
guard let saverClass = principal as? ScreenSaverView.Type else {
    die("principalClass is not a ScreenSaverView subclass: \(principal)")
}
print("Loaded principal class: \(principal)")

let frame = NSRect(x: 0, y: 0, width: width, height: height)
guard let view = saverClass.init(frame: frame, isPreview: false) else {
    die("init(frame:isPreview:) returned nil")
}
view.frame = frame

// Fresh appearance so theme=auto is deterministic. THEME env var forces light/dark.
let themeEnv = ProcessInfo.processInfo.environment["THEME"] ?? "dark"
view.appearance = NSAppearance(named: themeEnv == "light" ? .aqua : .darkAqua)

view.startAnimation()

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Capture frames at a spread of elapsed times so we can see breathing + walkers.
// We can't fast-forward internal Date()-based time, so we sleep between grabs for
// the later frames; keep it short but enough for a walker to appear.
let grabs: [(String, useconds_t)] = [
    ("frame_00_t0.png", 0),
    ("frame_01_t250ms.png", 250_000),
    ("frame_02_t800ms.png", 550_000),
    ("frame_03_t2s.png", 1_200_000),
    ("frame_04_t3s.png", 1_000_000),
    ("frame_05_t5s.png", 2_000_000),
    ("frame_06_t7s.png", 2_000_000),
]

func capture(to path: String) {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        die("no bitmap rep")
    }
    // Clear then draw the full hierarchy.
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        die("png encode failed")
    }
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)  (\(data.count) bytes)")
}

for (name, delay) in grabs {
    if delay > 0 { usleep(delay) }
    view.animateOneFrame()
    capture(to: (outDir as NSString).appendingPathComponent(name))
}

view.stopAnimation()
print("done")
