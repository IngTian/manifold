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

    private let kTheme = "theme"
    private let kWalkers = "showWalkers"
    private let kPauseOnBattery = "pauseOnBattery"
    private let kShowFooter = "showFooter"
    private let kFooter = "footerMessage"
    private let kZoomLevel = "zoomLevel"
    private let kLighting = "lightingEnabled"
    private let kPalettePreset = "palettePreset"
    private let kBreathStrength = "breathStrength"

    /// Shipping default footer — placeholder text, personalized per install.
    static let defaultFooter = "Lorem Ipsum"

    /// Camera pull-back (renderer `zoomOut`) default. The menu offers a few discrete
    /// steps (a menu can't host a slider).
    static let defaultZoom = 0.85

    /// Breathing-motion strength multiplier default. The menu offers discrete steps.
    static let defaultBreath = 1.0

    init(suiteName: String = "com.ingtian.manifold.wallpaper") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.register(defaults: [
            kTheme: WallpaperTheme.auto.rawValue,
            kWalkers: false,          // the breathing field stands on its own
            kPauseOnBattery: false,   // keep it alive on battery by default (15fps)
            kShowFooter: false,       // no signature line unless the user turns it on
            kFooter: WallpaperSettings.defaultFooter,
            kZoomLevel: WallpaperSettings.defaultZoom,
            kLighting: true,          // Eye-Dome Lighting on by default — the shape cue
            kPalettePreset: PalettePreset.classic.rawValue,
            kBreathStrength: WallpaperSettings.defaultBreath,
        ])
    }

    var theme: WallpaperTheme {
        get { WallpaperTheme(rawValue: defaults.integer(forKey: kTheme)) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: kTheme) }
    }

    var showWalkers: Bool {
        get { defaults.bool(forKey: kWalkers) }
        set { defaults.set(newValue, forKey: kWalkers) }
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

    /// Camera pull-back (renderer `zoomOut`). Clamped to the same 0.6…1.15 range the
    /// saver uses so the two products behave identically.
    var zoomLevel: Double {
        get {
            let v = defaults.object(forKey: kZoomLevel) as? Double ?? WallpaperSettings.defaultZoom
            return min(1.15, max(0.6, v))
        }
        set { defaults.set(min(1.15, max(0.6, newValue)), forKey: kZoomLevel) }
    }

    /// Eye-Dome Lighting (the shape cue). Default on.
    var lightingEnabled: Bool {
        get { defaults.bool(forKey: kLighting) }
        set { defaults.set(newValue, forKey: kLighting) }
    }

    /// Chosen color scheme. Falls back to Classic for any unknown stored value.
    var palettePreset: PalettePreset {
        get { PalettePreset(rawValue: defaults.integer(forKey: kPalettePreset)) ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: kPalettePreset) }
    }

    /// Breathing-motion strength (renderer `breathStrength`). Clamped to the same
    /// 0…2 range the saver uses so the two products behave identically.
    var breathStrength: Double {
        get {
            let v = defaults.object(forKey: kBreathStrength) as? Double ?? WallpaperSettings.defaultBreath
            return min(2.0, max(0.0, v))
        }
        set { defaults.set(min(2.0, max(0.0, newValue)), forKey: kBreathStrength) }
    }
}
