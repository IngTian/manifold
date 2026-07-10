//
//  TerrainRenderer.swift
//  A faithful Core Graphics port of ingtian.github.io's TerrainHero (terrain.js).
//
//  The scene is a pointillist 3D terrain: a Gaussian-bump elevation field sampled
//  on a grid, projected through a fixed yaw+tilt rotation, and drawn as ~1000 dots
//  colored by elevation. The field "breathes" slowly, and glowing "walker"
//  particles periodically spawn at fixed points and trace gradient-descent paths
//  downhill, settling at the bottom with a soft glow.
//
//  Every constant here (bump params, U/N/V, the it/dt rotation, the 0.34/0.46
//  projection factors, J, dot radius/opacity curves, walker timings) is copied
//  verbatim from the site so the aesthetic matches exactly. Coordinates are
//  produced in a Y-DOWN convention (origin top-left, like an HTML canvas); the
//  caller is responsible for giving us a context in that orientation.
//

import CoreGraphics
import Foundation

// MARK: - Elevation field

/// One Gaussian bump in the elevation field (terrain.js `rt` entries).
private struct Bump {
    let a: Double   // amplitude (signed)
    let cx: Double  // center x
    let cy: Double  // center y
    let s: Double   // spread (sigma)
}

/// The procedural terrain: elevation field + gradient + gradient-descent walker paths.
/// Pure math, no rendering — mirrors tt(), Mt(), wt() from terrain.js.
struct TerrainField {
    // rt from terrain.js
    private let bumps: [Bump] = [
        Bump(a: -1.0,  cx: -1.4, cy: -0.5, s: 0.9),
        Bump(a: -0.65, cx: 1.5,  cy: 0.7,  s: 0.8),
        Bump(a: -0.5,  cx: 0.3,  cy: -1.3, s: 0.7),
        Bump(a: 0.7,   cx: -0.2, cy: 0.9,  s: 1.0),
        Bump(a: 0.45,  cx: 1.0,  cy: -0.6, s: 0.7),
    ]

    let U: Double = 1.7  // elevation scale
    let N: Double = 2.6  // grid half-extent
    let V: Double = 0.16 // grid step

    /// Fixed walker start points (terrain.js `X`).
    let walkerStarts: [(Double, Double)] = [
        (-2, 1.6), (1.8, -1.8), (0.4, 2), (-1.6, -1.9), (2.1, 1.2), (-0.6, -0.4),
    ]

    /// Elevation at (x, y) — terrain.js tt().
    func elevation(_ n: Double, _ e: Double) -> Double {
        var t = 0.0
        for r in bumps {
            let c = n - r.cx
            let i = e - r.cy
            t += r.a * exp(-(c * c + i * i) / (2 * r.s * r.s))
        }
        return t * U
    }

    /// Gradient of the elevation field at (x, y) — terrain.js Mt().
    func gradient(_ n: Double, _ e: Double) -> (Double, Double) {
        var t = 0.0
        var r = 0.0
        for c in bumps {
            let i = n - c.cx
            let d = e - c.cy
            let u = c.a * exp(-(i * i + d * d) / (2 * c.s * c.s))
            t += u * (-i / (c.s * c.s))
            r += u * (-d / (c.s * c.s))
        }
        return (t * U, r * U)
    }

    /// Gradient-descent path from a start point, resampled to 10 points — terrain.js wt().
    func walkerPath(_ n: Double, _ e: Double) -> [CGPoint] {
        var t = n
        var r = e
        var c: [CGPoint] = [CGPoint(x: t, y: r)]
        let i = 0.16 // step size
        for _ in 0..<140 {
            let (gx, gy) = gradient(t, r)
            t -= i * gx
            r -= i * gy
            c.append(CGPoint(x: t, y: r))
            if hypot(gx, gy) < 0.01 { break }
        }
        // Resample the (variable-length) path down to exactly 10 evenly-spaced points.
        let d = 10
        var u: [CGPoint] = []
        let w = Double(c.count - 1) / Double(d - 1)
        for f in 0..<(d - 1) {
            u.append(c[Int((Double(f) * w).rounded())])
        }
        u.append(c[c.count - 1])
        return u
    }
}

// MARK: - Projection

/// Fixed yaw+tilt projection from world (x, y, elevation) to screen — terrain.js at().
/// Returns (screenX, screenY, depth). Depth is used only for painter's-order sorting.
struct Projector {
    // it = PI*0.18 (yaw about Z), dt = 0.92 (tilt about X)
    private let nt = cos(Double.pi * 0.18)
    private let st = sin(Double.pi * 0.18)
    private let ot = cos(0.92)
    private let ct = sin(0.92)

