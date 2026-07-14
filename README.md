# Manifold — a macOS screensaver & live wallpaper

[![build](https://github.com/IngTian/manifold/actions/workflows/build.yml/badge.svg)](https://github.com/IngTian/manifold/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![Platform](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Universal](https://img.shields.io/badge/universal-arm64%20%C2%B7%20x86__64-informational)

> *「聖人含道映物，賢者澄懷味象。」*
> *The sage embodies the Way and mirrors things; the wise clarify the mind and savor forms.*
> — 宗炳《畫山水序》, Zong Bing, *Preface on Landscape Painting* (c. 400 CE)

A minimal digital clock floating over a living **pointillist 3D terrain** — a
mountain rendered as breathing points of light. Ported faithfully from the hero
animation on [ingtian.github.io](https://ingtian.github.io).

*Manifold* — the terrain is literally a 2-manifold surface; the name also nods to
manifold optimization and to many-folded mountain ranges (山水).

<p align="center"><sub><b>Screen saver</b> — the terrain with a floating clock</sub></p>
<p align="center">
  <img src="docs/saver-dark.gif"  width="49%" alt="Manifold screen saver, dark — clock over terrain cycling through Classic, Nordic Slate, Glacier, Bordeaux Night">
  <img src="docs/saver-light.gif" width="49%" alt="Manifold screen saver, light — clock over terrain cycling through Classic, Sumi-e Ink, Basalt & Ash, Heather & Slate">
</p>

<p align="center"><sub><b>Live wallpaper</b> — the same terrain, no clock, behind your desktop</sub></p>
<p align="center">
  <img src="docs/wallpaper-dark.gif"  width="49%" alt="Manifold live wallpaper, dark — terrain cycling through Classic, Nordic Slate, Glacier, Bordeaux Night">
  <img src="docs/wallpaper-light.gif" width="49%" alt="Manifold live wallpaper, light — terrain cycling through Classic, Sumi-e Ink, Basalt & Ash, Heather & Slate">
</p>

<p align="center"><sub>Eye-Dome Lighting makes the sparse dots read as a solid 3-D
ridge; the clips cycle through a few of the eight palettes (each cross-fading like a
theme switch).</sub></p>

The terrain is a height field `z = h(x, y)` sampled on a 33×33 grid, projected
through a fixed yaw+tilt rotation and drawn as ~1000 elevation-colored dots. Each dot
is shaded by **Eye-Dome Lighting** — darkened and shrunk where its screen neighbors
sit nearer — so the sparse cloud reads as a solid mountain rather than a flat scatter.
The field breathes slowly, and glowing "walker" particles periodically trace
gradient-descent paths downhill and settle with a soft glow. The **Classic** palette's
colors (sky gradient, elevation ramp, walker glow) are the exact values from the site's
`SkyWash.css` and `terrain.js`; seven more bundled palettes re-skin both light and dark.
Switching theme *or* palette **cross-fades** smoothly (a slow dawn/dusk transition)
rather than snapping.

The surface itself is selectable, too: the default **Classic** field is the site's
five Gaussian bumps, and a **gallery of eight math surfaces** swaps in others — the
classic optimization landscapes **Ackley**, **Himmelblau**, **Rosenbrock** and
**Rastrigin**, plus a Gaussian-windowed **monkey-saddle rosette**, damped radial
**ripples**, and a **hexagonal wave** lattice. Each has a closed-form gradient, so the
walkers keep descending the *real* surface, and each is fitted to the same elevation
band as Classic so the camera, colors and lighting stay tuned. (The optimization
functions are apt: the walkers are literally gradient descent, so each surface becomes
a live picture of basins of attraction, ill-conditioned valleys, and local-vs-global
capture.)

## Install

**Requirements:** macOS 14+ and the Xcode **Command Line Tools** (no full Xcode).
If you don't have them: `xcode-select --install`.

Because you build it **locally**, macOS doesn't quarantine it — there's no
"unidentified developer" wall and no Apple Developer account needed.

There are two pieces and you can install either or both. The one-command
installer takes a `screensaver` (default), `wallpaper`, or `all` argument:

```sh
# Screen saver only (default):
curl -fsSL https://raw.githubusercontent.com/IngTian/manifold/main/scripts/install.sh | bash

# Live wallpaper only:
curl -fsSL https://raw.githubusercontent.com/IngTian/manifold/main/scripts/install.sh | bash -s -- wallpaper

# Both:
curl -fsSL https://raw.githubusercontent.com/IngTian/manifold/main/scripts/install.sh | bash -s -- all
```

*(The `-s --` passes the argument through to the piped script.)*

**Or from a clone:**

```sh
git clone https://github.com/IngTian/manifold.git
cd manifold
scripts/install.sh            # screensaver (default)
scripts/install.sh wallpaper  # live wallpaper
scripts/install.sh all        # both
```

The screen saver installs to `~/Library/Screen Savers/Manifold.saver`; the
wallpaper installs to `/Applications/Manifold Wallpaper.app` and launches
immediately. See **[Configuring & using](#configuring--using)** below to turn
them on and tune them.

> If the screen saver doesn't show up in System Settings right away, force a
> re-scan: `killall WallpaperAgent legacyScreenSaver 2>/dev/null || true`

### Manual build (without installing)

```sh
scripts/build.sh                    # build/Manifold.saver (universal)
scripts/build.sh install            # …and copy to ~/Library/Screen Savers
scripts/build-wallpaper.sh          # build/Manifold Wallpaper.app (universal)
scripts/build-wallpaper.sh install  # …and copy to /Applications + launch
```

## Updating

Re-run the same installer — it fetches the latest source, rebuilds, and
overwrites the installed copy in place. Your settings are **not** touched (they
live in preference stores, not in the app):

```sh
# Update whatever you have installed (pick the matching component):
curl -fsSL https://raw.githubusercontent.com/IngTian/manifold/main/scripts/install.sh | bash -s -- all
```

- **Screen saver:** the installer nudges the settings UI to reload; if a preview
  looks stale, close and reopen the Screen Saver pane (or
  `killall WallpaperAgent legacyScreenSaver`).
- **Live wallpaper:** the installer quits the running copy, replaces the app, and
  relaunches it automatically — no logout needed.

From a clone, `git pull` first, then re-run `scripts/install.sh <component>`.

## The live wallpaper

The same terrain can also run as a **live desktop wallpaper** — the breathing
mountain behind your icons, with an animated light↔dark cross-fade. It's a tiny
background app (`Manifold Wallpaper.app`) that shares the exact renderer with the
screen saver. No clock by design — a calm backdrop rather than a second clock
competing with your menu bar.

**Why a separate app?** macOS exposes no public API for animated wallpapers, so —
like every third-party live wallpaper (Plash, etc.) — it pins its own borderless
window at the desktop level (above the static wallpaper, below your icons). Because
it never touches the screensaver subsystem, it's unaffected by MDM screensaver
policies. It's **battery-aware**: 30 fps normally, 15 fps on battery / Low Power
Mode, and it fully pauses (≈0 % CPU) whenever the desktop is covered, the display
sleeps, the screen is locked, or the real screensaver runs.

## Configuring & using

The two pieces are configured in **two different places** — the screen saver
through System Settings (macOS only knows about `.saver` bundles there), the
wallpaper through its own menu-bar icon (it's a standalone app). Both remember
their settings across restarts and updates.

### The screen saver — System Settings → Options…

1. **Turn it on:** System Settings → **Screen Saver** → scroll down to the
   **"Other"** group → pick **Manifold**. Set the idle timer under
   **Lock Screen → "Start Screen Saver when inactive"**.
2. **Configure it:** click **Options…** on the Manifold tile. Settings persist via
   `ScreenSaverDefaults` and take effect immediately in the preview:

   - **24-hour time** (default on) — `14:32` vs `2:32 pm`
   - **Show seconds** (default on) — small superscript seconds that tick
   - **Show date** (default on) — spaced-caps weekday + date under the time
   - **Show walker particles** (default **off**) — the glowing downhill walkers
   - **Shape lighting (Eye-Dome)** (default **on**) — shades each dot by how much
     its screen neighbors occlude it, so the sparse point cloud reads as a solid
     3-D ridge instead of a flat scatter. Turn it off for the plain pointillist look.
   - **Theme** — Auto (match system) / Light / Dark
   - **Palette** — the color scheme. Eight bundled presets: **Classic** (the ported
     teal/earth look), **Nordic Slate** (cool blue-gray), **Sumi-e Ink** (monochrome
     graphite), **Glacier** (cold cyan ice), **Heather & Slate** (muted violet-gray),
     **Graphite & Copper** (graphite with one warm accent), **Basalt & Ash** (warm
     neutral gray), **Bordeaux Night** (deep oxblood). The theme (light/dark) still
     picks the variant *within* the chosen palette, and palette switches cross-fade.
   - **Surface** — the terrain's math function. Eight bundled surfaces: **Classic**
     (the site's Gaussian bumps), **Ackley**, **Himmelblau**, **Rosenbrock**,
     **Rastrigin** (four optimization landscapes the walkers descend), a
     **Monkey-Saddle Rosette**, **Still Water** (ripples), and **Hex Interference**.
   - **Font** — System (SF Pro) / Rounded / Serif (New York) / Monospace
   - **Zoom** — how much of the terrain fills the screen (0.60–1.15×); lower shows more
     of its footprint (wide), higher zooms in. Default `0.85`.
   - **Motion** — breathing strength (0–2×): how much the terrain wobbles. `0` is
     perfectly still, `1.0` the tuned default, higher is livelier.
   - **Motto** — a small italic signature line below the clock, right-aligned to
     the date (default `Lorem Ipsum`). Any text works, including pasted Unicode
     such as Greek letters (α, β, σ, …); leave empty to hide.

   The clock sits on the horizontal golden section (≈61.8 % of width), balancing
   the terrain's ridge on the left.

### The live wallpaper — the ⛰ menu-bar icon

Once installed, the app runs in the background and shows a **⛰ icon in the menu
bar** (top-right). Everything is configured from that menu — there's no System
Settings entry, because it's an app, not a `.saver`:

- **Theme** — Auto (match system) / Light / Dark (switches cross-fade smoothly)
- **Palette** — the same eight presets as the screen saver (Classic, Nordic Slate,
  Sumi-e Ink, Glacier, Heather & Slate, Graphite & Copper, Basalt & Ash, Bordeaux
  Night); switches cross-fade
- **Surface** — the same eight terrain functions as the screen saver (Classic, Ackley,
  Himmelblau, Rosenbrock, Rastrigin, Monkey-Saddle Rosette, Still Water, Hex
  Interference)
- **Shape lighting** — toggle Eye-Dome Lighting (default on), the depth-shading that
  makes the terrain read as a 3-D ridge
- **Zoom** — Wide / Default / Close / Closest — how much of the terrain is shown
- **Motion** — Still / Subtle / Default / Lively — the breathing strength
- **Walker particles** — toggle the glowing downhill walkers
- **Pause on battery** — fully stop animating on battery (default off; it already
  drops to 15 fps and pauses when hidden regardless)
- **Show message** — toggle the bottom-left signature line
- **Set message…** — edit that line's text (editing it turns it on). Default
  `Lorem Ipsum`; paste any Unicode you like. It sits at the lower-left golden
  section and cross-fades with the theme.
- **Launch at login** — start the wallpaper automatically at login
- **Quit Manifold Wallpaper** — stop it (removes the desktop window)

> *Launch at login* uses `SMAppService`, which wants a stably-located, signed app —
> that's why the installer puts it in `/Applications`. If the toggle ever fails on
> an ad-hoc build the app still runs; enable it manually in **System Settings →
> General → Login Items**.

## The math

The scene is a small amount of closed-form math, ported verbatim from
[`terrain.js`](https://ingtian.github.io) into
[`TerrainRenderer.swift`](Sources/Shared/TerrainRenderer.swift). Here's the whole thing.

**Elevation field.** The terrain is a sum of $M = 5$ Gaussian bumps over the
plane $(x, y)$, scaled by $U = 1.7$:

$$
h(x, y) \;=\; U \sum_{k=1}^{M} a_k \,
\exp\!\left( -\frac{(x - c_{k,x})^2 + (y - c_{k,y})^2}{2\,\sigma_k^2} \right)
$$

Each bump $k$ has amplitude $a_k$ (signed — negative bumps carve valleys), center
$(c_{k,x}, c_{k,y})$, and spread $\sigma_k$. The field is sampled on a square grid
$x, y \in [-N, N]$ with step $V$ ($N = 2.6,\ V = 0.16$), giving
$\left(\lfloor 2N/V \rfloor + 1\right)^2 = 33 \times 33 = 1089$ points.

**Surface gallery.** `h` is one of eight selectable surfaces (`Classic` above, plus
Ackley, Himmelblau, Rosenbrock, Rastrigin, a Gaussian-windowed monkey saddle, damped
ripples, and a hexagonal wave field). Each non-classic surface $g$ is evaluated over
its own native domain and then affine-fitted onto the exact elevation band Classic
occupies over the lattice — sample $g$ at $s\cdot(x,y)$ (a domain scale $s$) and map
$h = z_{\text{scale}}\,(g - g_{\text{mid}}) + z_{\text{mid}}$ — so the fixed camera,
color ramp, Eye-Dome Lighting and breathing stay tuned for every one. Because this fit
is affine (hence monotonic), the closed-form gradient carries through by the chain rule
($\nabla h = z_{\text{scale}}\,s\,\nabla g$) and the walkers still descend the real
surface. The two steep test functions (Himmelblau, Rosenbrock) are $\log(1+\cdot)$
-compressed first — also monotonic, so their minima and descent paths are unchanged
while the ~1000× outer walls stop flattening the basins on a sparse cloud.

**Gradient.** Walkers flow downhill along $-\nabla h$, which has a closed form
(each bump contributes its own Gaussian times a linear factor):

$$
\frac{\partial h}{\partial x} = -U \sum_{k=1}^{M}
a_k \, \frac{x - c_{k,x}}{\sigma_k^2}\,
\exp\!\left( -\frac{(x - c_{k,x})^2 + (y - c_{k,y})^2}{2\,\sigma_k^2} \right)
$$

and symmetrically for $\partial h / \partial y$.

**Breathing.** Each frame the elevation is perturbed by a slow travelling wave in
time $t$ (seconds), so the surface gently swells and settles:

$$
z(x, y, t) \;=\; h(x, y) \;+\; A \, \sin\!\big( \omega t + 0.7\,x + 0.6\,y \big),
\qquad A = 0.04,\ \ \omega = 0.4
$$

**Projection.** Each point $(x, y, z)$ is rotated by a fixed yaw $\theta = 0.18\pi$
about the vertical axis, then tilted by $\phi = 0.92$ rad, and orthographically
projected to the screen:

$$
\begin{aligned}
u &= x\cos\theta - y\sin\theta, &\quad
d &= x\sin\theta + y\cos\theta, \\
p &= d\cos\phi - z\sin\phi, &\quad
\text{depth} &= d\sin\phi + z\cos\phi.
\end{aligned}
$$

With a scale factor $f = 0.34 \cdot \max\!\big(\min(W, H),\ 0.46\,W\big)$ (the
$\max$ is the ultra-wide fill — a uniform zoom, never a stretch), the on-screen
position is $\big(\tfrac{W}{2} + u f,\ 0.46\,H - p f\big)$. Points are painted
back-to-front by `depth`, and colored by a normalized elevation
$\ell = \mathrm{clamp}\big((z + J)/2J,\ 0, 1\big)$ (with $J = 1.55$) that
drives both the dot's color ramp and its radius/opacity.

**Walkers.** The glowing particles are literally gradient descent: from a fixed
start $(x_0, y_0)$, iterate $\mathbf{p}_{i+1} = \mathbf{p}_i - \eta\,\nabla h(\mathbf{p}_i)$
with step $\eta = 0.16$ until $\lVert \nabla h \rVert < 0.01$ (a local minimum), then
resample the path to 10 points and animate it tracing downhill. It's the same
descent a first-order optimizer walks — the "manifold" the name nods to.

## Display adaptability

Everything in the scene is sized as a **fraction of the view** — no hardcoded
pixels — so it scales to any resolution or Retina scale factor. Verified on 16:9,
21:9, 32:9 super-ultrawide, and portrait. On screens wider than ~21:9 the terrain
grows toward the width (a uniform zoom, never a stretch) so it fills the display
instead of leaving empty side margins.

## Layout

```
Sources/
  Shared/                The framework-free engine, compiled into BOTH products:
    Palette.swift          SkyWash gradient + elevation ramps + walker colors (light/dark)
                             + palette blending for the theme cross-fade
                             + PalettePreset color schemes (8 presets)
    TerrainRenderer.swift  Core Graphics port of terrain.js (field, projection, walkers)
                             + TerrainFunction surface gallery (8, closed-form gradients)
                             + the animated theme cross-fade + surface-morph state machines
    TerrainConfig.swift    the shared render knobs (single source of truth for key/default/clamp)
  Saver/                 Screen-saver-only shell:
    Settings.swift         ScreenSaverDefaults-backed options + FontDesign/ThemePreference
    ManifoldView.swift     ScreenSaverView principal class (draw, layout, config sheet)
    ConfigSheet.swift      Programmatic AppKit options sheet
  WallpaperApp/          Live-wallpaper-only shell (reuses Shared/):
    main.swift             accessory-app entry point
    AppDelegate.swift      per-display windows, status-bar menu, theme, launch-at-login
    WallpaperWindow.swift  borderless NSWindow pinned at the desktop level
    TerrainWallpaperView.swift  layer-backed view, CADisplayLink frame pacing
    PlaybackGovernor.swift particle/battery/occlusion/sleep/lock pause logic
    WallpaperSettings.swift  UserDefaults-backed options (own suite, no ScreenSaver dep)
Resources/
  Info.plist             NSPrincipalClass = ManifoldView (the .saver)
  Wallpaper-Info.plist   LSUIElement agent app (the wallpaper)
  thumbnail.png/@2x      System Settings preview image (a real rendered frame)
scripts/
  build.sh               swiftc → universal .saver bundle (+ optional install)
  build-wallpaper.sh     swiftc → universal "Manifold Wallpaper.app" (+ optional install)
  install.sh             one-command clone + build + install
                           (arg: screensaver | wallpaper | all; also the updater)
tools/
  render.swift           Headless verifier: renders both products to PNGs
                           (saver = loads the real .saver; wallpaper = shared renderer)
  verify-math.swift      Math regression tests: every surface's analytic gradient vs
                           finite differences, + classic-field fidelity (run in CI)
```

## Publishing / forking

This is distributed as **source you build locally**, which is the friction-free
path for a free, open-source macOS screensaver: locally-built bundles aren't
quarantined by Gatekeeper, so no Apple Developer account, code-signing identity,
or notarization is required. Your friends just run `scripts/install.sh`.

If you fork it, update `REPO_URL` in [`scripts/install.sh`](scripts/install.sh)
and the bundle id `com.ingtian.manifold` (in
[`Resources/Info.plist`](Resources/Info.plist) and
[`scripts/build.sh`](scripts/build.sh)) to your own namespace.

**If you ever want it distributed as a signed, download-and-double-click bundle**
(so users don't build it themselves), that requires the paid Apple Developer
Program ($99/yr): sign with a Developer ID and notarize —
`codesign --options runtime --sign "Developer ID Application: …"` then
`xcrun notarytool submit … --wait` and `xcrun stapler staple`. Not needed for the
build-locally flow above.

## Verifying rendering headlessly

[`tools/render.swift`](tools/render.swift) renders either product to PNGs. In
**saver** mode it loads the built `.saver` and drives it exactly as the screensaver
host does (`init(frame:isPreview:)` on `NSPrincipalClass`) — proving the real
shipping bundle loads and draws. In **wallpaper** mode it drives the shared
`TerrainRenderer` (the same engine the app uses) with the wallpaper's own settings,
since the wallpaper is a plain app, not a loadable bundle.

```sh
SDK="$(xcrun --show-sdk-path)"
swiftc -sdk "$SDK" -O -parse-as-library -module-name Render \
  -framework AppKit -framework ScreenSaver \
  Sources/Shared/*.swift \
  Sources/WallpaperApp/WallpaperSettings.swift tools/render.swift \
  -o build/render
mkdir -p build/frames

# Saver: pass the built bundle. THEME forces light/dark.
THEME=dark  ./build/render saver build/Manifold.saver build/frames 1600 1000
THEME=light ./build/render saver build/Manifold.saver build/frames 1600 1000

# Wallpaper: reads WallpaperSettings; PALETTE=<int> LIGHTING=0|1 ZOOM=<n> override.
PALETTE=1 THEME=dark ./build/render wallpaper build/frames 1600 1000
```

## Notes

- Fidelity: grid density (1089 pts), projection matrix, color ramps, breathing,
  and walker timing are copied verbatim from `terrain.js` so the aesthetic matches
  the site. The device-pixel-ratio (`g`) factor is omitted deliberately —
  Core Graphics applies the backing scale itself, so point-space drawing is
  equivalent.
- The bundle is ad-hoc code-signed, which is exactly right for the build-locally
  flow. See **Publishing / forking** above for the notarized-distribution path.

## License

[MIT](LICENSE) © Ing Tian (Zeying Tian). Terrain aesthetic after
[ingtian.github.io](https://ingtian.github.io).
