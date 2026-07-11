//
//  Settings.swift
//  Persisted options, backed by ScreenSaverDefaults so they survive across
//  invocations and can be edited from the options sheet: 24-hour, seconds, date,
//  walkers, theme (auto/light/dark), font design, and the motto line.
//

import AppKit
import ScreenSaver

enum ThemePreference: Int {
    case auto = 0
    case light = 1
    case dark = 2
}

/// Which system font design to render the clock/motto in. Configurable in the
/// options sheet only (deliberately not adjustable live on screen).
enum FontDesign: Int, CaseIterable {
    case system = 0   // SF Pro
    case rounded = 1  // SF Rounded
    case serif = 2    // New York
    case mono = 3     // SF Mono

    var label: String {
        switch self {
        case .system: return "System (SF Pro)"
        case .rounded: return "Rounded"
        case .serif: return "Serif (New York)"
        case .mono: return "Monospace"
        }
    }

    var systemDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

/// Thin wrapper over ScreenSaverDefaults. `moduleName` must be the bundle
/// identifier of the .saver so preview and fullscreen share one store.
final class Settings {
    private let defaults: UserDefaults

    private let kUse24Hour = "use24Hour"
    private let kShowSeconds = "showSeconds"
    private let kShowDate = "showDate"
    private let kTheme = "themePreference"
    private let kWalkers = "showWalkers"
    private let kFontDesign = "fontDesign"
    private let kFooter = "footerMessage"
    private let kZoomLevel = "zoomLevel"
    private let kLighting = "lightingEnabled"
    private let kPalettePreset = "palettePreset"
    private let kBreathStrength = "breathStrength"

    /// Shipping default motto — placeholder text, personalized per install.
    static let defaultFooter = "Lorem Ipsum"

    /// How far the camera pulls back — larger shows more terrain footprint. Matches
    /// the renderer's `Projector.zoomOut` default; the slider spans 0.6…1.15.
    static let defaultZoom = 0.85

    /// Breathing-motion strength multiplier. 1.0 = the tuned default; the slider
    /// spans 0…2 (0 = still, 2 = double the wobble).
    static let defaultBreath = 1.0

    init(moduleName: String) {
        self.defaults = ScreenSaverDefaults(forModuleWithName: moduleName) ?? .standard
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            kUse24Hour: true,
            kShowSeconds: true,
            kShowDate: true,
            kTheme: ThemePreference.auto.rawValue,
            kWalkers: false, // walkers off — the breathing field stands on its own
            kFontDesign: FontDesign.system.rawValue,
            kFooter: Settings.defaultFooter,
            kZoomLevel: Settings.defaultZoom,
            kLighting: true, // Eye-Dome Lighting on by default — it's the shape cue
            kPalettePreset: PalettePreset.classic.rawValue,
            kBreathStrength: Settings.defaultBreath,
        ])
    }

    var use24Hour: Bool {
        get { defaults.bool(forKey: kUse24Hour) }
        set { defaults.set(newValue, forKey: kUse24Hour) }
    }

    var showSeconds: Bool {
        get { defaults.bool(forKey: kShowSeconds) }
        set { defaults.set(newValue, forKey: kShowSeconds) }
    }

    var showDate: Bool {
        get { defaults.bool(forKey: kShowDate) }
        set { defaults.set(newValue, forKey: kShowDate) }
    }

    var showWalkers: Bool {
        get { defaults.bool(forKey: kWalkers) }
        set { defaults.set(newValue, forKey: kWalkers) }
    }

    var theme: ThemePreference {
        get { ThemePreference(rawValue: defaults.integer(forKey: kTheme)) ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: kTheme) }
    }

    var fontDesign: FontDesign {
        get { FontDesign(rawValue: defaults.integer(forKey: kFontDesign)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: kFontDesign) }
    }

    /// The motto line under the clock. Empty string hides it.
    var footerMessage: String {
        get { defaults.string(forKey: kFooter) ?? Settings.defaultFooter }
        set { defaults.set(newValue, forKey: kFooter) }
    }

    /// Camera pull-back (renderer `zoomOut`). Clamped to the slider's 0.6…1.15 range
    /// so a stray stored value can't wildly over/under-zoom.
    var zoomLevel: Double {
        get {
            let v = defaults.object(forKey: kZoomLevel) as? Double ?? Settings.defaultZoom
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

    /// Breathing-motion strength (renderer `breathStrength`). Clamped to 0…2.
    var breathStrength: Double {
        get {
            let v = defaults.object(forKey: kBreathStrength) as? Double ?? Settings.defaultBreath
            return min(2.0, max(0.0, v))
        }
        set { defaults.set(min(2.0, max(0.0, newValue)), forKey: kBreathStrength) }
    }

    func synchronize() {
        defaults.synchronize()
    }
}
