# Manifold — a macOS screensaver

A minimal digital clock floating over a living **pointillist 3D terrain**, ported
faithfully from the hero animation on [ingtian.github.io](https://ingtian.github.io).

*Manifold* — the terrain is literally a 2-manifold surface; the name also nods to
manifold optimization and to many-folded mountain ranges (山水).

The terrain is a Gaussian-bump elevation field sampled on a 33×33 grid, projected
through a fixed yaw+tilt rotation and drawn as ~1000 elevation-colored dots. The
field breathes slowly, and glowing "walker" particles periodically trace
gradient-descent paths downhill and settle with a soft glow. Colors (sky gradient,
elevation ramp, walker glow) are the exact values from the site's `SkyWash.css`
and `terrain.js`, for both light and dark themes.

## Install

**Requirements:** macOS 14+ and the Xcode **Command Line Tools** (no full Xcode).
If you don't have them: `xcode-select --install`.

Because you build it **locally**, macOS doesn't quarantine it — there's no
"unidentified developer" wall and no Apple Developer account needed.

**One command** (clones, builds a universal binary, installs):

```sh
curl -fsSL https://raw.githubusercontent.com/ingtian/manifold-screensaver/main/scripts/install.sh | bash
```

**Or from a clone:**

```sh
git clone https://github.com/ingtian/manifold-screensaver.git
cd manifold-screensaver
scripts/install.sh        # build + install to ~/Library/Screen Savers
```

Then activate it: **System Settings → Screen Saver → scroll down to the "Other"
group → "Manifold"**, and click **Options…** to configure.

> If it doesn't show up right away, force a re-scan:
> `killall WallpaperAgent legacyScreenSaver 2>/dev/null || true`

### Manual build (without installing)

```sh
scripts/build.sh            # builds build/Manifold.saver (universal arm64 + x86_64)
scripts/build.sh install    # …and copies it to ~/Library/Screen Savers
```

## Options (Options… panel, persisted via ScreenSaverDefaults)

- **24-hour time** (default on) — `14:32` vs `2:32 pm`
- **Show seconds** (default on) — small superscript seconds that tick
- **Show date** (default on) — spaced-caps weekday + date under the time
- **Show walker particles** (default **off**) — the glowing downhill walkers
- **Theme** — Auto (match system) / Light / Dark
- **Font** — System (SF Pro) / Rounded / Serif (New York) / Monospace
- **Motto** — a small italic signature line below the clock, right-aligned to the
  date (default `Lorem Ipsum`). Any text works, including pasted Unicode such as
  Greek letters (α, β, σ, …); leave empty to hide.

The clock sits at a fixed position on the horizontal golden section (≈61.8% of
width), balancing the terrain's ridge on the left.

## Display adaptability

Everything in the scene is sized as a **fraction of the view** — no hardcoded
pixels — so it scales to any resolution or Retina scale factor. Verified on 16:9,
21:9, 32:9 super-ultrawide, and portrait. On screens wider than ~21:9 the terrain
grows toward the width (a uniform zoom, never a stretch) so it fills the display
instead of leaving empty side margins.

## Layout

```
Sources/
  Palette.swift          SkyWash gradient + elevation ramps + walker colors (light/dark)
  TerrainRenderer.swift  Core Graphics port of terrain.js (field, projection, walkers)
  Settings.swift         ScreenSaverDefaults-backed options + FontDesign/ThemePreference
  ManifoldView.swift     ScreenSaverView principal class (draw, layout, config sheet)
  ConfigSheet.swift      Programmatic AppKit options sheet
Resources/
  Info.plist             NSPrincipalClass = ManifoldView
  thumbnail.png/@2x      System Settings preview image (a real rendered frame)
scripts/
  build.sh               swiftc → universal .saver bundle (+ optional install)
  install.sh             one-command clone + build + install
tools/
  render_frames.swift    Headless verifier: loads the real .saver and renders PNGs
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

[`tools/render_frames.swift`](tools/render_frames.swift) loads the built bundle
exactly as the screensaver host does (`init(frame:isPreview:)` on
`NSPrincipalClass`) and captures frames — also used to generate the thumbnail:

```sh
SDK="$(xcrun --show-sdk-path)"
swiftc -sdk "$SDK" -framework AppKit -framework ScreenSaver \
  tools/render_frames.swift -o build/render_frames
mkdir -p build/frames
THEME=dark  ./build/render_frames build/Manifold.saver build/frames 1600 1000
THEME=light ./build/render_frames build/Manifold.saver build/frames 1600 1000
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
