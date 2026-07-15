//
//  TerrainConfig.swift
//  The render knobs shared by BOTH products (screen saver + live wallpaper):
//  palette, surface function, shape-lighting, zoom, breathing, and walkers.
//
//  This is the single source of truth for each shared knob's persistence KEY,
//  DEFAULT, and CLAMP range. Before this existed, the two independent stores
//  (Settings over ScreenSaverDefaults, WallpaperSettings over a UserDefaults suite)
//  each re-declared the same keys/defaults/clamp literals — so a value changed in
//  one could silently diverge from the other, and adding a knob meant editing both.
//  Now both stores read/register through here, and the renderer gets one `apply`
//  path (see TerrainRenderer.apply) instead of a hand-copied push block per call
//  site. Framework-free (plain UserDefaults — ScreenSaverDefaults IS one), so the
//  wallpaper app stays free of the ScreenSaver framework.
//
//  NOTE: the key strings below are the ones already on disk in shipping installs —
//  do not rename them or users' stored preferences would reset.
//

import Foundation

extension ClosedRange where Bound == Double {
    /// Clamp a value into this range.
    func clamp(_ v: Double) -> Double { Swift.min(upperBound, Swift.max(lowerBound, v)) }
}

/// A snapshot of the shared terrain render knobs. Read from a store with
/// `init(reading:)`, pushed to the engine with `TerrainRenderer.apply(_:palette:animated:)`.
struct TerrainConfig {
    var palettePreset: PalettePreset
    var terrainFunction: TerrainFunction
    var lightingEnabled: Bool
    var zoomOut: Double
    var breathStrength: Double
    var showWalkers: Bool

    /// Persisted key strings (shared verbatim by both stores — see NOTE above).
    enum Key {
        static let palettePreset = "palettePreset"
        static let terrainFunction = "terrainFunction"
        static let lighting = "lightingEnabled"
        static let zoom = "zoomLevel"
        static let breath = "breathStrength"
        static let walkers = "showWalkers"
    }

    // Defaults + clamp ranges — the single definition both stores (and the config
    // sheet's slider bounds) point at, so the UI, the clamp, and the two products
    // can never disagree.
    static let defaultZoom = 0.85
    static let zoomRange: ClosedRange<Double> = 0.6...1.15
    static let defaultBreath = 1.0
    static let breathRange: ClosedRange<Double> = 0.0...2.0
    static let defaultLighting = true    // Eye-Dome Lighting on — it's the shape cue
    static let defaultWalkers = false    // off — the breathing field stands on its own

    /// The `register(defaults:)` entries for the shared knobs. Each store merges its
    /// own product-specific keys (clock/font/footer, battery, etc.) on top of these.
    static var registrationDefaults: [String: Any] {
        [
            Key.palettePreset: PalettePreset.classic.rawValue,
            Key.terrainFunction: TerrainFunction.classic.rawValue,
            Key.lighting: defaultLighting,
            Key.zoom: defaultZoom,
            Key.breath: defaultBreath,
            Key.walkers: defaultWalkers,
        ]
    }

    /// Read the shared knobs from any store, applying fallbacks + clamps. Self-
    /// contained: it does not rely on `register(defaults:)` having run, so a stray or
    /// missing value can't produce an out-of-range zoom/breath or an unknown enum.
    init(reading d: UserDefaults) {
        palettePreset = PalettePreset(rawValue: d.integer(forKey: Key.palettePreset)) ?? .classic
        terrainFunction = TerrainFunction(rawValue: d.integer(forKey: Key.terrainFunction)) ?? .classic
        lightingEnabled = d.object(forKey: Key.lighting) as? Bool ?? TerrainConfig.defaultLighting
        zoomOut = TerrainConfig.zoomRange.clamp(d.object(forKey: Key.zoom) as? Double ?? TerrainConfig.defaultZoom)
        breathStrength = TerrainConfig.breathRange.clamp(d.object(forKey: Key.breath) as? Double ?? TerrainConfig.defaultBreath)
        showWalkers = d.object(forKey: Key.walkers) as? Bool ?? TerrainConfig.defaultWalkers
    }
}
