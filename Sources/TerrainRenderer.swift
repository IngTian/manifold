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

/// One Gaussian bump in the classic elevation field (terrain.js `rt` entries).
private struct Bump {
    let a: Double   // amplitude (signed)
    let cx: Double  // center x
    let cy: Double  // center y
    let s: Double   // spread (sigma)
}

/// A named height field `z = h(x, y)` with a *closed-form* gradient. `.classic`
/// is the shipped ingtian.github.io five-Gaussian field (returned verbatim). The
/// rest are elegant analytic surfaces — classic optimization test functions,
/// radial wavelets, and wave fields — picked to read cleanly as a sparse dotted
/// 3-D shape at the fixed camera.
///
/// Each non-classic case declares a NATIVE function `g` and its exact gradient
/// over some native domain; `domainScale` maps the fixed sampling square `[-N,N]`
/// into that domain, and `TerrainField` affine-fits `g`'s range onto the same
/// elevation band the classic field occupies — so the fixed camera, color ramp,
/// Eye-Dome Lighting and breathing all stay tuned for every surface without
/// per-surface retuning. The affine fit is monotonic, so the closed-form gradient
/// carries through by the chain rule and the "walkers" keep tracing real
/// gradient descent down whichever surface is showing.
///
/// Add a case here and it flows automatically into both config UIs (they
/// enumerate `allCases`) and the persisted setting (rawValue) — exactly like
/// `PalettePreset`.
enum TerrainFunction: Int, CaseIterable {
    case classic = 0
    case ackley = 1
    case himmelblau = 2
    case rosenbrock = 3
    case rastrigin = 4
    case rosette = 5
    case ripples = 6
    case hexWaves = 7

    /// Menu / popup label.
    var label: String {
        switch self {
        case .classic:     return "Classic (Gaussian bumps)"
        case .ackley:      return "Ackley (funnel)"
        case .himmelblau:  return "Himmelblau (four minima)"
        case .rosenbrock:  return "Rosenbrock (banana valley)"
        case .rastrigin:   return "Rastrigin (dimpled dome)"
        case .rosette:     return "Monkey-Saddle Rosette"
        case .ripples:     return "Still Water (ripples)"
        case .hexWaves:    return "Hex Interference"
        }
    }

    /// The classic field is returned verbatim (no fit) so it stays byte-for-byte
    /// identical to the shipped look.
    var isClassic: Bool { self == .classic }

    /// Map from the fixed world sampling square `[-N, N]` to this surface's native
    /// domain: `native = domainScale * world`. 1 for classic (world == native).
    /// Chosen so 33×33 samples land across the surface's interesting region without
    /// aliasing (every feature stays well above the ~4-grid-step alias floor).
    fileprivate var domainScale: Double {
        switch self {
        case .classic:    return 1
        case .ackley:     return 4.0 / TerrainField.halfExtent  // native ±4 — one central funnel
        case .himmelblau: return 5.0 / TerrainField.halfExtent  // native ±5 — all four minima inside
        case .rosenbrock: return 2.0 / TerrainField.halfExtent  // native ±2 — the curved valley
        case .rastrigin:  return 2.5 / TerrainField.halfExtent  // native ±2.5 — period-2 dimple lattice
        case .rosette:    return 4.0 / TerrainField.halfExtent  // native ±4 — Gaussian window confines it
        case .ripples:    return 6.0 / TerrainField.halfExtent  // native ±6 — ~2 rings survive the envelope
        case .hexWaves:   return 2.6 / TerrainField.halfExtent  // native ±2.6 — λ≈2.86, ~18 samples/wave
        }
    }

    /// `rt` from terrain.js — the classic field's five signed Gaussians.
    private static let classicBumps: [Bump] = [
        Bump(a: -1.0,  cx: -1.4, cy: -0.5, s: 0.9),
        Bump(a: -0.65, cx: 1.5,  cy: 0.7,  s: 0.8),
        Bump(a: -0.5,  cx: 0.3,  cy: -1.3, s: 0.7),
        Bump(a: 0.7,   cx: -0.2, cy: 0.9,  s: 1.0),
        Bump(a: 0.45,  cx: 1.0,  cy: -0.6, s: 0.7),
    ]