    /// The uniform world→screen scale for a viewport. Every screen position derives
    /// from it — and so does the dot radius (see `render`), which is what keeps the
    /// pointillist texture density constant across resolutions.
    ///
    /// Scale by the smaller dimension (like the site) so the terrain keeps its
    /// proportions — but on very wide screens (ultra-wide/32:9) that leaves big
    /// empty side margins, so grow the scale toward the width. This is a uniform
    /// zoom (never an x/y stretch), so the field never looks distorted; on
    /// <=~16:9 the max() picks min(r,c) and behavior is unchanged.
    func scale(width r: Double, height c: Double) -> Double {
        max(min(r, c), r * 0.46) * 0.34
    }

    func project(_ n: Double, _ e: Double, _ z: Double, width r: Double, height c: Double)
        -> (x: Double, y: Double, depth: Double)
    {
        let i = n * nt - e * st
        let d = n * st + e * nt
        let u = d * ot - z * ct
        let w = d * ct + z * ot
        let f = scale(width: r, height: c)
        return (r * 0.5 + i * f, c * 0.46 - u * f, w)
    }
}

// MARK: - Renderer

/// One grid sample with its (static) base elevation, computed once.
private struct GridPoint {
    let x: Double
    let y: Double
    let baseZ: Double
}

/// A live walker particle.
private final class Walker {
    let pts: [CGPoint]
    let born: Double
    var done = false
    var retire = false
    init(pts: [CGPoint], born: Double) {
        self.pts = pts
        self.born = born
    }
}

/// Renders the terrain scene into a Y-DOWN Core Graphics context.
final class TerrainRenderer {
    private let field = TerrainField()
    private let projector = Projector()
    private let grid: [GridPoint]

    private var palette: Palette
    /// The palette actually used for this frame's draw calls (== `palette` unless a
    /// theme cross-fade is mid-flight). Set once at the top of `render`.
    private var activePalette: Palette
    private var animateWalkers: Bool

    // Theme cross-fade: when the target palette's identity changes, we ease from
    // the palette shown at the switch instant to the new one over `fadeDuration`.
    private var fadeFrom: Palette
    private var fadeStartMs: Double = 0
    private var fadeActive = false
    private let fadeDuration: Double = 650 // ms — a calm dawn/dusk transition
    private var lastNowMs: Double = 0

    // Walker spawn state (terrain.js: m, T, F, j).
    private var walkers: [Walker] = []
    private var spawnIndex = 0             // T
    private var nextSpawnAt: Double = 600  // F
    private let revealInterval: Double = 680 // j

    private let J = 1.55 // elevation normalization half-range for color/size

    // MARK: Dot sizing across resolutions
    //
    // The dot/walker radii below were tuned against the demo render (1600×1000).
    // Dot *positions* scale with the live projection scale, so on bigger viewports
    // the terrain zooms up but fixed-size dots used to stay tiny — the ridge
    // dissolved into sparse specks (worst on ultra-wide, but present on any display
    // whose projection scale exceeds the reference). We grow the radii with the
    // projection scale so the pointillist texture (dot size vs. dot spacing) stays
    // coherent at any resolution — a continuous function of the actual scale, never
    // a per-resolution table. `dotScale` (in `render`) computes it.
    //
    // Threshold, in point space (what the view hands us): dots grow once the scale
    // exceeds referenceScale, i.e. once min(width, height) > ~1000 pt. So a 13"/14"
    // laptop at default scaling (≤1000 pt tall) is pinned to 1.0 and byte-for-byte
    // unchanged, while a 16" MBP (1117 pt), a 1440p external, or a "More Space"
    // scaled mode gets a modest, proportionate enlargement — the same fix, milder.

    /// Resolution the base radii were tuned at. Derived from the projector so it
    /// stays the true `dotScale == 1` pivot if the reference render size changes.
    /// This is `Projector.scale(1600×1000)` == 340. (Note the projector's uniform
    /// 0.34 zoom cancels in `scale/referenceScale`, so dot sizing is invariant to
    /// it; only the min/width-fraction split of `scale()` shapes the ratio.)
    private static let referenceScale = Projector().scale(width: 1600, height: 1000)

    /// Growth exponent for dot radius vs. projection scale. 1.0 holds texture density
    /// exactly constant but reads a touch heavy on very wide screens; 0.70 lets the
    /// terrain breathe a little more per pixel while still restoring the ridge. Only
    /// matters above the reference resolution — at/below it `dotScale` is pinned to 1.
    private static let dotGrowthExponent = 0.70

    init(palette: Palette, animateWalkers: Bool = true) {
        self.palette = palette
        self.activePalette = palette
        self.fadeFrom = palette
        self.animateWalkers = animateWalkers

        // Build the grid once, replicating terrain.js's float accumulation exactly
        // so the point count matches (for(a=-N;a<=N;a+=V)).
        let f = TerrainField()
        var pts: [GridPoint] = []
        var a = -f.N
        while a <= f.N {
            var h = -f.N
            while h <= f.N {
                pts.append(GridPoint(x: a, y: h, baseZ: f.elevation(a, h)))
                h += f.V
            }
            a += f.V
        }
        self.grid = pts
    }

