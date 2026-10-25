## 1. Contract and documentation (branch `work/visual-envelope-specs`)

- [x] 1.1 Research the codebase across scene/light, pad physics and frog depth (docs/visual-envelope.md)
- [x] 1.2 Record environment limitations and open questions
- [x] 1.3 Write proposal, design and delta specs for this change
- [x] 1.4 Write the optional asset hand-off spec (art/ASSET_REQUESTS.md)

## 2. Atmosphere (branch `work/pond-atmosphere`)

- [x] 2.1 Seeded rain intensity envelope in drizzle/storm; drive spawn, caps, streaks, ripples, shelter, audio label
- [x] 2.2 Insect species table with biome night sets (firefly, moth, mayfly, glowbeetle) keyed on continuous daylight; procedural sprites
- [x] 2.3 Colour-matrix time-of-day grade with per-biome night keys, replacing the flat wash; apply to foreground
- [x] 2.4 `scripts/make-emissive.mjs` and generated emissive masks; emissive draw pass with fallback
- [x] 2.5 Tests: envelope bounds and smoothness, determinism, night-set availability, grade monotonicity

## 3. Layers and palette cycling (branch `work/pond-layers`)

- [x] 3.1 Optional asset loader with procedural fallback and a single registry of optional filenames
- [x] 3.2 Palette-cycle engine (baked frames, blend/step, reduced-motion freeze) with procedural index generators
- [x] 3.3 Cycle regions for backdrops with water features (waterfalls, streams) and glows
- [x] 3.4 Layer stack with slots, depth-weighted sway, breathing parallax; move foreground into the renderer
- [x] 3.5 Procedural canopy generators per biome and particle emitters (petals, leaves, drips, spores)
- [x] 3.6 Tests: cycle periodicity, canopy clear-lane rule, optional-asset fallback, render smoke over all biomes

## 4. Pads and frog depth (branch `work/pond-pads-depth`)

- [x] 4.1 Seeded hero + ambient pad layout with sections; mutable slow state; perspective radii
- [x] 4.2 Momentum slide, drag, soft walls, curl-noise current, separation, sleep freeze
- [x] 4.3 Pad-relative perches, frogs ride pads, in-flight homing
- [x] 4.4 Perspective frog scale (quantised), scaled arc height, view selection, haze, scaled shadow, depth sort
- [x] 4.5 Procedural away/toward poses; optional depth sheet loading
- [x] 4.6 Rewrite fixed-home tests as pad-relative invariants; add slide, boundedness and moving-landing tests

## 6. Owner follow-ups (2026-10-25)

- [x] 6.1 Weather follows nature: fog thickens toward night, fine fog drizzle, no showers in mist or clear
- [x] 6.2 Every pad roams a small section; ripple Stokes drift, koi and pad wakes; roaming through sleep
- [x] 6.3 Cycle feel by material (water smooth, fire stepped)
- [x] 6.4 Whole-number scenic re-export (2752 × 1536) and regenerated emissive masks
- [x] 6.5 Depth-aware JEV prior (12→16→3) retrained, plus patience when nothing is in reach

## 7. Foliage, more cycles, glow at night (branch `work/pond-foliage`, 2026-10-25)

- [x] 7.1 Research cheap, convincing 2D foliage animation; write it up (docs/visual-envelope.md "Foliage animation")
- [x] 7.2 Procedural leaf-sprite atlas per biome (`LeafAtlas`), baked once, drawn with `drawRawAtlas`; optional painted `foliage-<biome>.webp`
- [x] 7.3 Branch chains from the top corners with wind-trace lag, bounded lean and leaf packs; optional painted `branches-<biome>.webp` strip
- [x] 7.4 Mid-bank and near-corner bushes with ground-anchored shear, baked bodies, atlas leaves, grotto glow flecks
- [x] 7.5 New palette-cycle regions: grotto shimmer, every fungus cluster, moon, evening stars, sunset/alpenglow/fog glitter (`glints` generator)
- [x] 7.6 Emissive masks regenerated so lanterns, fungi, moon and fireflies are lit; maskless backdrops get additive star regions
- [x] 7.7 Tests: clear-lane bound and poses, atlas determinism, reduced-motion freeze, wind trace, cycle periodicity for every region, render smoke with and without optional images

## 5. Integration (branch `work/visual-envelope`)

- [x] 5.1 Merge 2–4, resolve conflicts, `flutter analyze` and `flutter test` clean
- [x] 5.2 Update styleguides and README for the new systems
- [x] 5.3 Visual check of rendered frames for every biome (offscreen renders, not a browser; see docs/visual-envelope.md)

## 7. Fauna and sound (branch `work/pond-fauna-sound`)

- [x] 7.1 Thunder follows the rain envelope: brief, capped heavy rumbles in downpours, at least 60 s apart, lulls return to distant; rain intensity passed to the ambience (backward compatible)
- [x] 7.2 Signature insect species per scenery (12 new, all catchable, procedural sprites), common-species absences, all-weather residents
- [x] 7.3 Species-linked ambient voices (cricket, katydid, bee, cicada) gated on on-screen presence; per-species presence string from the model
- [x] 7.4 Tests: signature availability and absences per biome, resident coverage, presence string, partition determinism, sprite smoke; Node tests for the pure thunder plan (`npm run test:ambience`)