    // Tuning constants for the analytic surfaces. Frequencies (k*) are deliberately
    // gentled below each function's textbook value so features span many grid steps
    // and never alias into "static" on the sparse 33-sample lattice. The two "log"
    // fields (Himmelblau, Rosenbrock) are log(1+…)-compressed: their raw walls are
    // ~1000× the basin depth and would clip the whole field to one spike, and since
    // log1p is monotonic the minima — and thus the walker descent paths — are
    // unchanged (the gradient just carries a positive 1/(1+…) factor).
    private static let ackleyB   = 0.5             // Ackley funnel steepness
    private static let ackleyK   = Double.pi / 2   // Ackley cosine freq (gentled from 2π)
    private static let rosenB    = 2.0             // Rosenbrock valley curvature (gentled from 100)
    private static let rastA     = 0.12            // Rastrigin bowl weight
    private static let rastB     = 0.7             // Rastrigin dimple depth (k = π)
    private static let rosetteS2 = 2.25            // Rosette Gaussian window, σ² (σ = 1.5)
    private static let rippleS2  = 6.25            // Ripple Gaussian window, σ² (σ = 2.5)
    private static let rippleK   = 1.5             // Ripple radial freq
    private static let hexK      = 2.2             // Hex wave number
    private static let hexA      = 0.75            // Hex amplitude

    /// Native height `g(x, y)` (before the domain map / z-fit). For classic this
    /// is the full terrain.js `tt()` (including the U = 1.7 scale).
    fileprivate func rawElevation(_ x: Double, _ y: Double) -> Double {
        switch self {
        case .classic:
            var t = 0.0
            for r in Self.classicBumps {
                let dx = x - r.cx, dy = y - r.cy
                t += r.a * exp(-(dx * dx + dy * dy) / (2 * r.s * r.s))
            }
            return t * 1.7                                       // U

        case .ackley:
            // The canonical global-optimization funnel: a near-flat rippled plateau
            // plunging to one central well. Radially ringed — glorious under EDL.
            let b = Self.ackleyB, k = Self.ackleyK
            let R = (0.5 * (x * x + y * y)).squareRoot()
            return -20 * exp(-b * R) - exp(0.5 * (cos(k * x) + cos(k * y))) + 20 + M_E

        case .himmelblau:
            // Four equal minima separated by ridges — the textbook multi-basin map.
            let a = x * x + y - 11, b = x + y * y - 7
            return log1p(a * a + b * b)                          // log-compressed (monotone)

        case .rosenbrock:
            // The ill-conditioned "banana" — one crescent ravine curving to a basin.
            let b = Self.rosenB, t = y - x * x
            return log1p((1 - x) * (1 - x) + b * t * t)          // log-compressed (monotone)

        case .rastrigin:
            // A serene paraboloid quilted with a regular lattice of soft dimples —
            // ordered structure, not noise. Local-vs-global basins for the walkers.
            let a = Self.rastA, b = Self.rastB, p = Double.pi
            return a * (x * x + y * y) - b * (cos(p * x) + cos(p * y))

        case .rosette:
            // A monkey saddle windowed by a Gaussian: a 120°-symmetric 3-petal
            // pinwheel (three hills, three valleys) fading to a flat plain.
            let m = x * x * x - 3 * x * y * y
            return m * exp(-(x * x + y * y) / (2 * Self.rosetteS2))

        case .ripples:
            // A 山水 "raindrop crown": a bright center ringed by Gaussian-damped
            // swells fading into stillness. The calmest pure-radial gesture.
            let r = (x * x + y * y).squareRoot()
            return exp(-(x * x + y * y) / (2 * Self.rippleS2)) * cos(Self.rippleK * r)

        case .hexWaves:
            // Three plane waves at 120° → a crystalline six-fold honeycomb of
            // rounded swells and shallow hex basins. Perfectly regular, zero jitter.
            let k = Self.hexK, s3 = 3.0.squareRoot() / 2
            let t2 = k * (-x / 2 + s3 * y), t3 = k * (-x / 2 - s3 * y)
            return Self.hexA * (cos(k * x) + cos(t2) + cos(t3))
        }
    }

