//
//  WallpaperSettings.swift
//  Persisted options for the Manifold live wallpaper, backed by a private
//  UserDefaults suite. Deliberately tiny and independent of the screensaver's
//  Settings.swift / ScreenSaverDefaults — the wallpaper app never links the
//  ScreenSaver framework. No clock by design; an optional bottom-left signature
//  line is the only text.
//

import AppKit

/// Theme choice for the wallpaper. Mirrors the saver's ThemePreference values so
/// the two feel like one product, but lives in its own type to keep the app free
/// of the ScreenSaver framework.
enum WallpaperTheme: Int, CaseIterable {
    case auto = 0   // follow the system (light/dark), with an animated cross-fade
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .auto: return "Auto (match system)"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// UserDefaults-backed options. The suite name is namespaced under the app's
/// bundle id so it never collides with the saver's ByHost store.
final class WallpaperSettings {
    private let defaults: UserDefaults

    // Wallpaper-only keys. The shared render knobs (palette/surface/lighting/zoom/
    // breath/walkers) live in TerrainConfig.Key — read/clamped through TerrainConfig
    // so the saver and wallpaper can never diverge on keys, defaults, or clamps.
    private let kTheme = "theme"
    private let kPauseOnBattery = "pauseOnBattery"
    private let kShowFooter = "showFooter"
    private let kFooter = "footerMessage"

    /// Shipping default footer — placeholder text, personalized per install.
    static let defaultFooter = "Lorem Ipsum"

    init(suiteName: String = "com.ingtian.manifold.wallpaper") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        var d: [String: Any] = [
            kTheme: WallpaperTheme.auto.rawValue,
            kPauseOnBattery: false,   // keep it alive on battery by default (15fps)
            kShowFooter: false,       // no signature line unless the user turns it on
            kFooter: WallpaperSettings.defaultFooter,
        ]
        // Shared render knobs — one source of truth (see TerrainConfig).
        d.merge(TerrainConfig.registrationDefaults) { current, _ in current }
        defaults.register(defaults: d)
    }

    // MARK: Shared render knobs (single source of truth in TerrainConfig)

    /// The shared terrain render configuration, read/clamped through TerrainConfig
    /// so the saver and wallpaper can never diverge on keys, defaults, or clamps.
    var terrainConfig: TerrainConfig { TerrainConfig(reading: defaults) }

    var showWalkers: Bool {
        get { defaults.bool(forKey: TerrainConfig.Key.walkers) }
        set { defaults.set(newValue, forKey: TerrainConfig.Key.walkers) }
    }

    /// Eye-Dome Lighting (the shape cue). Default on.
    var lightingEnabled: Bool {
        get { defaults.bool(forKey: TerrainConfig.Key.lighting) }
        set { defaults.set(newValue, forKey: TerrainConfig.Key.lighting) }
    }

    /// Chosen color scheme. Falls back to Classic for any unknown stored value.
    var palettePreset: PalettePreset {
        get { PalettePreset(rawValue: defaults.integer(forKey: TerrainConfig.Key.palettePreset)) ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: TerrainConfig.Key.palettePreset) }
    }

    /// Chosen terrain height field. Falls back to Classic for any unknown value.
    var terrainFunction: TerrainFunction {
        get { TerrainFunction(rawValue: defaults.integer(forKey: TerrainConfig.Key.terrainFunction)) ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: TerrainConfig.Key.terrainFunction) }
    }

    /// Camera pull-back (renderer `zoomOut`). Clamped to TerrainConfig.zoomRange.
    var zoomLevel: Double {
        get { terrainConfig.zoomOut }
        set { defaults.set(TerrainConfig.zoomRange.clamp(newValue), forKey: TerrainConfig.Key.zoom) }
    }

    /// Breathing-motion strength (renderer `breathStrength`). Clamped to TerrainConfig.breathRange.
    var breathStrength: Double {
        get { terrainConfig.breathStrength }
        set { defaults.set(TerrainConfig.breathRange.clamp(newValue), forKey: TerrainConfig.Key.breath) }
    }

    // MARK: Wallpaper-only options

    var theme: WallpaperTheme {
        get { WallpaperTheme(rawValue: defaults.integer(forKey: kTheme)) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: kTheme) }
    }

    var pauseOnBattery: Bool {
        get { defaults.bool(forKey: kPauseOnBattery) }
        set { defaults.set(newValue, forKey: kPauseOnBattery) }
    }

    /// Whether to draw the small signature line in the bottom-left corner.
    var showFooter: Bool {
        get { defaults.bool(forKey: kShowFooter) }
        set { defaults.set(newValue, forKey: kShowFooter) }
    }

    /// The footer text. Empty string also hides it.
    var footerMessage: String {
        get { defaults.string(forKey: kFooter) ?? WallpaperSettings.defaultFooter }
        set { defaults.set(newValue, forKey: kFooter) }
    }
}
