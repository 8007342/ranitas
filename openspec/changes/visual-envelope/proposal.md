## Why

The pond already reads as a living place, but its light, weather, layout and
camera depth are static: weather never changes intensity, night has one insect,
backdrops darken with a single flat wash, pads sit on fixed anchors at one
depth, and every frog jump is a sideways hop. The next step is to make the
scene breathe on every axis while keeping the quiet, scoreless contract, and to
do it as a data-driven framework that painted assets can be dropped into later.

## What Changes

- Rain gains a continuous, seeded intensity envelope (first drops → drizzle →
  shower → downpour → clearing) inside drizzle and storm sessions. Still no
  lightning.
- Night insects become biome-specific sets (fireflies, moths, mayflies, glow
  beetles) that cross-fade on continuous daylight.
- Backdrops and the foreground are graded through sunset → dusk → night (or the
  reverse at dawn) with colour matrices instead of a flat wash; emissive regions
  (lanterns, fungi, windows) stay lit through masks.
- Palette-cycling regions animate waterfalls, streams and glows the way 1990s
  scenery did, from procedural index maps now and painted index maps later.
- A per-biome, data-driven layer stack adds canopy layers hanging from the top
  (willow fronds, Spanish moss, vines, wisteria, stalactites), mid-bank layers,
  particle emitters (petals, leaves, drips, spores) and optional painted layers.
- **BREAKING (layout):** lily pads are seeded per world in size and position,
  slide after takeoff and landing, wander within bounded sections on a
  divergence-free current, and change depth (scale, brightness) as they move.
  Hero pads are no longer fixed per-biome anchors.
- Frogs carry depth: jumps between pads at different depths scale the frog with
  perspective, pick side, away (back view) or toward (front view) poses by
  screen-space direction, and fade with atmospheric haze.
- Optional asset contract: named files that image-generation agents can supply
  later are loaded when present and fall back to procedural art when absent.

## Capabilities

### New Capabilities

- `scene-composition`: layer stack, time-of-day grading, emissive light,
  palette cycling, particle emitters and the optional asset contract.
- `lily-pad-dynamics`: seeded pad layout, bounded drift, jump momentum, depth.
- `frog-depth-motion`: depth-aware jump arcs, view selection, scale and haze.

### Modified Capabilities

- `experience`: weather intensity becomes time-varying within persistent
  weather; insect species gain biome night sets; frogs land on pads that move.
- `ranitas`: frog animation states extend with away and toward views.

## Impact

- `lib/game/pond_model.dart` (pads, rain, insects, frog arcs),
  `lib/game/pond_renderer.dart` (tiers, grading, pads, frogs), `lib/game/frog_sprites.dart`,
  `lib/game/ranitas_game.dart` (optional asset loading), new files under `lib/game/`.
- New `scripts/make-emissive.mjs` and generated `assets/images/emissive-*.webp`.
- Tests that pin fixed hero-pad homes are rewritten as pad-relative invariants.
- `art/ASSET_REQUESTS.md` lists every asset still to be painted.
