## Context

Research for this change is summarised in [docs/visual-envelope.md](../../../docs/visual-envelope.md).
The renderer draws a 641×359 logical canvas in six tiers
(`lib/game/pond_renderer.dart`); `PondModel` is pure, seeded, and advanced in
fixed 1/60 s steps. The source art is AI-rendered truecolor faux pixel art, not
indexed, so palette tricks need index maps, and no image generation is available
in the environment that implements this change.

Every decision below marked *provisional* is a default chosen to keep work
moving; the open questions in the research doc may overturn it.

## Goals / Non-Goals

**Goals:** continuous light and weather, richer depth, physically plausible pad
motion, depth-aware frogs, and a drop-in contract for painted assets with a
procedural fallback for every one.

**Non-Goals:** lightning, camera cuts, pointer-hover parallax (no hover on
touch), fragment shaders (web compile risk), re-exporting the backdrops at an
integer scale, retraining the JEV prior, native audio.

## Decisions

### D1 Rain intensity envelope (decided 2026-10-25: follow nature)

*Owner decision:* "do the same thing that happens in nature". Clear stays dry
(rain needs cloud). Mist does not shower, because fog forms in calm, stable air
and showers need instability. What it does do is thicken as the air cools after
sunset (`mistDensity = 0.35 + 0.65·(1 − daylight)`), thin after sunrise, and,
when thick (density > 0.65, smoothstep to 0.85), shed a fine **fog drizzle**
from a `fog` envelope of 0.06–0.15 that is dry half the time. Mist bands follow
the density. Fog drizzle under 0.2 does not ground insects. Storms are left as
persistent frontal rain.

`rainIntensity ∈ [0,1]` follows a seeded piecewise-smooth envelope of 45–150 s
segments: drizzle sessions wander 0.15–0.55, storm sessions 0.35–1.0 with at
least one downpour above 0.85, both with occasional clearing lulls down to 0.05.
Spawn rate, drop cap, streak length/alpha, ripple intensity, cloud darkening and
insect shelter interpolate on it. Above 0.7, extra streaks are visual only (no
extra ripples) to bound cost; ripple cap stays 34. Clear and mist sessions keep
zero rain, so the seeded weather distribution is unchanged. Audio receives a
derived label (`drizzle` below 0.6, `storm` above) through the existing API.

*As implemented* (`lib/game/rain_envelope.dart`): the envelope owns a
`Random(sceneSeed ^ 0x2e7a9d1b)` stream and extends its node list lazily, so
sampling it never shifts the model's main draw order and the value at a time
is independent of update partitioning. Nodes join by smoothstep, bounding the
slope to `1.5·Δv/Δt ≤ 0.032 /s`. Storm nodes: start 0.35–0.48, then a
guaranteed downpour node 0.88–1.0, then alternating low (0.35–0.6, 25 % lull
0.05–0.12) and high (60 % downpour, else 0.6–0.88). Drizzle nodes: start
0.2–0.45, alternating 0.15–0.3 (20 % lull) and 0.35–0.55. Derived values:
drop cap `round(6 + 36·I)`, spawn rate `20 + 90·I` /s, streak length
`×(0.8 + 0.5·I)`, streak alpha `0.22 + 0.16·I`, impact ripple intensity
`0.30 + 0.14·I`, shelter `1 → 0.55` over `I ∈ [0, 0.3]` then `0.55 → 0.25`
to `I = 1`, cloud darkening `smoothstep((I − 0.06)/0.84)`, heavy-rain fog
fading in above 0.5, and up to 30 visual-only sheet streaks above 0.7.