    /// Exact closed-form gradient `(∂g/∂x, ∂g/∂y)` in native coords. Every entry
    /// is verified against finite differences (max error ~1e-9) — the walkers,
    /// surface normals and Eye-Dome Lighting all depend on it being exact.
    fileprivate func rawGradient(_ x: Double, _ y: Double) -> (Double, Double) {
        switch self {
        case .classic:
            var gx = 0.0, gy = 0.0
            for r in Self.classicBumps {
                let dx = x - r.cx, dy = y - r.cy
                let e = r.a * exp(-(dx * dx + dy * dy) / (2 * r.s * r.s))
                gx += e * (-dx / (r.s * r.s))
                gy += e * (-dy / (r.s * r.s))
            }
            return (gx * 1.7, gy * 1.7)

        case .ackley:
            let b = Self.ackleyB, k = Self.ackleyK
            let R = (0.5 * (x * x + y * y)).squareRoot()
            let e2 = exp(0.5 * (cos(k * x) + cos(k * y)))
            // First term's factor 20·b·e^(−bR)·(x)/(2R); guard R at the origin (the
            // lattice never lands on 0,0, but keep walkers/EDL safe from the cusp).
            let Rg = max(R, 1e-12)
            let f = 20 * b * exp(-b * R) / (2 * Rg)
            return (f * x + e2 * 0.5 * k * sin(k * x),
                    f * y + e2 * 0.5 * k * sin(k * y))

        case .himmelblau:
            let a = x * x + y - 11, b = x + y * y - 7
            let H = a * a + b * b
            // g = log(1+H) ⇒ ∇g = ∇H / (1+H).
            return ((4 * x * a + 2 * b) / (1 + H), (2 * a + 4 * y * b) / (1 + H))

        case .rosenbrock:
            let b = Self.rosenB, t = y - x * x
            let R = (1 - x) * (1 - x) + b * t * t
            let Rx = -2 * (1 - x) - 4 * b * x * t, Ry = 2 * b * t
            return (Rx / (1 + R), Ry / (1 + R))

        case .rastrigin:
            let a = Self.rastA, b = Self.rastB, p = Double.pi
            return (2 * a * x + b * p * sin(p * x), 2 * a * y + b * p * sin(p * y))

        case .rosette:
            let s2 = Self.rosetteS2
            let e = exp(-(x * x + y * y) / (2 * s2)), m = x * x * x - 3 * x * y * y
            // ∇[m·e] = e·(∇m − (r/σ²)·m). ∇m = (3(x²−y²), −6xy).
            return (e * (3 * (x * x - y * y) - (x / s2) * m),
                    e * (-6 * x * y - (y / s2) * m))

        case .ripples:
            let s2 = Self.rippleS2, k = Self.rippleK
            let r = (x * x + y * y).squareRoot()
            if r < 1e-7 { return (0, 0) }                        // ∇=0 at the crown
            let e = exp(-(x * x + y * y) / (2 * s2))
            // d/dr[e·cos(kr)] = −e·(cos(kr)/σ² · r + k·sin(kr)); ∂r/∂x = x/r cancels the r.
            let common = -e * (cos(k * r) / s2 + k * sin(k * r) / r)
            return (x * common, y * common)

        case .hexWaves:
            let k = Self.hexK, A = Self.hexA, s3 = 3.0.squareRoot() / 2
            let t2 = k * (-x / 2 + s3 * y), t3 = k * (-x / 2 - s3 * y)
            return (-A * k * (sin(k * x) - 0.5 * sin(t2) - 0.5 * sin(t3)),
                    -A * k * (s3 * sin(t2) - s3 * sin(t3)))
        }
    }
}

