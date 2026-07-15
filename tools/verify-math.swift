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
//    2. Value lock: every surface's FITTED elevation at two fixed points matches
//       values frozen here (computed out-of-band from the math spec + the affine fit,
//       NOT by calling TerrainField). This anchors what check 1 can't — a coordinated
//       retune that shifts elevation() and gradient() together — and, for .classic,
//       locks fidelity to the ported terrain.js values.
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

        // --- 2. Value lock: FITTED elevation matches frozen reference values ---
        // Check 1 only proves gradient == d/dx(elevation) for whatever the surface
        // currently IS — a coordinated tuning change (e.g. ackleyK π/2 → π) shifts
        // elevation() and gradient() together and would pass it. So pin each surface's
        // fitted elevation at two fixed world points to values FROZEN here (computed
        // once, out-of-band, from the math spec + the affine fit — not by calling
        // TerrainField). Any change to a surface's shape, domain map, or fit constants
        // moves these and fails the check. Regenerate deliberately if a surface is
        // intentionally retuned. (For .classic these also lock fidelity to terrain.js.)
        let p0 = (0.0, 0.0), p1 = (1.3, -0.8)
        let refs: [(TerrainFunction, Double, Double)] = [
            (.classic,     0.266305,  0.321117),
            (.ackley,     -2.128260,  0.117248),
            (.himmelblau,  0.417902, -0.131305),
            (.rosenbrock, -0.398021, -1.309327),
            (.rastrigin,  -1.784222,  0.566023),
            (.rosette,    -0.280303, -0.375903),
            (.ripples,     2.439202,  0.654336),
            (.hexWaves,    1.031893, -1.095251),
        ]
        for (fn, want0, want1) in refs {
            let field = TerrainField(function: fn)
            for (pt, want) in [(p0, want0), (p1, want1)] {
                let got = field.elevation(pt.0, pt.1)
                let ok = abs(got - want) < 1e-5
                print(String(format: "value %-16@ h(%.1f,%.1f) = %+.6f  (ref %+.6f)  %@",
                             fn.label as NSString, pt.0, pt.1, got, want, ok ? "OK" : "*** FAIL ***"))
                if !ok { failures += 1 }
            }
        }

        if failures > 0 { die("\(failures) math check(s) failed") }
        print("all math checks passed")
    }
}