*Thunder (decided 2026-10-25: "could get heavier but briefly — we want a
relaxing game").* The model now passes `rainIntensity` to the ambience beside
the derived weather label (`PondAmbience.update(…, rainIntensity:, species:)`,
both optional on the JavaScript side, so the four-argument form still works).
In `web/ambience.js` a pure `thunderPlan(rain, now, lastHeavyAt, rnd)` picks
each rumble while the storm label is active: the **distant** rumble is the
original voice (low-pass 180 Hz noise, 3.5 s, gain 0.18); a **heavy** rumble is
allowed only while the rain is a downpour (intensity ≥ 0.75), with a chance of
35 % at the threshold rising to 75 % at intensity 1, never within 60 s of the
previous heavy one, and is brief: 0.05 s attack into a 1.6 s decay, low-passed
at 260 Hz, gain capped at 0.26 (one croak syllable). The 22–45 s scheduling
interval is unchanged for both kinds, so lulls return to distant rumbles by
themselves. No lightning or flash of any kind; the renderer is untouched. The
plan is tested without an `AudioContext` by `scripts/ambience.test.mjs`
(`npm run test:ambience`).

### D2 Insect species table

Species become a table: base speed, flight style, altitude band, glow colour,
and a habitat predicate over biome, continuous `daylight`, and rain intensity.
Night sets: `firefly` (willow, cypress, firefly, lotus, alpine), `moth`
(sanctuary, jade_sanctuary, maple, autumn_mist, alpine, around light sources),
`mayfly` (lotus, blossom, willow at dusk, low over water), `glowbeetle` (grotto,
crystal_grotto, cyan/violet). All remain catchable (provisional). Day species
and the spawn budget formula are unchanged.

*As implemented* (`lib/game/insect_species.dart`): night sets require dry
weather (clear or mist) and `daylight < 0.56`, which matches the old firefly
boundaries in both cycles; willow mayflies additionally need `daylight ≥ 0.2`.
Table values: moth speed 0.055, wing rate 6, band 0.18–0.5, lantern-seeking
(sanctuary lantern at logical 114,168 → pull 0.035 plus a tangential drift);
mayfly speed 0.05, wing rate 9, band 0.5–0.68, hard floor 0.72, bob 0.03;
glowbeetle speed 0.04, band 0.3–0.62, turn gain 0.9, cyan or violet by a
variant bit derived from the spawn phase (no extra random draw). Spawn draws
keep their original order (species, angle, x, y, phase).

*Signature species (decided 2026-10-25: "all bugs are edible, but the set of
bugs should match the scenery").* Every scenery now owns one or two species
found only there or in a few related sceneries, some common species stay away
from sceneries they do not suit, and four species carry an ambient voice that
plays only while they are on screen. The matching is artistic natural history,
not biology. Twelve species join the table, all catchable, all drawn
procedurally in `_bug`:

| Species | Sceneries | Hours / weather | Voice |
| --- | --- | --- | --- |
| `waterstrider` (skates, band 0.57–0.68) | willow, lotus, blossom, sanctuary, jade_sanctuary | daylight ≥ 0.2, until rain reaches 0.5 | – |
| `whirligig` (spins, band 0.58–0.68) | willow, cypress, firefly | any hour, until rain reaches 0.5 | – |
| `damselfly` (blue or emerald) | lotus, blossom, jade_sanctuary | dry daylight, progress ≥ 0.12 | – |
| `bee` | blossom, sanctuary, jade_sanctuary, alpine | dry daylight, progress ≥ 0.1 | hum |
| `cicada` (canopy band 0.14–0.4) | maple, sanctuary, jade_sanctuary | warm: daylight ≥ 0.3, not storm | drone |
| `cricket` (night set) | maple, autumn_mist | dry dusk/night | trill |
| `katydid` (night set) | cypress, firefly | dry dusk/night | rasp |
| `cranefly` | autumn_mist, cypress | damp air, until rain reaches 0.5, not storm | – |
| `stonefly` | alpine only | any hour, any weather | – |
| `cavecricket` | grotto, crystal_grotto | any hour, any weather | – |
| `jewelbeetle` | jade_sanctuary only | dry daylight, progress ≥ 0.2 | – |
| `fungusgnat` (faint cyan halo) | crystal_grotto only | any hour | – |

Absences: `mosquito` leaves alpine and both grottos; `butterfly` leaves the
grottos and autumn_mist; `dragonfly` leaves the grottos; `ladybug` leaves
cypress, firefly, lotus and the grottos. Stoneflies and cave crickets are the
all-weather residents of the sceneries without mosquitoes, so no scenery is
ever empty (`_spawnBug` also guards an empty list without drawing). Table
additions: `vertical` (share of heading that becomes climb; 0.08–0.2 for
skaters and hoppers), `spawnInBand` (night sets and signature species spawn
inside their band; the original day species keep the 0.2–0.6 airspace) and
`voice`. The spawn budget formula and the draw order are unchanged; new
species only change which name a given draw selects. `PondModel.speciesPresence`
reports visible voiced insects as `cricket:3,bee:1` for the ambience.

### D3 Time-of-day grade (colour matrix, not shader)

A 4×5 colour matrix interpolated across four keyframes keyed on `daylight`:
day (identity), sunset (warm: R×1.04 G×0.90 B×0.80, peak at daylight≈0.6),
dusk (30 % desaturation, R×0.62 G×0.66 B×0.86), night (50 % desaturation,
R×0.34 G×0.42 B×0.66 plus a small blue lift). Each biome may override the night
key (grotto and crystal_grotto keep teal; sanctuary keeps warmth). The matrix
applies to the backdrop and painted layers through `Paint.colorFilter`;
procedural actors keep their own night handling. This replaces the flat
`#101f48` wash at an equivalent mean darkness.

Emissive regions: an optional per-backdrop mask (`emissive-<backdrop>.webp`,
alpha = light) is drawn as backdrop ∩ mask (`saveLayer` + `BlendMode.dstIn`)
with `BlendMode.plus` at strength `night × richness`, so lanterns and fungi glow
while the rest darkens. Masks are generated by `scripts/make-emissive.mjs` from
saturation/luminance keys and may be replaced by painted masks.

*As implemented* (`lib/game/scene_grade.dart`): keys sit at daylight 1 (day,
identity), 0.6 (sunset), 0.3 (dusk) and 0 (night); matrices interpolate
linearly between them, so swatch luminance is piecewise linear and monotone
after the sunset key. Night lift is (4, 8, 22)/255; grotto night is
R×0.28 G×0.48 B×0.60, 45 % desaturation, lift (2, 14, 18); sanctuary night is
R×0.44 G×0.40 B×0.52, 45 % desaturation, lift (12, 8, 12). On a seven-colour
reference swatch the night keys keep 0.40–0.60 of daylight luminance, like the
old wash on mid-grey (0.51). Day no longer carries the wash's 6 % tint.
Cloud darkening composes a `1 − 0.28·cloud` scale with `0.25·cloud`
desaturation. The emissive pass runs at `0.85 × night × richness`, skipped
below 0.02 or without a mask. Generated masks exist for grotto,
crystal-grotto, sanctuary, jade-sanctuary, dusk and firefly; on the other six
backdrops the key picks petals, sun glitter or dithered sky, so they stay on
plain grading until painted masks arrive.

*Revised 2026-10-25 (`work/pond-foliage`):* the first masks missed the main
lights. The lantern window with its lit sill and every fungus cluster formed
blobs above the 2600 px cap and were dropped, leaving only water glints and
reflections. The script now classifies a blob as *coloured* when half its
pixels pass the light-hue key, caps coloured blobs at 16 000 px (white blobs
stay at 2600 px, which still drops snow and sky), and keys coloured pixels on
a local contrast of 0.04 instead of 0.16 because a cap or window fills its own
blur radius. The six masks were regenerated and checked: lantern, all fungi,
moon and the painted fireflies and stars are lit. Light sources on the
maskless backdrops (the evening stars on blossom, lotus, alpine, dusk and
firefly; the grotto moon) are covered by additive emissive cycle regions
instead (D4). Maple, autumn-mist and mist contain no painted light source.

### D4 Palette cycling as cached frames

*Owner decision:* blend by material. Water and bioluminescence blend smoothly.
Fire (the sanctuary lanterns) steps hard at 7 fps. The scenery has no neon.

A cycle region is a logical-space rectangle with an index map (0 = transparent,
1..N = ramp slot) and a colour ramp. At load the engine bakes N frames (one
`Picture` per shift) and at runtime draws frame `floor(t·fps) mod N`, blending
to the next frame by its fractional part when `blend` is true (Mark Ferrari's
smooth cycling) or stepping hard when false (authentic 8-bit). Index maps come
from (a) procedural generators now (falling-water streaks, stream ripples, glow
pulses) or (b) a painted grayscale `cycle-<backdrop>-<region>.webp` later, read
with `Image.toByteData`. Shader remapping was rejected (web risk, mushy on
anti-aliased edges).

**As built (`lib/game/palette_cycle.dart`).** Frames are baked as small
`ui.Image`s (one per ramp shift, via `decodeImageFromPixels`) rather than
`Picture`s, so a blended frame is two `drawImageRect` calls with paint alpha
and no `saveLayer`. Glow regions are *additive* (`BlendMode.plus`, ramps carry
alpha) and dithered radially, because the painted fungi and lantern cannot be
masked procedurally; replacing their pixels would also overwrite rock. Painted
grayscale maps decode `slot = round(gray / 16)` and clamp to the ramp length.
Cycles draw in Tier 0 right after the backdrop image, before the night wash.
Region table (logical 641 × 359 coordinates, measured on the 1376 × 768
sources):

| Backdrop | Region | Rect (x, y, w, h) | Generator | N / fps | Blend |
| --- | --- | --- | --- | --- | --- |
| pond-blossom, pond-lotus | `waterfall` | 381, 150, 6, 18 | falling water | 6 / 9 | yes |
| pond-blossom, pond-lotus | `waterfall-strand` | 377, 153, 2, 14 | falling water | 6 / 9 | yes |
| pond-blossom, pond-lotus | `reflection` | 382, 169, 7, 15 | ripple bands | 5 / 3 | yes |
| pond-alpine | `stream` | 200, 186, 240, 4 | ripple bands | 6 / 4 | yes |
| pond-grotto, pond-crystal-grotto | `seep` | 572, 98, 22, 64 | falling water, density 0.4 | 8 / 6 | yes |
| pond-grotto, pond-crystal-grotto | `fungi` | 6, 206, 62, 50 | radial pulse, additive, emissive | 8 / 2.5 | yes |
| pond-grotto, pond-crystal-grotto | `fungi-right` | 564, 190, 66, 46 | radial pulse, additive, emissive | 8 / 2.2 | yes |
| pond-sanctuary, pond-jade-sanctuary | `lantern` | 88, 152, 48, 32 | radial pulse, additive, emissive | 8 / 5 | yes |

Deviations: the alpine backdrop has no painted melt stream, so `stream` is the
tarn's far-shore water line (dark teal row under the meadow) lapping sideways.

**Added 2026-10-25 (owner: "good animation candidates", "glowy things at
night").** Two new generators: `glints` (sparse 2–6 px dashes whose slots run
along the dash, so each glint flashes and travels; everything else stays
transparent) and the `_flash` ramp (one bright slot, two dim shoulders). Stars
and caps are additive radial pulses marked emissive (ungraded); water glitter
is additive but graded, because it is reflected sky light. Centres were
measured on the 1376 × 768 sources and converted to logical units.

| Backdrop | Region | Rect (x, y, w, h) | Generator | N / fps | Blend |
| --- | --- | --- | --- | --- | --- |
| pond-blossom, pond-lotus | `star` | 243, 55, 20, 20 | radial pulse, additive, emissive | 8 / 1.6 | yes |
| pond-blossom, pond-lotus | `star-faint` | 344, 56, 12, 12 | radial pulse, additive, emissive | 8 / 1.1 | yes |
| pond-blossom, pond-lotus | `glitter` | 140, 176, 380, 22 | glints, additive | 8 / 3 | yes |
| pond-alpine | `star` | 398, 24, 20, 20 | radial pulse, additive, emissive | 8 / 1.6 | yes |
| pond-alpine | `glitter` | 200, 192, 240, 44 | glints 0.025, additive | 8 / 2.5 | yes |
| pond-dusk, pond-firefly | `star` | 425, 25, 20, 20 | radial pulse, additive, emissive | 8 / 1.6 | yes |
| pond-dusk, pond-firefly | `glitter` | 120, 178, 400, 20 | glints 0.03, additive | 8 / 3 | yes |
| pond-maple, pond-autumn-mist | `glitter` | 230, 198, 150, 28 | glints 0.05, additive | 8 / 3 | yes |
| pond-mist | `sheen` | 214, 186, 180, 34 | glints 0.025, additive | 8 / 2 | yes |
| pond-sanctuary, pond-jade-sanctuary | `sheen` | 262, 188, 250, 30 | glints 0.02, additive | 8 / 2 | yes |
| pond-grotto, pond-crystal-grotto | `cap-tall` | 52, 136, 50, 48 | radial pulse, additive, emissive (cyan) | 8 / 2.1 | yes |
| pond-grotto, pond-crystal-grotto | `cap-violet` | 6, 160, 34, 32 | radial pulse, additive, emissive (violet) | 8 / 2.6 | yes |
| pond-grotto, pond-crystal-grotto | `cap-amber` | 106, 138, 34, 26 | radial pulse, additive, emissive (amber) | 8 / 1.9 | yes |
| pond-grotto, pond-crystal-grotto | `cap-lilac` | 126, 176, 46, 42 | radial pulse, additive, emissive (violet) | 8 / 2.4 | yes |
| pond-grotto, pond-crystal-grotto | `cap-low` | 148, 220, 32, 26 | radial pulse, additive, emissive (cyan) | 8 / 2.8 | yes |
| pond-grotto, pond-crystal-grotto | `cap-ledge` | 200, 204, 28, 24 | radial pulse, additive, emissive (amber) | 8 / 2 | yes |
| pond-grotto, pond-crystal-grotto | `cap-shelf` | 484, 92, 42, 38 | radial pulse, additive, emissive (amber) | 8 / 1.8 | yes |
| pond-grotto, pond-crystal-grotto | `cap-right` | 516, 146, 50, 48 | radial pulse, additive, emissive (cyan) | 8 / 2.3 | yes |
| pond-grotto, pond-crystal-grotto | `cap-violet-right` | 480, 216, 34, 34 | radial pulse, additive, emissive (violet) | 8 / 2.7 | yes |
| pond-grotto, pond-crystal-grotto | `cap-low-right` | 590, 250, 32, 30 | radial pulse, additive, emissive (cyan) | 8 / 2.5 | yes |
| pond-grotto, pond-crystal-grotto | `moon` | 336, 120, 32, 32 | radial pulse, additive, emissive, faint | 8 / 0.5 | yes |
| pond-grotto, pond-crystal-grotto | `shimmer` | 200, 236, 240, 64 | glints 0.03, additive, emissive | 8 / 2.5 | yes |

Crystal-grotto swaps the cap hues (magenta, pink, coral) and the shimmer to
lilac. Every backdrop now declares at least one region. The painted index-map
override (`cycle-<backdrop>-<region>.webp`) applies to all of them.

### D5 Data-driven layer stack

A biome declares `SceneLayer`s in slots: `farBank` (after backdrop, before water
tiers), `midBank` (after water, before pads), `canopy` (after frogs and insects,
anchored to the top, kept above y=0.30 in the central lane so high arcs stay
readable), `nearCorner` (the current foreground), `particles`. Each layer has a
depth factor driving sway amplitude, wind response, slow breathing parallax
(±1.5 px × depth, 40 s period) and grade strength. Layers render from a painted
image when its optional asset loads and otherwise from a procedural generator:
willow fronds, Spanish moss, vines, wisteria racemes, bamboo leaves, maple
boughs, stalactites with drips, pine boughs. The foreground draw moves from
`RanitasGame` into the renderer so it is graded and ordered with the others.

**As built (`lib/game/scene_layers.dart`).** `SceneLayers.stackFor(biome)` is
the table; `SceneLayerPainter.drawSlot` is called from `PondRenderer.render`
at farBank (after the sky), midBank (after the water surface), canopy and
particles (after bugs), nearCorner (after weather). Procedural canopies are
baked into 16 `Picture`s keyed by sway phase (5.5 s period), invalidated when
the night or reveal bucket changes; wind is a canvas skew about the top edge
(`shear = (wind·0.6 + windTell·0.032)·windResponse·depth`, capped at 0.08) so
the lean grows toward the tip without rebaking. Breathing parallax is
`±1.5 px × depth` on x (±0.45 on y) over 40 s. Reveal is
`(richness − revealAt)/0.25`; the foreground keeps its original
`(richness − 0.12)·0.68` opacity, sway and modulate tint. `tintFor(model)` is
the single tint helper for painted layers (`_shade` applies the same multiply
to procedural colours) and is the merge point for `SceneGrade.filterFor`.

**Foliage (added 2026-10-25, `lib/game/foliage.dart`).** Research is in
`docs/visual-envelope.md` ("Foliage animation"). Every biome gets, through
`FoliageSpec.forBiome`, a branch leaf kind and a bush leaf kind (willow
blades, cherry or peach petal clusters, momiji, bamboo, pine needle tufts,
moss sprigs, ferns, wisteria bits, broad bush leaves) with four-tone
palettes.

- *Atlas:* `LeafAtlas` is 8 × 4 cells of 16 px: row 0 large leaves, row 1
  small, rows 2–3 their lit flip frames; columns 0–3 the branch leaf in four
  shape/tone variants, 4–7 the bush leaf. `LeafAtlas.pixelsFor(spec)` is a
  pure function of the spec (deterministic bytes, alpha 0 or 255) and
  `bake` decodes it once per biome. A painted `foliage-<biome>.webp` at a
  whole multiple of 128 × 64 (256 × 128 at 2×) replaces it.
- *Branches:* 2–3 per side (`BranchChain`): one from the top corner reaching
  ≈ 100–115 px inward, one hanging from the top edge at x 30–54, one from
  the side edge at y 52–92. Chains have 4–5 segments shortening toward the
  tip, 5–7 leaf packs of 4–6 leaves, the last pack at the tip. The lean of
  segment k is `clamp(−(wind(t − lag_k)·0.55 + windTell·0.05)·windResponse·
  (0.35 + 0.65·(k+1)/n) + ambient, ±0.36)`, with `lag_k = x_root/641·0.5 s +
  0.07 s·k` read from a `WindTrace` ring buffer of the model's wind. Builder
  invariant: `root + Σ lengths + max pack radius ≤ laneLeft − 34 − 2`, so the
  central lane stays clear at any pose; the test checks the bound and seven
  extreme poses. Bark is `drawLine` strokes (no AA, tapering, lit upper edge)
  or cells of a painted `branches-<biome>.webp` strip (6 × 48 × 16 logical).
  Leaves are one `drawRawAtlas` call: rotation = base + segment lean +
  flutter (1.7 Hz large, 3.6 Hz small, amplitude `0.06 + 0.35·windy`),
  quantised to 1/24 turn; the lit row shows when the flutter phase exceeds
  0.93 in moving air.
- *Bushes:* two near bushes per bottom corner (rx 42–56 and 24–32, ground at
  y 352–356, 44/22 leaves) drawn after the corner foreground, and two mid
  bushes per side on the far shore just outside the basin edge (scale 0.7,
  14 small leaves) drawn after the mid bank. Bodies (two stacked scanline
  ovals plus a crown row in the biome's bush tones) bake into one `Picture`
  per slot and night bucket; the picture is sheared about y = 356 by the mean
  bush shear, and each leaf carries its own bush's shear
  (`clamp(wind_lagged·0.35 + tell·0.02 + ambient, ±0.3)`) times its height.
  Grotto bushes add three additive glow-moss flecks each.
- *Integration:* `SceneLayerPainter.foliage` draws after the declared layers
  of the midBank, canopy and nearCorner slots for every biome, reveals on
  `(richness − 0.2)/0.25`, takes the scene grade through the atlas paint's
  `colorFilter`, breathes with the slot depth, and freezes (zero lean, shear,
  flutter and flips) under reduced motion. `RanitasGame.onLoad` loads the two
  optional images and awaits `foliage.prepare(biome)`; until the atlas exists
  the slots draw nothing.

Clear-lane rule: `CanopyGeometry` places side elements at least 34 px outside
the central lane (x 160.25–480.75) and centre elements no deeper than 96 px,
which covers sway (≤ 7 px), curve (≤ 7 px), shear (≤ 14 px) and breathing;
`test/scene_layers_test.dart` checks every biome's strands, boughs, clusters
and lantern over 33 phases, both wind extremes and five seeds.

Particles are a pure function of time (seeded period and phase per particle,
no model mutation): petals (blossom, lotus; 14), momiji leaves (maple,
autumn_mist; 12), drips from stalactite tips (grotto, crystal_grotto; 6, 10
when raining) and spores (grotto, crystal_grotto; 10). They drift with wind and
end with a four-pixel ripple fade when they land inside the basin. The drifting
petals, leaves and moss formerly in `_motifs` were folded into this system;
the sanctuary lantern glow and grotto glow motifs stay. The bamboo canopy
hangs a paper lantern at x = 592 whose glow flickers live; stalactite glow moss
and crystals pulse live over the baked rock. Mid-bank procedural art is limited
to far-shore reeds for willow, cypress and firefly; the other biomes use the
slot only when `midbank-<biome>.webp` ships. farBank is reserved (no
procedural content, no optional asset yet).

### D6 Lily pad dynamics

*Owner decision:* every pad roams a **small** area and interacts with the water
and with the other pads. As implemented:

- **Sections:** ambient sections are reserved at placement (4–10 px, or 2 px for
  the last tight fits) and checked against every other section and the
  narrowing far shore. They are no longer grown into the free room. The
  tightest basins therefore fit 4 ambient pads.
- **Ripple drift:** passing ripple crests add Stokes drift to the slow slide
  (`10·strength`). A pad ignores ripples centred on its own body.
- **Koi:** wakes push along the fish's heading (`4·wake`).
- **Pad wakes:** a pad sliding faster than 2.5 px/s sheds a faint wake ripple
  every 0.45 s, so one landing nudges the neighbours.
- **Sleep:** roaming continues while the frogs sleep, and they ride their
  leaves.
- **Settling:** after a landing, the slide settles back to ambient roaming
  below 1 px/s within 3 s.

Layout: one seeded placer (`_fxRandom`) puts hero pad 0 in the left 22–42 % of
basin width and hero 1 in the right 58–78 %, each at any basin depth with a
14 px margin and a minimum vertical difference of 0 (depth jumps arise
naturally); hero base radius 30–40 px, 4–9 ambient pads (4 only in the tightest basins) with 9.5–21 px base
radius. Each pad owns a circular section (hero 10–14 px, ambient 22–30 px)
around its home; sections and pads never overlap.

Motion: slow state `x, y, vx, vy` (+ visual yaw) on top of the existing fast
springs (dip, tilt, driftX, floatY — constants unchanged). Landing impulse
`J = η·v_h` with η = 0.08, effective lateral mass `1.6 + 0.02·rx` (frog = 1),
70 % to slide velocity and 30 % to the drift spring; takeoff applies −0.8 J.
Drag `a = −1.2 v − 0.06 |v| v`, integrated implicitly. Soft section walls
`k = 2.5 s⁻²`, `c = 1.5 s⁻¹`; basin clamp kept as last resort. Current: curl of
seeded value noise, 90 px scale, 25 s time scale, 0.8–2.0 px/s (hero ×0.6),
plus `wind×3`. Pad–pad separation by mass-weighted penalty. Motion freezes
while sleeping. Yaw rotates veins and lotus only (scanline ovals cannot rotate).

*As implemented (`work/pond-pads-depth`):* η = 0.2 and linear drag 1.6 s⁻¹,
because the seeded hero spacing (75–135 px, perch ≈ 30 px inside the rim) gives
hop speeds of 60–200 px/s, and η = 0.08 / 1.2 s⁻¹ produced 1–2 px slides that
did not settle under 0.1 px/s within 3 s. `vx, vy` is the slide *relative to the
water*: the pad rides the current exactly and drag acts on the slide, so a
settled pad has zero slide speed while still wandering. The soft wall is a 3 px
band inside the section radius (at least 60 % of it) so ordinary slides finish
on free water. Ambient sections are nominally 22–30 px but shrink to the free
room around each pad (half the gap to neighbours, basin room); in the current
basins that is typically 1–9 px. Clamps run basin first, then section.

Depth: `perspectiveAt(yPx)` shared by pads, frogs and stems:
`s = 0.56 + 0.48·d`, `d = (y − basin.topY)/(basin.bottomY − basin.topY)`.
Radii, stem length and haze (`vd × 0.12` toward `#2f5d66`) follow it every tick;
`ry` is quantised to 0.5 px against scanline flicker.

Targeting: a perch is a pad-relative offset. While perched, the frog follows its
pad. In flight, the landing point homes toward the moving pad at 6 s⁻¹, which
keeps the parabola continuous. JEV is unchanged; its y-feature saturates
outside 0.6–0.8 but is only a 0.008 tie-breaker.

### D7 Frog depth motion

Frog scale is perspective at its ground point (not its airborne y), quantised to
1/16 steps, and the arc height is scaled by the same factor. View selection uses
`θ = atan2((toY − fromY)·2.5, toX − fromX)`: |θ| < 35° or > 145° → side poses;
otherwise away (moving up-screen) or toward (moving down-screen) poses, with a
residual horizontal flip. Haze `(1 − d)·(0.25 + 0.35·night)` blends toward the
water tone and opacity drops by `0.25·(1 − d)`; shadows scale with `s`. Frogs
join the pad painter's sort keyed by ground y. Away/toward poses are procedural
pixel matrices now; an optional `frog-<name>-depth-sheet.webp` supersedes them.

*As implemented:* the arc height uses the continuous perspective at the ground
point (only the sprite scale is quantised, so the arc has no 1/16 steps). The
visiting perch is `0.78·rx + 4 px` toward the visitor's home side instead of a
fixed 0.045 of the width. A back-view landing shows `back_idle`; a front-view
landing uses the side `landing` cell. Chomps during a back-view flight reuse
`away_fall` (no away chomp cell exists).

## Risks / Trade-offs

- Random hero layout breaks tests that assert fixed homes → rewrite as
  pad-relative invariants over 100 seeds.
- Continuous frog scale shimmers on noisy painted cells → quantised scale and
  a recommended future re-quantisation of the sheets to a 42×36 grid.
- More layers mean more draw calls on mobile web → layers cache `Picture`s per
  sway bucket where possible; particle and strand counts are capped.
- Procedural canopy art will not match the painted backdrops' rendering →
  painted replacements are specified in `art/ASSET_REQUESTS.md`.

## Open Questions

Listed in [docs/visual-envelope.md](../../../docs/visual-envelope.md#open-questions).
