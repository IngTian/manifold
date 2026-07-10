# Terrain lighting / depth experiment — findings

Status: **STAGED, not shipped.** Branch `feat/terrain-lighting`. Do not merge as-is.
This documents an exploration into making the terrain's 3D shape read more clearly
(lighting, occlusion, depth cues) and — importantly — *why it hit a ceiling*, so a
future attempt doesn't repeat the dead ends.

## Goal

The pointillist terrain colors every dot by **elevation only**, so a point on the
front slope and a point on the back slope at the same height are the *same color*.
The eye can't separate front from back; depth is unreadable, especially at the
centre of the map. We wanted a cue (shading / occlusion / depth) to convey shape.

## What was built (all gated behind `TerrainRenderer.lightingEnabled`; off ⇒ byte-for-byte identical to shipped)

- **Precomputed surface normals** per grid point from the analytic gradient
  `N = normalize(-∂z/∂x, -∂z/∂y, 1)` — cheap, like `baseZ`.
- **Half-Lambert directional shading** with warm-lit / cool-shadow tint. Brightness
  is theme-adaptive: darken shadows in light theme (reads against pale sky),
  brighten highlights in dark theme (reads against dark sky). This *does* convey
  some form and is the most defensible piece.
- **Backface dim + desaturate** (N·V < 0): the away-facing slope recedes in alpha
  and hue. Helps the dominant single ridge, but see the flaw below.
- A **fixed overhead sun** (an orbiting sun was tried first but swings behind the
  mountain for half the cycle, dropping the visible face into shadow — abandoned).

## What was tried for OCCLUSION and why each failed (data-backed)

Researched the industrial techniques (parallel web-research agents): floating
horizon, hidden-point-removal (Katz–Tal–Basri), eye-dome lighting, depth cueing.

- **World-space ray-march** (march the elevation field along the sightline): correct
  in principle but tie-prone at the silhouette (grazing rays), step-size sensitive on
  the 5-bump field, and I repeatedly got the eye-vector *sign* wrong by guessing
  instead of measuring. Lesson: **compute and print the geometry; never guess signs.**
- **Screen-space z-buffer**: fails because the cloud is *sparse* — ~1089 dots over
  millions of pixels, so a far dot almost never lands on the same cell as the near dot
  in front of it. Occlusion is simply missed. (Also resolution-dependent.)
- **Floating horizon** (the textbook method for `z=f(x,y)`): the correct tool, but on
  this *tilted, sparse, multi-bump* field the ridge self-occludes — a debug red/green
  overlay showed the crest classified "hidden". Needs careful per-slice ordering that
  wasn't worth the iterations for a single-dominant-ridge scene.

## The root cause (proven with a diagnostic, `/tmp` experiments)

Measured the bottom-of-screen dots and the dimmed-vs-bright populations:

- The **bottom-of-screen dots are the FAR valley floor** (depth-near ≈ 0.16,
  xy-toward-camera ≈ 0.19) — *not* the near foreground the eye assumes. The tilted
  projection wraps the far valley down to the bottom of the frame.
- **N·V dimming barely correlates with distance** (dimmed dots mean depth-near 0.49
  vs bright 0.43): it dims by *facing*, not distance, so dimmed/bright dots scatter at
  all depths → reads as arbitrary patches, not coherent depth.
- **Pure depth-cue** (far = dim) dims the crest/back and brightens the low foreground —
  i.e. it makes the *mountain recede*, backwards for "show me the mountain".

**Why nothing worked well:** the mountain ridge sits at **middle depth and middle
facing**. So neither a depth scalar nor a facing scalar aligns with "the mountain
body". No single per-dot scalar cue distinguishes the ridge, and the field is too
**sparse + dark-on-dark** to carry a strong cue anyway. That is the ceiling.

## Viewpoint note

Current camera = **37.3° above horizontal** (tilt constant `dt = 0.92 rad`). Raising
toward bird's-eye (dt ↓) flattens the height into the plane and reads *less* like a
mountain; lowering toward side-on (dt ↑) gives more silhouette height. Changing it
also drifts from the faithful ingtian.github.io port (dt is copied verbatim).

## If revisited — the one lever with a real ceiling

The cue that would actually track the ridge is **elevation itself** (brighten high
dots, dim low) — "the mountain is literally the high dots". Combined with a
**denser grid** (~4× dots, so there's an actual surface for shading/occlusion to
bite), that's the only path likely to produce a *dramatic* (not subtle) improvement.
Everything short of denser-grid produced only subtle effects.
