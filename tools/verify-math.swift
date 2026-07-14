//
//  verify-math.swift
//  Committed regression tests for the terrain MATH — the one thing that must be
//  right and that renders plausibly wrong when it isn't (a sign error in a gradient
//  makes the walkers drift the wrong way and the EDL normals invert, but nothing
//  crashes and the render smoke-test still passes). These asserts lock in the
//  invariants that were previously only checked by uncommitted throwaway scripts.
//
//  Two checks, over the SHARED engine (Sources/Shared/*.swift), compiled exactly
//  like render.swift (own module name, no product shell):
//
//    1. Gradient consistency: for every TerrainFunction, the analytic
//       TerrainField.gradient() matches a central finite-difference of the composed
//       TerrainField.elevation() at a scatter of points. This validates the WHOLE
//       fitted chain (domain map + affine z-fit + closed-form gradient) the walkers
//       and normals actually consume — not just the raw per-surface partials.
//
//    2. Classic fidelity: the classic field's elevation at a few points matches
//       hardcoded reference values (the ported terrain.js `tt()`), locking the
//       "byte-identical to the site" claim against accidental drift.
//
//  Exits non-zero on any failure so CI fails loudly. Run: `swiftc ... && ./verify-math`.
//

import Foundation

@main
struct VerifyMath {
    static func die(_ msg: String) -> Never {
        FileHandle.standardError.write(("FAIL: " + msg + "\n").data(using: .utf8)!)
        exit(1)
    }

    // A deterministic scatter of sample points in [-N, N]^2 (no RNG, so CI is stable).
    // Skips a small disc around the origin where a couple of surfaces have a guarded
    // cusp (Ackley's R→0, ripples' r→0) whose one-sided FD is meaningless.
    static func samplePoints() -> [(Double, Double)] {
        let N = TerrainField.halfExtent
        var pts: [(Double, Double)] = []
        var i = -7
        while i <= 7 {
            var j = -7
            while j <= 7 {
                let x = Double(i) / 7.0 * N
                let y = Double(j) / 7.0 * N
                if x * x + y * y > 0.09 { pts.append((x, y)) }   // skip |r|<0.3 (guarded cusps)
                j += 1
            }
            i += 1
        }
        return pts
    }

    static func main() {
        var failures = 0

        // --- 1. Gradient == central finite-difference, per surface ---
        let h = 1e-5
        // Relative tolerance: the fitted surfaces span a wide range of local slopes;
        // a pure absolute tol would be too strict on the steep ones and too loose on
        // the flat ones. Compare |analytic - FD| against tol*(1 + |analytic|).
        let relTol = 1e-4
        for fn in TerrainFunction.allCases {
            let field = TerrainField(function: fn)
            var worst = 0.0
            var worstAt = (0.0, 0.0)
            for (x, y) in samplePoints() {
                let (gx, gy) = field.gradient(x, y)
                let fdx = (field.elevation(x + h, y) - field.elevation(x - h, y)) / (2 * h)
                let fdy = (field.elevation(x, y + h) - field.elevation(x, y - h)) / (2 * h)
                let ex = abs(gx - fdx) / (1 + abs(gx))
                let ey = abs(gy - fdy) / (1 + abs(gy))
                let e = max(ex, ey)
                if e > worst { worst = e; worstAt = (x, y) }
            }
            let ok = worst <= relTol
            print(String(format: "grad %-16@ max rel err %.2e  %@",
                         fn.label as NSString, worst, ok ? "OK" : "*** FAIL ***"))
            if !ok {
                failures += 1
                FileHandle.standardError.write(
                    "  \(fn.label): rel err \(worst) at \(worstAt) exceeds \(relTol)\n".data(using: .utf8)!)
            }
        }

        // --- 2. Classic fidelity: elevation matches the ported terrain.js values ---
        // Reference values recomputed directly from the five-Gaussian tt() definition
        // (a_k, c_k, sigma_k, U=1.7) — an independent lock on the classic surface.
        let classic = TerrainField(function: .classic)
        let refs: [(Double, Double, Double)] = [
            (0.0, 0.0, referenceClassic(0.0, 0.0)),
            (1.0, -0.5, referenceClassic(1.0, -0.5)),
            (-1.4, -0.5, referenceClassic(-1.4, -0.5)),   // a bump center
            (2.0, 2.0, referenceClassic(2.0, 2.0)),
            (-2.0, 1.3, referenceClassic(-2.0, 1.3)),
        ]
        for (x, y, want) in refs {
            let got = classic.elevation(x, y)
            let ok = abs(got - want) < 1e-9
            print(String(format: "classic h(%.1f,%.1f) = %.6f  (ref %.6f)  %@",
                         x, y, got, want, ok ? "OK" : "*** FAIL ***"))
            if !ok { failures += 1 }
        }

        if failures > 0 { die("\(failures) math check(s) failed") }
        print("all math checks passed")
    }

    /// Independent reference implementation of the classic five-Gaussian field
    /// (terrain.js `tt()`), used only to lock TerrainField(.classic).elevation().
    static func referenceClassic(_ x: Double, _ y: Double) -> Double {
        let bumps: [(a: Double, cx: Double, cy: Double, s: Double)] = [
            (-1.0, -1.4, -0.5, 0.9), (-0.65, 1.5, 0.7, 0.8), (-0.5, 0.3, -1.3, 0.7),
            (0.7, -0.2, 0.9, 1.0), (0.45, 1.0, -0.6, 0.7),
        ]
        var t = 0.0
        for b in bumps {
            let dx = x - b.cx, dy = y - b.cy
            t += b.a * exp(-(dx * dx + dy * dy) / (2 * b.s * b.s))
        }
        return t * 1.7
    }
}