/// The procedural terrain for a chosen `TerrainFunction`: elevation field +
/// gradient + gradient-descent walker paths. Pure math, no rendering — the
/// classic case mirrors tt(), Mt(), wt() from terrain.js verbatim.
struct TerrainField {
    static let halfExtent = 2.6   // N: grid half-extent
    static let step = 0.16        // V: grid step

    /// The active height field.
    let function: TerrainFunction

    let N = TerrainField.halfExtent
    let V = TerrainField.step

    /// Fixed walker start points (terrain.js `X`).
    let walkerStarts: [(Double, Double)] = [
        (-2, 1.6), (1.8, -1.8), (0.4, 2), (-1.6, -1.9), (2.1, 1.2), (-0.6, -0.4),
    ]

    // Affine z-fit onto the classic field's elevation band, so every surface
    // shares the tuned camera / color ramp / EDL / breathing:
    //   worldZ = zScale · (raw − gMid) + zMid,  sampled at  native = domainScale · world.
    // Identity for classic (zScale = 1, gMid = zMid), so classic is unchanged.
    private let domainScale: Double
    private let gMid: Double
    private let zScale: Double
    private let zMid: Double
    private let identity: Bool

    /// The classic field's [min, max] over the lattice — the band every other
    /// surface is fitted onto. Computed once (the fit derives from the classic
    /// field itself, so there are no free-floating magic target numbers).
    private static let classicBand = sampleRange(.classic)

    init(function: TerrainFunction = .classic) {
        self.function = function
        self.identity = function.isClassic
        self.domainScale = function.domainScale
        let (loC, hiC) = TerrainField.classicBand
        self.zMid = (loC + hiC) / 2
        if function.isClassic {
            self.gMid = (loC + hiC) / 2
            self.zScale = 1
        } else {
            let (lo, hi) = TerrainField.sampleRange(function)
            self.gMid = (lo + hi) / 2
            self.zScale = hi > lo ? (hiC - loC) / (hi - lo) : 1
        }
    }

    /// Elevation at world (x, y) — the classic field's `tt()` for `.classic`
    /// (verbatim), or a fitted analytic surface otherwise.
    func elevation(_ n: Double, _ e: Double) -> Double {
        if identity { return function.rawElevation(n, e) }
        return zScale * (function.rawElevation(n * domainScale, e * domainScale) - gMid) + zMid
    }

    /// Gradient of the (fitted) elevation field at world (x, y). The chain rule
    /// keeps it exactly closed-form: ∂/∂x of zScale·g(domainScale·x) is
    /// zScale·domainScale·gₓ, so walkers descend the true surface.
    func gradient(_ n: Double, _ e: Double) -> (Double, Double) {
        if identity { return function.rawGradient(n, e) }
        let (gx, gy) = function.rawGradient(n * domainScale, e * domainScale)
        let f = zScale * domainScale
        return (f * gx, f * gy)
    }

