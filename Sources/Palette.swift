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

    /// Build from a packed 0xRRGGBB literal — the concise form the palette presets use.
    init(hex v: UInt32) {
        self.init(CGFloat((v >> 16) & 0xff), CGFloat((v >> 8) & 0xff), CGFloat(v & 0xff))
    }

    /// Build directly from already-normalized (0…1) components — used for blending.
    init(rNorm: CGFloat, gNorm: CGFloat, bNorm: CGFloat) {
        self.r = rNorm
        self.g = gNorm
        self.b = bNorm
    }

    func cgColor(alpha: CGFloat) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: alpha)
    }

    /// Linear interpolation in normalized RGB space (used for theme cross-fades).
    static func lerp(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
        RGB(rNorm: a.r + (b.r - a.r) * t,
            gNorm: a.g + (b.g - a.g) * t,
            bNorm: a.b + (b.b - a.b) * t)
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

/// Cheap identity so callers can push the same palette every frame without
/// restarting a theme cross-fade. `.custom` marks a blended (mid-fade) palette,
/// which is never a fade *target*.
enum PaletteID {
    case light
    case dark
    case custom
}

/// All theme-dependent color choices for one mode.
struct Palette {
    let id: PaletteID              // light/dark/custom — identity for fade de-duplication
    /// Which `PalettePreset` this came from (its rawValue; 0 = Classic). Part of the
    /// fade-dedup key alongside `id`, so switching *preset* while staying in the same
    /// light/dark mode still triggers a cross-fade instead of being treated as a repeat.
    var presetTag: Int = 0
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
        id: .light,
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
        id: .dark,
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

    // MARK: Blending (theme cross-fade)

    /// Sample the vertical sky gradient at `loc` (0…1), interpolating between stops.
    /// Assumes stops are sorted by `location` (they are, by construction).
    func skyColor(at loc: CGFloat) -> RGB {
        guard let first = sky.first else { return RGB(0, 0, 0) }
        if loc <= first.location { return RGB(rNorm: first.rgb.0, gNorm: first.rgb.1, bNorm: first.rgb.2) }
        if let last = sky.last, loc >= last.location {
            return RGB(rNorm: last.rgb.0, gNorm: last.rgb.1, bNorm: last.rgb.2)
        }
        for i in 1..<sky.count {
            let lo = sky[i - 1], hi = sky[i]
            if loc <= hi.location {
                let span = hi.location - lo.location
                let t = span > 0 ? (loc - lo.location) / span : 0
                let a = RGB(rNorm: lo.rgb.0, gNorm: lo.rgb.1, bNorm: lo.rgb.2)
                let b = RGB(rNorm: hi.rgb.0, gNorm: hi.rgb.1, bNorm: hi.rgb.2)
                return RGB.lerp(a, b, t)
            }
        }
        let l = sky[sky.count - 1]
        return RGB(rNorm: l.rgb.0, gNorm: l.rgb.1, bNorm: l.rgb.2)
    }

    /// A palette that is `t` of the way from `self` to `other` (t in 0…1).
    /// Every color channel is interpolated so a theme switch can cross-fade
    /// smoothly instead of snapping. The sky is resampled onto a shared set of
    /// stop locations (the two themes have different stop counts).
    func blended(to other: Palette, t rawT: CGFloat) -> Palette {
        let t = max(0, min(1, rawT))
        if t <= 0 { return self }
        if t >= 1 { return other }

        // Union of both themes' stop locations → resample both, then lerp.
        var locs = Set<CGFloat>()
        for s in sky { locs.insert(s.location) }
        for s in other.sky { locs.insert(s.location) }
        let sortedLocs = locs.sorted()
        let blendedSky: [GradientStop] = sortedLocs.map { loc in
            let a = self.skyColor(at: loc)
            let b = other.skyColor(at: loc)
            let c = RGB.lerp(a, b, t)
            return GradientStop(location: loc, rgb: (c.r, c.g, c.b))
        }

        return Palette(
            id: .custom,
            sky: blendedSky,
            ramp: ElevationRamp(
                valley: RGB.lerp(ramp.valley, other.ramp.valley, t),
                mid: RGB.lerp(ramp.mid, other.ramp.mid, t),
                peak: RGB.lerp(ramp.peak, other.ramp.peak, t)),
            walker: WalkerColors(
                glow: RGB.lerp(walker.glow, other.walker.glow, t),
                settled: RGB.lerp(walker.settled, other.walker.settled, t),
                trail: RGB.lerp(walker.trail, other.walker.trail, t)),
            clockInk: RGB.lerp(clockInk, other.clockInk, t),
            clockShadow: RGB.lerp(clockShadow, other.clockShadow, t)
        )
    }

    /// #RRGGBB → normalized (r,g,b) triple.
    static func hex(_ v: UInt32) -> (CGFloat, CGFloat, CGFloat) {
        let r = CGFloat((v >> 16) & 0xff) / 255.0
        let g = CGFloat((v >> 8) & 0xff) / 255.0
        let b = CGFloat(v & 0xff) / 255.0
        return (r, g, b)
    }

    // MARK: Preset construction

    /// Build one mode of a preset from compact packed-hex specs. Keeps the preset
    /// table below terse and uniform (sky stops + the three ramp anchors + walker
    /// trio + clock pair), while producing exactly the same `Palette` shape the
    /// renderer already consumes. `tag` is the owning preset's rawValue.
    static func make(id: PaletteID, tag: Int,
                     sky: [(CGFloat, UInt32)],
                     valley: UInt32, mid: UInt32, peak: UInt32,
                     glow: UInt32, settled: UInt32, trail: UInt32,
                     clockInk ink: UInt32, clockShadow shadow: UInt32) -> Palette {
        Palette(
            id: id, presetTag: tag,
            sky: sky.map { GradientStop(location: $0.0, rgb: hex($0.1)) },
            ramp: ElevationRamp(valley: RGB(hex: valley), mid: RGB(hex: mid), peak: RGB(hex: peak)),
            walker: WalkerColors(glow: RGB(hex: glow), settled: RGB(hex: settled), trail: RGB(hex: trail)),
            clockInk: RGB(hex: ink), clockShadow: RGB(hex: shadow))
    }
}

/// A bundled color scheme the user can pick. Each preset owns a light and a dark
/// `Palette`; the theme setting (auto/light/dark) still selects *within* the preset,
/// so a preset is a full re-skin of both modes at once.
///
/// `Classic` is the shipped ingtian.github.io look (its palettes live on
/// `Palette.light`/`.dark`, kept there verbatim with their provenance comments). The
/// others were designed for Manifold and dialed in against the real terrain + EDL in
/// tools/palette-preview.html. Add a case here and it flows automatically into both
/// config UIs (they enumerate `allCases`) and the persisted setting (rawValue).
enum PalettePreset: Int, CaseIterable {
    case classic = 0
    case nordicSlate = 1
    case sumiInk = 2

    /// Menu / popup label.
    var label: String {
        switch self {
        case .classic:     return "Classic"
        case .nordicSlate: return "Nordic Slate"
        case .sumiInk:     return "Sumi-e Ink"
        }
    }

    /// The palette for a given light/dark mode.
    func palette(dark: Bool) -> Palette {
        switch self {
        case .classic:
            return dark ? .dark : .light
        case .nordicSlate:
            return dark ? Self.nordicDark : Self.nordicLight
        case .sumiInk:
            return dark ? Self.sumiDark : Self.sumiLight
        }
    }

    // MARK: Nordic Slate & Fog — cool blue-gray, architectural calm.
    private static let nordicDark = Palette.make(
        id: .dark, tag: PalettePreset.nordicSlate.rawValue,
        sky: [(0, 0x1c242c), (0.25, 0x171e25), (0.5, 0x12181e), (0.75, 0x0d1217), (1, 0x090c10)],
        valley: 0x455a68, mid: 0x6f8b9b, peak: 0xc3d6df,
        glow: 0xe7eff3, settled: 0x90a6b2, trail: 0x5c7482,
        clockInk: 0xd9e2e7, clockShadow: 0x090c10)
    private static let nordicLight = Palette.make(
        id: .light, tag: PalettePreset.nordicSlate.rawValue,
        sky: [(0, 0xeef1f3), (0.28, 0xe2e7ea), (0.55, 0xd1dae0), (0.8, 0xc2ced5), (1, 0xb4c1c9)],
        valley: 0x37444f, mid: 0x516470, peak: 0x647685,   // peak darkened from #728794 for fog headroom
        glow: 0xf5f8f9, settled: 0x5a6e7b, trail: 0x7f909c,
        clockInk: 0x1e2830, clockShadow: 0xeef1f3)

    // MARK: Sumi-e Ink Wash — near-neutral graphite, maximal restraint.
    private static let sumiDark = Palette.make(
        id: .dark, tag: PalettePreset.sumiInk.rawValue,
        sky: [(0, 0x1a1d22), (0.2, 0x16191e), (0.4, 0x111318), (0.6, 0x0c0e12), (0.8, 0x08090c), (1, 0x050506)],
        valley: 0x575d67, mid: 0x858c97, peak: 0xc6ccd5,
        glow: 0xeceff3, settled: 0xaab0bb, trail: 0x686e77,
        clockInk: 0xdadde2, clockShadow: 0x050506)
    private static let sumiLight = Palette.make(
        id: .light, tag: PalettePreset.sumiInk.rawValue,
        sky: [(0, 0xf7f6f2), (0.22, 0xf2f1ee), (0.45, 0xececeb), (0.68, 0xe2e3e6), (0.86, 0xd7d9de), (1, 0xcbced5)],
        valley: 0x7f838c, mid: 0x5d626b, peak: 0x31353d,   // valley darkened from #8b8f96 for ink on paper
        glow: 0xfcfcfb, settled: 0x474c55, trail: 0x9a9fa8,
        clockInk: 0x23262c, clockShadow: 0xf7f6f2)
}