    /// Set the target palette. If its theme identity differs from what's currently
    /// shown, a smooth cross-fade begins (animated over `fadeDuration`). Pushing the
    /// same identity every frame is a no-op, so callers can call this each frame.
    func setPalette(_ p: Palette) {
        // Ignore repeats of the identity we're already showing/targeting.
        if p.id == palette.id { return }
        // Begin (or redirect) a fade from whatever is on screen right now.
        fadeFrom = effectivePalette(atMs: lastNowMs)
        fadeStartMs = lastNowMs
        fadeActive = true
        palette = p
    }

    /// Set the palette immediately with no cross-fade (e.g. first appearance).
    func setPaletteImmediately(_ p: Palette) {
        palette = p
        fadeFrom = p
        activePalette = p   // keep currentClockInk/Shadow correct before first render
        fadeActive = false
    }

    func setAnimateWalkers(_ on: Bool) { self.animateWalkers = on }

    /// The clock ink/shadow to use *this frame*, matching the terrain's current
    /// cross-fade state so overlaid text fades in lockstep with the scene. Valid
    /// after a `render` call (or reflects the target palette before the first one).
    var currentClockInk: RGB { activePalette.clockInk }
    var currentClockShadow: RGB { activePalette.clockShadow }

    /// Smootherstep ease (0→1) for a calm, symmetric transition.
    private func ease(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    /// The palette to actually draw with at `nowMs`, accounting for an in-flight
    /// cross-fade. When no fade is active this is just the current palette.
    private func effectivePalette(atMs nowMs: Double) -> Palette {
        guard fadeActive else { return palette }
        let raw = (nowMs - fadeStartMs) / fadeDuration
        if raw >= 1 { return palette }
        if raw <= 0 { return fadeFrom }
        return fadeFrom.blended(to: palette, t: CGFloat(ease(raw)))
    }

    /// Draw one frame. `size` is the drawing area (point space, Y-down). `nowMs` is
    /// elapsed time in milliseconds. `animate` enables breathing + walkers.
    func render(in ctx: CGContext, size: CGSize, nowMs: Double, animate: Bool) {
        let width = Double(size.width)
        let height = Double(size.height)
        guard width > 1, height > 1 else { return }

        // Resolve the theme cross-fade for this frame. `lastNowMs` lets setPalette()
        // (which has no clock of its own) start a fade from the right instant.
        lastNowMs = nowMs
        activePalette = effectivePalette(atMs: nowMs)
        if fadeActive && (nowMs - fadeStartMs) >= fadeDuration {
            fadeActive = false
            fadeFrom = palette
        }

        drawSky(in: ctx, size: size)

        let x = nowMs / 1000.0
        let breathAmp = animate ? 0.04 : 0.0   // y in terrain.js
        let breathFreq = 0.4                    // I

        // Grow the dot radius with the projection scale so the pointillist texture
        // holds together as the viewport gets bigger. Sublinear (exponent < 1) so
        // dots enlarge gently; clamped to ≥1 so any viewport at/below the reference
        // scale (ratio ≤ 1 → pinned to exactly 1) is byte-for-byte unchanged.
        let scaleRatio = projector.scale(width: width, height: height) / Self.referenceScale
        let dotScale = max(1.0, pow(scaleRatio, Self.dotGrowthExponent))

        // Project every grid point (with breathing), collect for depth sorting.
        struct Dot { let sx: Double; let sy: Double; let depth: Double; let z: Double }
        var dots: [Dot] = []
        dots.reserveCapacity(grid.count)
        for g in grid {
            var z = g.baseZ
            z += breathAmp * sin(x * breathFreq + g.x * 0.7 + g.y * 0.6)
            let p = projector.project(g.x, g.y, z, width: width, height: height)
            dots.append(Dot(sx: p.x, sy: p.y, depth: p.depth, z: z))
        }
        // Painter's order: far (small depth) first.
        dots.sort { $0.depth < $1.depth }

        let bottomFade = height * 0.84 // O
        for dot in dots {
            if dot.sx < -20 || dot.sx > width + 20 || dot.sy < -20 || dot.sy > height + 20 {
                continue
            }
            let l = max(0.0, min(1.0, (dot.z + J) / (2 * J)))
            let radius = (2.9 - l * 1.6) * dotScale
            var opacity = 0.3 + (1 - l) * 0.45
            if dot.sy > bottomFade {
                opacity *= max(0.0, 1 - (dot.sy - bottomFade) / (height - bottomFade))
            }
            if opacity <= 0.004 { continue }

            let color = elevationColor(l)
            ctx.setFillColor(color.cgColor(alpha: CGFloat(opacity)))
            fillCircle(ctx, cx: dot.sx, cy: dot.sy, r: max(0.5, radius))
        }

        if animate && animateWalkers {
            drawWalkers(in: ctx, width: width, height: height, nowMs: nowMs,
                        x: x, breathAmp: breathAmp, breathFreq: breathFreq, dotScale: dotScale)
        }
    }

    // MARK: Sky background

    private func drawSky(in ctx: CGContext, size: CGSize) {
        let space = CGColorSpaceCreateDeviceRGB()
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        for stop in activePalette.sky {
            colors.append(CGColor(colorSpace: space,
                                  components: [stop.rgb.0, stop.rgb.1, stop.rgb.2, 1.0])!)
            locations.append(stop.location)
        }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                        locations: locations) else { return }
        // Y-down: stop 0 (top of gradient) is at y=0 (top of view).
        ctx.saveGState()
        ctx.addRect(CGRect(origin: .zero, size: size))
        ctx.clip()
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: 0),
                               end: CGPoint(x: 0, y: size.height),
                               options: [])
        ctx.restoreGState()
    }

    // MARK: Walkers

    private func maybeSpawn(_ nowMs: Double) {
        if nowMs < nextSpawnAt { return }
        if let last = walkers.last, !last.done {
            nextSpawnAt = nowMs + 400
            return
        }
        let (sx, sy) = field.walkerStarts[spawnIndex % field.walkerStarts.count]
        spawnIndex += 1
        walkers.append(Walker(pts: field.walkerPath(sx, sy), born: nowMs))
        nextSpawnAt = nowMs + 4200 + Double(spawnIndex % 3) * 900
    }

    private func drawWalkers(in ctx: CGContext, width: Double, height: Double,
                             nowMs: Double, x: Double, breathAmp: Double, breathFreq: Double,
                             dotScale: Double) {
        maybeSpawn(nowMs)

        let fadeIn = 160.0    // s
        let trailLife = 4600.0 // l
        let settleHold = 1600.0 // $

        let glow = activePalette.walker.glow
        let settled = activePalette.walker.settled
        let trail = activePalette.walker.trail

        for w in walkers {
            let age = nowMs - w.born
            let revealed = min(w.pts.count, Int(floor(age / revealInterval)) + 1)
            if revealed >= w.pts.count && !w.done { w.done = true }

            var maxAlpha = 0.0
            for s in 0..<revealed {
                let b = w.pts[s]
                let z = field.elevation(Double(b.x), Double(b.y))
                    + breathAmp * sin(x * breathFreq + Double(b.x) * 0.7 + Double(b.y) * 0.6)
                let p = projector.project(Double(b.x), Double(b.y), z + 0.06,
                                          width: width, height: height)

                let isEnd = (s == w.pts.count - 1)
                let q = nowMs - (w.born + Double(s) * revealInterval)
                let fadeInF = min(1.0, q / fadeIn)
                let lifeF: Double
                if isEnd && w.done {
                    lifeF = max(0.0, 1 - max(0.0, q - settleHold) / 700)
                } else {
                    lifeF = max(0.0, 1 - q / trailLife)
                }
                let m = fadeInF * lifeF
                if m <= 0.01 { continue }
                maxAlpha = max(maxAlpha, m)

                let core = (isEnd ? 5.2 : 3.8) * dotScale
                // Glow halo.
                ctx.setFillColor(glow.cgColor(alpha: CGFloat(0.5 * m)))
                fillCircle(ctx, cx: p.x, cy: p.y, r: core * 1.9)
                // Core dot.
                if isEnd && w.done {
                    ctx.setFillColor(settled.cgColor(alpha: CGFloat(0.95 * m)))
                } else {
                    ctx.setFillColor(trail.cgColor(alpha: CGFloat(m)))
                }
                fillCircle(ctx, cx: p.x, cy: p.y, r: core)
            }
            if w.done && maxAlpha <= 0.01 { w.retire = true }
        }
        walkers.removeAll { $0.retire }
    }

    // MARK: Color

    /// Elevation → color via the two-segment ramp — terrain.js Et().
    /// Linear interpolation is scale-invariant, so it's fine to lerp in normalized
    /// RGB space (RGB.lerp) — same result as the site's 0…255 mix, one helper.
    private func elevationColor(_ n: Double) -> RGB {
        let r = activePalette.ramp
        if n < 0.5 {
            return RGB.lerp(r.valley, r.mid, CGFloat(n / 0.5))
        } else {
            return RGB.lerp(r.mid, r.peak, CGFloat((n - 0.5) / 0.5))
        }
    }

    private func fillCircle(_ ctx: CGContext, cx: Double, cy: Double, r: Double) {
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }
}
