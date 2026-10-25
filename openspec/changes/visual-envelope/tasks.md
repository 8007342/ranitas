## 1. Contract and documentation (branch `work/visual-envelope-specs`)

- [x] 1.1 Research the codebase across scene/light, pad physics and frog depth (docs/visual-envelope.md)
- [x] 1.2 Record environment limitations and open questions
- [x] 1.3 Write proposal, design and delta specs for this change
- [x] 1.4 Write the optional asset hand-off spec (art/ASSET_REQUESTS.md)

## 2. Atmosphere (branch `work/pond-atmosphere`)

- [ ] 2.1 Seeded rain intensity envelope in drizzle/storm; drive spawn, caps, streaks, ripples, shelter, audio label
- [ ] 2.2 Insect species table with biome night sets (firefly, moth, mayfly, glowbeetle) keyed on continuous daylight; procedural sprites
- [ ] 2.3 Colour-matrix time-of-day grade with per-biome night keys, replacing the flat wash; apply to foreground
- [ ] 2.4 `scripts/make-emissive.mjs` and generated emissive masks; emissive draw pass with fallback
- [ ] 2.5 Tests: envelope bounds and smoothness, determinism, night-set availability, grade monotonicity

## 3. Layers and palette cycling (branch `work/pond-layers`)

- [x] 3.1 Optional asset loader with procedural fallback and a single registry of optional filenames
- [x] 3.2 Palette-cycle engine (baked frames, blend/step, reduced-motion freeze) with procedural index generators
- [x] 3.3 Cycle regions for backdrops with water features (waterfalls, streams) and glows
- [x] 3.4 Layer stack with slots, depth-weighted sway, breathing parallax; move foreground into the renderer
- [x] 3.5 Procedural canopy generators per biome and particle emitters (petals, leaves, drips, spores)
- [x] 3.6 Tests: cycle periodicity, canopy clear-lane rule, optional-asset fallback, render smoke over all biomes

## 4. Pads and frog depth (branch `work/pond-pads-depth`)

- [ ] 4.1 Seeded hero + ambient pad layout with sections; mutable slow state; perspective radii
- [ ] 4.2 Momentum slide, drag, soft walls, curl-noise current, separation, sleep freeze
- [ ] 4.3 Pad-relative perches, frogs ride pads, in-flight homing
- [ ] 4.4 Perspective frog scale (quantised), scaled arc height, view selection, haze, scaled shadow, depth sort
- [ ] 4.5 Procedural away/toward poses; optional depth sheet loading
- [ ] 4.6 Rewrite fixed-home tests as pad-relative invariants; add slide, boundedness and moving-landing tests

## 5. Integration (branch `work/visual-envelope`)

- [ ] 5.1 Merge 2–4, resolve conflicts, `flutter analyze` and `flutter test` clean
- [ ] 5.2 Update styleguides and README for the new systems
- [ ] 5.3 Visual check in a browser build and capture screenshots