    /// Sample a function's elevation range over the lattice (the exact points the
    /// grid draws) so the affine fit lands the rendered dots on the classic band.
    private static func sampleRange(_ fn: TerrainFunction) -> (Double, Double) {
        var lo = Double.infinity, hi = -Double.infinity
        var a = -halfExtent
        while a <= halfExtent {
            var b = -halfExtent
            while b <= halfExtent {
                let v = fn.rawElevation(a * fn.domainScale, b * fn.domainScale)
                if v < lo { lo = v }
                if v > hi { hi = v }
                b += step
            }
            a += step
        }
        return (lo, hi)
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
    ///
    /// `zoomOut` pulls the camera back a touch so more of the terrain's footprint is
    /// visible (its corners otherwise clip off the sides). Uniform, so it never
    /// distorts; it flows into project() AND the renderer's dotScale/EDL-radius, which
    /// all derive from this, keeping the pointillist texture consistent. Settable so
    /// the user can tune how much terrain is shown (default 0.85).
    var zoomOut = 0.85
    func scale(width r: Double, height c: Double) -> Double {
        max(min(r, c), r * 0.46) * 0.34 * zoomOut
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

    /// Resolution-independent projected coords (pre scale+offset): screen X-axis,
    /// screen Y-axis (u; larger = higher on screen), and depth (larger = nearer).
    /// project() is just a uniform scale+translate of (i, u), so screen-space NEIGHBOR
    /// relationships are identical at every resolution — which lets Eye-Dome Lighting
    /// be precomputed once here and reused at any viewport size.
    func raw(_ n: Double, _ e: Double, _ z: Double) -> (ix: Double, uy: Double, depth: Double) {
        let i = n * nt - e * st
        let d = n * st + e * nt
        let u = d * ot - z * ct
        let w = d * ct + z * ot
        return (i, u, w)
    }
}

// MARK: - Renderer

/// One grid sample with its (static) base elevation and surface normal, computed once.
private struct GridPoint {
    let x: Double
    let y: Double
    let baseZ: Double
    let nx: Double  // unit surface normal in world (x, y, elevation) space, z-up
    let ny: Double
    let nz: Double
    var edl: Double // Eye-Dome-Lighting shade in [0,1] (1 = unshaded), precomputed
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
    private var field: TerrainField
    private var projector = Projector()
    private var grid: [GridPoint]

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

    // MARK: Directional lighting (a fixed overhead sun that shades the dots for shape)
    //
    // A single distant light shades the terrain so its 3D form reads clearly. Each
    // dot's precomputed normal is dotted with the light (N·L, half-Lambert) to shade
    // its color, and with the view vector (N·V) to fade out the hidden far slope of
    // each ridge (backface culling) so the terrain reads as one solid surface instead
    // of a see-through point cloud. When `lightingEnabled` is false the whole path is
    // skipped and output is byte-for-byte identical to the unlit renderer.
    //
    // The light is FIXED high overhead (not orbiting): the terrain mostly faces up,
    // so an overhead sun lights the visible surface everywhere while the elevation
    // gradient still yields gentle relief. (An earlier orbiting "sun/moon" swung
    // behind the mountain for half its cycle and dropped the camera-facing side into
    // shadow — wrong for shape reading. Motion can return later as a *high* arc that
    // never dips low; for now a fixed sun keeps the form stable and unambiguous.)

    /// Master switch. Off ⇒ no shading, no backface fade (unchanged look).
    var lightingEnabled = false

    /// Camera pull-back. Forwarded to the projector; larger shows more terrain.
    /// EDL is precomputed in the projector's pre-scale `raw()` space (which `zoomOut`
    /// doesn't touch), so changing this never invalidates the baked EDL shade — a
    /// uniform zoom that leaves the pointillist texture and shape cue intact.
    var zoomOut: Double {
        get { projector.zoomOut }
        set { projector.zoomOut = newValue }
    }

    /// Breathing-motion strength: a multiplier on the field's breathing amplitude.
    /// 1.0 = the tuned default (the shipped 0.04 amplitude); 0 = perfectly still;
    /// >1 = livelier. Scales the vertical wobble of both the terrain dots and the
    /// walkers together, so the whole scene breathes in proportion. Doesn't touch
    /// EDL (precomputed on the *base* elevation, independent of the wobble).
    var breathStrength: Double = 1.0

    // Fixed light direction (unit, world x=n,y=e,z=up). Mostly overhead, tipped
    // slightly toward the viewer/left so the relief has a consistent, readable
    // gradient rather than being perfectly flat.
    private static let lightDir: (Double, Double, Double) = {
        let az = -0.565, alt = 1.30   // ~74° altitude (high), yaw aligned to camera
        let ca = cos(alt)
        let v = (cos(az) * ca, sin(az) * ca, sin(alt))
        let n = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return (v.0 / n, v.1 / n, v.2 / n)
    }()
    private static let lightAmbient    = 0.50     // shadow-side brightness floor (no dot to black)
    private static let lightWarm       = 0.30     // warm-lit / cool-shadow temperature swing
    // Brightness has two parts so shape reads on both pale and dark backgrounds:
    // `value` darkens the shadow side (reads against a light sky), `gain` brightens
    // the lit side (reads against a dark sky). We blend between them by the palette's
    // darkness so it adapts continuously across the theme cross-fade.
    private static let lightValueLight = 0.62     // shadow-darkening weight in light theme
    private static let lightGainDark   = 0.95     // lit-brightening weight in dark theme

    // MARK: Eye-Dome Lighting (the shape cue that actually works on a sparse cloud)
    //
    // Per-dot Lambert / N·V shading only weakly convey shape here because the ridge
    // sits at middle depth AND middle facing. Eye-Dome Lighting sidesteps that: it
    // darkens a dot when its SCREEN neighbors are NEARER than it — i.e. it detects
    // depth discontinuities and manufactures the silhouette / ridge-seam edges the
    // sparse point cloud can't otherwise produce. It's orientation-independent, so it
    // works exactly where the facing-based cues failed. (This is what Potree /
    // CloudCompare use to make un-meshed point clouds read as 3D.)
    //
    // Because the camera is fixed and the terrain static, the whole EDL shade is
    // PRECOMPUTED once per grid point (in resolution-independent raw-projected space)
    // and stored on GridPoint.edl — zero per-frame cost. Coupled to dot area (∝r²) so
    // the cue amplifies super-linearly rather than reading as a subtle value change.
    // Values below dialed in interactively in tools/terrain-explorer.html against the
    // real terrain (breathing on, dots-only): they make the ridge read clearly while
    // the valley recedes, staying calm & pointillist.
    private static let edlNeighborRadius = 0.53    // neighbor gather radius in raw-projected units (≈100px in the explorer)
    private static let edlStrength       = 2.0     // response→shade falloff (higher = harder edges)
    private static let edlFloor          = 0.20    // darkest an EDL-shadowed dot's opacity goes
    private static let edlSizeRange      = 0.75    // dot area spread: lit dots grow, shadowed shrink
    // Elevation emphasis: a small extra boost to the high ground (the mountain IS the
    // high dots), diminishing the valley. Complements EDL; kept gentle.
    private static let elevEmphasis      = 0.20    // 0 = off; valley dots fade toward (1-this) opacity

    /// A 0…1 "darkness" for the active palette (0 = light theme, 1 = dark), from the
    /// top sky color's luminance. Drives the light/dark blend of the shading so it
    /// adapts smoothly as the theme cross-fades (no hard switch).
    private var paletteDarkness: Double {
        let top = activePalette.skyColor(at: 0)
        let lum = 0.2126 * Double(top.r) + 0.7152 * Double(top.g) + 0.0722 * Double(top.b)
        return max(0.0, min(1.0, 1.0 - lum))
    }

    /// Shade a base (elevation- and theme-resolved) color by the light. `ndl` = N·L
    /// in [-1,1]. Half-Lambert → shade ∈ [ambient,1] (soft terminator, nothing to
    /// black). Shade drives brightness (theme-adaptive: darken shadows in light
    /// theme, brighten highlights in dark theme) and a warm-lit/cool-shadow tint.
    private func litColor(_ base: RGB, ndl: Double) -> RGB {
        let h = 0.5 + 0.5 * ndl                                   // half-Lambert, [0,1]
        let shade = Self.lightAmbient + (1 - Self.lightAmbient) * h
        let dark = paletteDarkness
        let value = 1 - (Self.lightValueLight * (1 - dark)) * (1 - shade) // ≤1: darken shadows
        let gain = 1 + (Self.lightGainDark * dark) * h                    // ≥1: brighten lit
        let t = Self.lightWarm * (h - 0.5) * 2                            // [-warm,+warm]
        let r = max(0.0, min(1.0, base.r * value * gain * (1 + t)))
        let g = max(0.0, min(1.0, base.g * value * gain))
        let b = max(0.0, min(1.0, base.b * value * gain * (1 - t)))
        return RGB(rNorm: r, gNorm: g, bNorm: b)
    }

    init(palette: Palette, animateWalkers: Bool = true, function: TerrainFunction = .classic) {
        self.palette = palette
        self.activePalette = palette
        self.fadeFrom = palette
        self.animateWalkers = animateWalkers
        self.field = TerrainField(function: function)
        self.grid = Self.buildGrid(field: field, projector: projector)
    }

    /// Build the (static) grid for a field: sample elevation + surface normal at
    /// every lattice point, then precompute the Eye-Dome-Lighting shade. Replicates
    /// terrain.js's float accumulation exactly so the point count matches
    /// (for(a=-N;a<=N;a+=V) → 33×33 = 1089). Called at init and whenever the terrain
    /// function changes.
    private static func buildGrid(field f: TerrainField, projector: Projector) -> [GridPoint] {
        var pts: [GridPoint] = []
        var a = -f.N
        while a <= f.N {
            var h = -f.N
            while h <= f.N {
                // Surface normal of z = elevation(x,y): N = normalize(-fx, -fy, 1).
                // Precomputed here (like baseZ) so per-frame shading is just a dot product.
                let (gx, gy) = f.gradient(a, h)
                let inv = 1.0 / (gx * gx + gy * gy + 1.0).squareRoot()
                pts.append(GridPoint(x: a, y: h, baseZ: f.elevation(a, h),
                                     nx: -gx * inv, ny: -gy * inv, nz: inv, edl: 1))
                h += f.V
            }
            a += f.V
        }
        computeEDL(&pts, projector: projector)
        return pts
    }

    /// Swap the terrain to a different height field. Rebuilds the grid + EDL (the
    /// camera is fixed, so this is a one-shot recompute, ~1.2M ops) and clears any
    /// in-flight walkers, whose gradient-descent paths belonged to the old surface.
    /// A no-op if the function is unchanged, so callers can push it every frame.
    func setTerrainFunction(_ fn: TerrainFunction) {
        guard fn != field.function else { return }
        field = TerrainField(function: fn)
        grid = Self.buildGrid(field: field, projector: projector)
        walkers.removeAll()
    }

    /// The active terrain function.
    var terrainFunction: TerrainFunction { field.function }

    /// Precompute the Eye-Dome-Lighting shade for every grid point (once; the camera
    /// is fixed and the terrain static). For each dot, gather its screen-space
    /// neighbors and measure how much NEARER they are; a dot that sits behind nearer
    /// terrain gets a large response → darker shade. Works in raw-projected space so
    /// the result is resolution-independent. O(n²) over ~1089 pts ≈ 1.2M ops, one time.
    private static func computeEDL(_ pts: inout [GridPoint], projector: Projector) {
        let n = pts.count
        var ix = [Double](repeating: 0, count: n)
        var uy = [Double](repeating: 0, count: n)
        var dp = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let r = projector.raw(pts[i].x, pts[i].y, pts[i].baseZ)
            ix[i] = r.ix; uy[i] = r.uy; dp[i] = r.depth
        }
        let r2 = edlNeighborRadius * edlNeighborRadius
        var response = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum = 0.0, cnt = 0.0
            for j in 0..<n where j != i {
                let dx = ix[j] - ix[i], dy = uy[j] - uy[i]
                if dx * dx + dy * dy > r2 { continue }
                cnt += 1
                // depth larger = NEARER. A dot RECEDES (→ darken) when its neighbors
                // are FARTHER, i.e. dp[j] < dp[i] → (dp[i] - dp[j]) > 0. This keeps
                // near/high ridge dots bright and dims the receding valley — the
                // opposite sign wrongly shrinks the hilltops.
                let recede = dp[i] - dp[j]
                if recede > 0 { sum += recede }
            }
            response[i] = cnt > 0 ? sum / cnt : 0
        }
        // Normalize by a high percentile of the responses: the raw response is very
        // skewed (a few silhouette dots dominate), so a fixed strength either barely
        // touches the bulk or nukes the tail. Dividing by ~p80 spreads the shading
        // across the whole field so the relief reads evenly, not just at hard edges.
        let sorted = response.sorted()
        let ref = max(1e-6, sorted[Int(0.80 * Double(n - 1))])
        for i in 0..<n {
            pts[i].edl = exp(-(response[i] / ref) * edlStrength)  // 1 = unshaded … →0 occluded
        }
    }

