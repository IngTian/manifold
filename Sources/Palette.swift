//
//  Palette.swift
//  Colors ported faithfully from ingtian.github.io — SkyWash.css (sky descent
//  gradient + theme surfaces) and TerrainHero's terrain.js (elevation ramps and
//  walker colors). Keeping the numbers identical is deliberate: the screensaver
//  should read as the same visual world as the site's hero.
//

import CoreGraphics
import Foundation

/// A single stop in a vertical gradient: `location` in 0…1 from top to bottom.
struct GradientStop {
    let location: CGFloat
    let rgb: (CGFloat, CGFloat, CGFloat)
}

/// RGB triple in 0…1, matching the `[r,g,b]` byte triples used by terrain.js
/// (divided by 255 here so the renderer can work in normalized space).
struct RGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    init(_ r255: CGFloat, _ g255: CGFloat, _ b255: CGFloat) {
        self.r = r255 / 255.0
        self.g = g255 / 255.0
        self.b = b255 / 255.0
    }

    func cgColor(alpha: CGFloat) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: alpha)
    }
}

/// The two elevation ramps from terrain.js (`lt` = light, `At` = dark). Each has
/// valley / mid / peak anchors that Et() interpolates between.
struct ElevationRamp {
    let valley: RGB
    let mid: RGB
    let peak: RGB
}

/// Walker particle colors from terrain.js `It()`.
struct WalkerColors {
    let glow: RGB
    let settled: RGB
    let trail: RGB
}

enum ThemeMode {
    case light
    case dark
}

/// All theme-dependent color choices for one mode.
struct Palette {
    let sky: [GradientStop]        // the full-page "descent" background gradient
    let ramp: ElevationRamp        // terrain dot colors by elevation
    let walker: WalkerColors       // walker glow / settled / trail
    let clockInk: RGB              // clock text color
    let clockShadow: RGB           // subtle contrast shadow behind text

    // MARK: Light

    /// SkyWash light "descent" gradient. On the site this spans the WHOLE page
    /// (`.descent` <main>: hero 108vh + interlude 78vh + more), and the terrain
    /// hero canvas only shows the top band — cream → warm greige → soft blue-gray,
    /// never the dark ground. So we take only the TOP ~44% of the descent
    /// (stops through #7d7e88 @ 44%) and rescale it to fill the screen (÷0.44).
    /// Full descent for reference:
    /// #f4efe4 0%, #f0eadf 8%, #efe6d4 15%, #e2d2c2 23%, #ccc4b6 30%, #a6a8ad 37%,
    /// #7d7e88 44%, #565660 52%, #3a3833 62%, #2a2720 78%, #1d1b16 90%, #16140f 100%.
    static let light = Palette(
        sky: [
            GradientStop(location: 0.000, rgb: hex(0xf4efe4)), // 0%    ÷0.44
            GradientStop(location: 0.182, rgb: hex(0xf0eadf)), // 8%
            GradientStop(location: 0.341, rgb: hex(0xefe6d4)), // 15%
            GradientStop(location: 0.523, rgb: hex(0xe2d2c2)), // 23%
            GradientStop(location: 0.682, rgb: hex(0xccc4b6)), // 30%
            GradientStop(location: 0.841, rgb: hex(0xa6a8ad)), // 37%
            GradientStop(location: 1.000, rgb: hex(0x7d7e88)), // 44%
        ],
        // terrain.js lt: valley[150,110,58] mid[120,112,96] peak[109,118,137]
        ramp: ElevationRamp(valley: RGB(150, 110, 58),
                            mid: RGB(120, 112, 96),
                            peak: RGB(109, 118, 137)),
        // walker light: glow[244,239,228] settled[200,163,106] trail[92,108,140]
        walker: WalkerColors(glow: RGB(244, 239, 228),
                             settled: RGB(200, 163, 106),
                             trail: RGB(92, 108, 140)),
        // Background is now light throughout, so the clock uses the site's dark
        // ink (#16140f), with a soft light halo for legibility over the blue-gray.
        clockInk: RGB(22, 20, 15),
        clockShadow: RGB(244, 239, 228)
    )

    // MARK: Dark

    /// SkyWash dark "descent" gradient:
    /// linear-gradient(180deg, #16191d 0%, #131619 20%, #111417 40%, #0e1013 60%,
    ///   #0b0d0f 80%, #08090b 100%)
    static let dark = Palette(
        sky: [
            GradientStop(location: 0.00, rgb: hex(0x16191d)),
            GradientStop(location: 0.20, rgb: hex(0x131619)),
            GradientStop(location: 0.40, rgb: hex(0x111417)),
            GradientStop(location: 0.60, rgb: hex(0x0e1013)),
            GradientStop(location: 0.80, rgb: hex(0x0b0d0f)),
            GradientStop(location: 1.00, rgb: hex(0x08090b)),
        ],
        // terrain.js At: valley[70,120,92] mid[78,150,150] peak[95,190,170]
        ramp: ElevationRamp(valley: RGB(70, 120, 92),
                            mid: RGB(78, 150, 150),
                            peak: RGB(95, 190, 170)),
        // walker dark: glow[220,225,220] settled[102,194,140] trail[95,178,201]
        walker: WalkerColors(glow: RGB(220, 225, 220),
                             settled: RGB(102, 194, 140),
                             trail: RGB(95, 178, 201)),
        clockInk: RGB(223, 227, 223),
        clockShadow: RGB(8, 9, 11)
    )

    static func forMode(_ mode: ThemeMode) -> Palette {
        mode == .dark ? .dark : .light
    }

    /// #RRGGBB → normalized (r,g,b) triple.
    static func hex(_ v: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        let r = CGFloat((v >> 16) & 0xff) / 255.0
        let g = CGFloat((v >> 8) & 0xff) / 255.0
        let b = CGFloat(v & 0xff) / 255.0
        return (r, g, b)
    }
}
