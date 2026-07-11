//
//  render.swift
//  Headless render/verify harness for both Manifold products.
//
//    render saver     <path-to-.saver> <outdir> [w h]
//    render wallpaper <outdir> [w h]
//
//  SAVER mode loads the built .saver bundle and instantiates its NSPrincipalClass
//  exactly the way the ScreenSaver host does (initWithFrame:isPreview:), then drives
//  startAnimation/animateOneFrame and captures draw(_:) output. This proves the
//  *real shipping bundle* loads and renders — not a re-compiled copy of the sources.
//
//  WALLPAPER mode has no loadable bundle to open (the wallpaper is a plain .app
//  executable, not a ScreenSaver plug-in), so it drives the SHARED `TerrainRenderer`
//  directly — the identical engine the wallpaper app renders through — configured
//  from the wallpaper's own WallpaperSettings. No terrain math is re-implemented; the
//  only glue here is the offscreen bitmap + the same Y-down flip both views apply.
//  (The optional bottom-left footer is a wallpaper-view overlay, not part of the
//  terrain, so it isn't drawn here — palette/shape/zoom are what this verifies.)
//
//  THEME=light|dark forces the appearance in both modes (default dark). In wallpaper
//  mode PALETTE=<int>, LIGHTING=0|1, ZOOM=<double> override the persisted settings.
//
//  Compiled with `@main` + `-parse-as-library` alongside Palette.swift +
//  TerrainRenderer.swift + WallpaperSettings.swift, under its OWN module name (not
//  "Manifold") so the compiled-in TerrainRenderer can't collide with the copy inside
//  a dlopen'd .saver bundle.
//

import AppKit
import ScreenSaver

@main
struct Render {
    static func die(_ msg: String) -> Never {
        FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
        exit(1)
    }

    static func ensureDir(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    static func writePNG(_ rep: NSBitmapImageRep, to path: String) {
        guard let data = rep.representation(using: .png, properties: [:]) else { die("png encode failed") }
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)  (\(data.count) bytes)")
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            die("usage:\n  render saver <.saver> <outdir> [w h]\n  render wallpaper <outdir> [w h]")
        }
        let mode = args[1]

        // Fresh appearance so theme=auto is deterministic. THEME env forces light/dark.
        let wantDark = (ProcessInfo.processInfo.environment["THEME"] ?? "dark") != "light"

        switch mode {
        case "saver":     renderSaver(args, wantDark: wantDark)
        case "wallpaper": renderWallpaper(args, wantDark: wantDark)
        default:
            die("unknown mode '\(mode)'. usage:\n  render saver <.saver> <outdir> [w h]\n  render wallpaper <outdir> [w h]")
        }
    }

    // MARK: Saver — load the real .saver bundle and drive its principal class.

    static func renderSaver(_ args: [String], wantDark: Bool) {
        guard args.count >= 4 else { die("usage: render saver <.saver> <outdir> [w h]") }
        let saverPath = args[2]
        let outDir = args[3]
        let width = args.count > 4 ? Int(args[4])! : 1600
        let height = args.count > 5 ? Int(args[5])! : 1000

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
        view.appearance = NSAppearance(named: wantDark ? .darkAqua : .aqua)
        view.startAnimation()
        ensureDir(outDir)

        // The saver renders off the real Date() clock (we can't inject time into the
        // opaque bundle), so sleep between grabs to advance breathing + walkers.
        let grabs: [(String, useconds_t)] = [
            ("frame_00_t0.png", 0),
            ("frame_01_t250ms.png", 250_000),
            ("frame_02_t800ms.png", 550_000),
            ("frame_03_t2s.png", 1_200_000),
            ("frame_04_t3s.png", 1_000_000),
            ("frame_05_t5s.png", 2_000_000),
            ("frame_06_t7s.png", 2_000_000),
        ]
        for (name, delay) in grabs {
            if delay > 0 { usleep(delay) }
            view.animateOneFrame()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { die("no bitmap rep") }
            view.cacheDisplay(in: view.bounds, to: rep)
            writePNG(rep, to: (outDir as NSString).appendingPathComponent(name))
        }
        view.stopAnimation()
        print("done")
    }

    // MARK: Wallpaper — drive the shared TerrainRenderer with the wallpaper's settings.

    static func renderWallpaper(_ args: [String], wantDark: Bool) {
        guard args.count >= 3 else { die("usage: render wallpaper <outdir> [w h]") }
        let outDir = args[2]
        let width = args.count > 3 ? Int(args[3])! : 1600
        let height = args.count > 4 ? Int(args[4])! : 1000

        // Reflect the wallpaper's real configuration (env can override any of the three).
        let settings = WallpaperSettings()
        let env = ProcessInfo.processInfo.environment
        let preset = env["PALETTE"].flatMap { Int($0) }.flatMap { PalettePreset(rawValue: $0) }
            ?? settings.palettePreset
        let lighting = env["LIGHTING"].map { $0 != "0" } ?? settings.lightingEnabled
        let zoom = env["ZOOM"].flatMap { Double($0) } ?? settings.zoomLevel
        let breath = env["BREATH"].flatMap { Double($0) } ?? settings.breathStrength
        let palette = preset.palette(dark: wantDark)   // mirrors AppDelegate.resolvedPalette
        print("Wallpaper — palette: \(preset.label) \(wantDark ? "dark" : "light"), lighting: \(lighting), zoom: \(zoom), breath: \(breath)")

        let renderer = TerrainRenderer(palette: palette, animateWalkers: false)
        renderer.lightingEnabled = lighting
        renderer.zoomOut = zoom
        renderer.breathStrength = breath
        renderer.setPaletteImmediately(palette)
        let size = CGSize(width: width, height: height)
        ensureDir(outDir)

        // We drive the renderer directly, so inject nowMs instead of sleeping.
        let times: [(String, Double)] = [
            ("frame_00_t0.png", 0),
            ("frame_01_t800ms.png", 800),
            ("frame_02_t2s.png", 2000),
            ("frame_03_t5s.png", 5000),
        ]
        for (name, nowMs) in times {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { die("no bitmap rep") }
            guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { die("no gfx context") }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            let cg = ctx.cgContext
            cg.saveGState()
            // Flip into the renderer's Y-down space — the same flip both real views apply.
            if !ctx.isFlipped {
                cg.translateBy(x: 0, y: CGFloat(height))
                cg.scaleBy(x: 1, y: -1)
            }
            renderer.render(in: cg, size: size, nowMs: nowMs, animate: true)
            cg.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            writePNG(rep, to: (outDir as NSString).appendingPathComponent(name))
        }
        print("done")
    }
}