    /// Set the target palette. If its theme identity differs from what's currently
    /// shown, a smooth cross-fade begins (animated over `fadeDuration`). Pushing the
    /// same identity every frame is a no-op, so callers can call this each frame.
    func setPalette(_ p: Palette) {
        // Ignore repeats of the identity we're already showing/targeting. The key is
        // (mode, preset) so switching *preset* within the same light/dark mode still
        // cross-fades, while pushing the identical palette every frame stays a no-op.
        if p.id == palette.id && p.presetTag == palette.presetTag { return }
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
        let breathAmp = animate ? 0.04 * breathStrength : 0.0   // y in terrain.js, scaled by the user's strength
        let breathFreq = 0.4                    // I

        // Grow the dot radius with the projection scale so the pointillist texture
        // holds together as the viewport gets bigger. Sublinear (exponent < 1) so
        // dots enlarge gently; clamped to ≥1 so any viewport at/below the reference
        // scale (ratio ≤ 1 → pinned to exactly 1) is byte-for-byte unchanged.
        let scaleRatio = projector.scale(width: width, height: height) / Self.referenceScale
        let dotScale = max(1.0, pow(scaleRatio, Self.dotGrowthExponent))

        // Directional light on a slow azimuth arc + view vector for backface culling.
        // Computed once per frame; only consulted when lightingEnabled (else the dot
        // loop takes the exact original unlit path).
        let lit = lightingEnabled
        let (Lx, Ly, Lz) = Self.lightDir      // fixed overhead sun (for gentle warm/cool tint)

        // Project every grid point (with breathing), collect for depth sorting.
        struct Dot { let sx: Double; let sy: Double; let depth: Double; let z: Double; let ndl: Double; let edl: Double }
        var dots: [Dot] = []
        dots.reserveCapacity(grid.count)
        for g in grid {
            var z = g.baseZ
            z += breathAmp * sin(x * breathFreq + g.x * 0.7 + g.y * 0.6)
            let p = projector.project(g.x, g.y, z, width: width, height: height)
            let ndl = lit ? (g.nx * Lx + g.ny * Ly + g.nz * Lz) : 0  // N·L, half-Lambert input
            dots.append(Dot(sx: p.x, sy: p.y, depth: p.depth, z: z, ndl: ndl, edl: g.edl))
        }
        // Painter's order: far (small depth) first.
        dots.sort { $0.depth < $1.depth }

        let bottomFade = height * 0.84 // O
        for dot in dots {
            if dot.sx < -20 || dot.sx > width + 20 || dot.sy < -20 || dot.sy > height + 20 {
                continue
            }
            let l = max(0.0, min(1.0, (dot.z + J) / (2 * J)))
            var radius = (2.9 - l * 1.6) * dotScale
            var opacity = 0.3 + (1 - l) * 0.45
            if dot.sy > bottomFade {
                opacity *= max(0.0, 1 - (dot.sy - bottomFade) / (height - bottomFade))
            }
            let color = lit ? litColor(elevationColor(l), ndl: dot.ndl) : elevationColor(l)
            if lit {
                // Eye-Dome Lighting: a dot whose neighbors are NEARER is receding
                // (edl→0) — dim its opacity toward the floor AND shrink its area, while
                // near/high ridge dots (edl→1) stay bright and grow. This manufactures
                // the depth-discontinuity edges the sparse cloud lacks. Size coupling is
                // centered on 1× (sh=0.5 ⇒ unchanged) so mean dot size is preserved.
                let sh = dot.edl
                opacity *= Self.edlFloor + (1 - Self.edlFloor) * sh
                radius *= 1 + Self.edlSizeRange * (sh - 0.5)

                // Elevation emphasis: the mountain IS the high ground — diminish the
                // valley (l→0) toward (1−emphasis) opacity and shrink it, so the ridge
                // (l→1) carries the form. (Counters the faithful curves, which happen
                // to make valley dots bigger/brighter.)
                let e = Self.elevEmphasis
                opacity *= 1 - e * (1 - l)
                radius  *= (1 - e * 0.5) + (e * 0.5) * l
            }
            if opacity <= 0.004 { continue }

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
