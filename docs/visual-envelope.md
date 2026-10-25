# Visual Envelope: Research, Limits and Decisions

This document covers research done on 2026-10-25 for the
[`visual-envelope`](../openspec/changes/visual-envelope/proposal.md) change. It
had three parallel read-only studies of the codebase: scene and light, lily pad
physics, and frog depth. Below are their conclusions, the limits of the
environment that implemented the change, the provisional decisions taken, and
the questions still open for the project owner.

## Limitations of this implementation environment

- **No image generation.** The existing backdrops, foregrounds and frog sheets
  came from an image-generation tool. This environment has none. It has node +
  sharp, ImageMagick and ffmpeg. As a result:
  - **Can be produced here:** procedural pixel art drawn in code (canopy strands,
    moss, vines, stalactites, particles, insect sprites, back and front frog
    poses), palette ramps and index maps, and emissive masks keyed from the
    existing backdrops.
  - **Cannot be produced here:** new painted backdrops, painted canopy and
    mid-bank layers, per-biome foregrounds, and painted frog depth sheets. Each
    is specified in [art/ASSET_REQUESTS.md](../art/ASSET_REQUESTS.md) and is
    wired as an optional asset with a procedural fallback.
- **No human viewing or play.** Motion constants come from physics reasoning and
  authored taste. Automated checks are technical checks. Nobody has watched,
  played or listened on a phone or tablet. The project's honest-evidence rule
  (`openspec/specs/experience/spec.md`) applies.
- **No physical-device performance numbers.** Draw-call budgets are estimates.
  Mobile Safari and low-end Android need real checks.
- **Procedural art will not match the painted look.** The code-drawn layers use
  the styleguide palette and a crisp pixel grid. The painted art is soft, faux
  pixel art. Until painted replacements arrive the two will sit side by side.

## Findings

### Scene, light and layers

- The renderer draws a 641×359 logical canvas in six tiers
  (`lib/game/pond_renderer.dart:183-291`). At night it darkens the backdrop with
  one flat `#101f48` rectangle at alpha `0.06 + 0.60·night` (`:216`). That
  desaturates lanterns and fungi along with everything else.
- The single foreground overlay is drawn outside the renderer
  (`lib/game/ranitas_game.dart:59-93`) with a modulate tint and a 0.3 % sway.
  It is the only "parallax" layer, and there is no camera.
- `pond-wildlife-sheet.webp` is loaded but never read, so it is dead weight.
- The source art is 1376×768 truecolor (145k–226k unique colours, dithered,
  anti-aliased). It is upscaled by nearest neighbour at a non-integer 1.858× to
  2557×1439, so pixels are uneven. Only one biome's art is loaded per session,
  so the per-session payload (~2 MB) and GPU memory (~14.7 MB per full-frame
  RGBA layer) matter more than the 25 MiB per-file cap.
- Weather is seeded once and persistent by spec. Rain is physical (drops aim at
  basin targets and dip pads or ripple the water), but its intensity is a fixed
  drizzle-or-storm switch.
- Fireflies are the only night insect, and species have no biome input.

**Palette cycling.** The art is not indexed, so true cycling needs index maps.
Three options were weighed:

- **Hue remap in a shader:** rejected, because it looks mushy on anti-aliased
  edges and adds web shader risk.
- **Index map + ramp, remapped in a shader:** correct but risky on the web.
- **Index map + ramp, baked to frames at load:** chosen. It has no runtime
  risk, draws with `FilterQuality.none`, and supports Ferrari-style blended
  cycling.

The blossom waterfall is only ~20×45 soft source pixels, so quantising it would
look mushy. A procedural or hand-painted index map looks better.

### Lily pads

- Hero pads sit on fixed per-biome anchors with hard-coded radii. Ambient pads
  are seeded but final (`lib/game/pond_model.dart:186-235`, `:1418-1449`).
- All pad motion is anchored damped springs (heave, tilt, lateral drift,
  float), so pads shimmy and always return. Nothing slides.
- Pads have no perspective projection. Radii are fixed per pad, and only the
  koi have a real depth law (`pond_renderer.dart:401-406`).
- Jump targets are fixed at launch and ignore drift. Landing snaps to them.
- Tests pin fixed homes (`test/pond_model_test.dart:73-76, 147-148`) and frozen
  positions after sleep (`test/pond_soak_test.dart:170-190`).

**Physics notes behind design D6:**

- **Heave:** the added mass of a thin heaving disc, `(8/3)ρa³`, dwarfs the
  leaf's own mass. Heave therefore stays small and stiff, which matches the
  existing springs.
- **Sliding:** lateral motion has little added mass, so a pad slides
  noticeably.
- **Drag:** a linear plus quadratic drag pair stops a 10 px/s slide in about
  1 s, after 5–8 px.
- **Current:** a divergence-free curl-noise current avoids pads piling up.
- **Bounds:** over-damped soft walls bound each pad without a visible rebound.
- **Integrator:** semi-implicit Euler at the existing fixed 1/60 s step stays
  stable at these stiffnesses.

### Frog depth

- Each frog has one 4×2 atlas plus pixel-matrix micro-expressions and a full
  procedural fallback (`lib/game/frog_sprites.dart`).
- Frogs are drawn at a fixed 42×36 with no perspective, after all pads, with no
  depth sorting. Facing is a mirror of right-facing cells.
- Side jumps need no new art. No back view exists anywhere, so back views must
  be procedural or painted, while the existing `falling` cell is almost
  frontal.
- Continuous nearest-neighbour scaling of the soft painted cells shimmers.
  Quantised scale is a stopgap; re-quantising the sheets to a true 42×36 grid is
  the real fix.
- The styleguide's phase thresholds (`.44/.58`) and the code (`.52`) already
  disagree (`art/STYLEGUIDE.md:62-66`, `pond_model.dart:1409`).

## Decisions

Rows marked **Decided** were answered by the project owner on 2026-10-25. The
rest are provisional defaults. Q numbers are the original numbering; the open
questions below have been renumbered.

| # | Topic | Default taken |
| --- | --- | --- |
| Q1 | Where rain varies | **Decided: follow nature.** Clear stays dry; mist never showers but thickens toward night and sheds fine fog drizzle (≤ 0.15) when thick; drizzle and storm vary |
| Q2 | Storm look | Darker clouds and heavier sheets of rain; never lightning |
| Q3 | Night insects | Fixed per-biome tables; all catchable |
| Q4 | Night grade | Colour matrix (no shader), shared indigo night with per-biome overrides for grotto, crystal_grotto and sanctuary |
| Q5 | What stays lit | Lanterns, fungi, windows, moon and stars, through script-generated masks |
| Q6 | Waterfall | Procedural index map now; painted map requested |
| Q7 | Cycle feel | **Decided: by material.** Water and bioluminescence blend smoothly; fire (lanterns) steps hard |
| Q8 | New layers | Procedural canopy per biome now; painted canopy, mid-bank and foreground requested |
| Q9 | Parallax | Wind sway plus slow breathing parallax; no pointer parallax; canopy keeps the central lane clear above 30 % height |
| Q10 | Integer re-export | Deferred; requested in the asset list |
| Q11 | Drift amount | **Decided: small roam, all pads.** Hero sections 10–14 px, ambient 4–10 px; ripples, koi and pad wakes push every pad |
| Q12 | Pads carry frogs | **Decided:** yes; roaming continues through sleep and the sleeping frogs ride their leaves |
| Q13 | Counts and sizes | 2 hero (base radius 30–40 px) + 4–9 ambient (9.5–21 px, about one in ten 21–28 px); **Decided (2026-10-25):** about one world in four adds a decorative 42–54 px super pad behind the heroes |
| Q14 | Occlusion | Pads never overlap; frogs depth-sort with pads |
| Q15 | Yaw | **Decided (2026-10-25):** real in-plane rotation; the slit is a see-through gap; pads turn on current shear, ripples, koi and hops (design D6 "As implemented") |
| Q16 | Frog scale | **Decided (2026-10-25):** continuous along the arc, sprite snapped to whole pixels (design D7 "As implemented") |
| Q17 | Depth-jump targets | Hero pads are seeded at different depths, so ordinary jumps gain depth |
| Q18 | JEV retraining | Not needed now; optional polish |
| Q19 | Sheet re-quantisation | **Decided:** request regenerated assets on a true pixel grid as needed (`art/ASSET_REQUESTS.md`) |

## Implementation status (2026-10-25)

All of the code for this change is built on `work/visual-envelope`. That branch
merges `work/pond-atmosphere`, `work/pond-layers` and `work/pond-pads-depth`
onto `work/visual-envelope-specs`. `flutter analyze` is clean and all 61 tests
pass.

**Deviations from the design** (details under "As implemented" in each design
section):

- **Pad slide constants:** pad landing momentum uses η = 0.2 and linear drag
  1.6 s⁻¹ instead of 0.08 and 1.2. With the seeded hop speeds (60–200 px/s) the
  design values gave 1–2 px slides.
- **Ambient pad sections:** these shrink to the free room in the basin,
  typically 1–9 px, so ambient leaves wander less than designed.
- **Visiting perch:** when a frog visits the other pad it perches at the rim,
  so hero landings now mostly hit the "edge" zone.
- **Emissive masks:** these were generated for 6 of the 12 backdrops (both
  grottos, both sanctuaries, firefly, willow). On the others the key caught
  petals, sun glitter or dithered sky, so those stay on plain grading.
  *2026-10-25, foliage branch:* the first-pass masks missed the real lights.
  The sanctuary mask held only water-line glints (the lantern window and its
  lit sill formed one blob above the 2600 px cap) and the grotto masks held
  the fungi *reflections* but not the caps. `make-emissive.mjs` now lets
  coloured blobs grow to 16 000 px and keys coloured pixels on a lower local
  contrast; the six masks were regenerated and checked by eye (lantern, every
  fungus cluster, moon and fireflies are lit). The other six backdrops were
  previewed again with the new rules and still key petals, larch boughs or
  water, so they keep plain grading plus the new additive star and glitter
  cycle regions.
- **Alpine stream:** alpine has no painted stream, so its `stream` cycle
  animates the far-shore water line.
- **Glow cycles:** the fungi and lantern cycles are additive halos, not pixel
  replacement.
- **Far-bank slot:** reserved; it has no procedural content yet.
- **Night insects:** they switch on at a daylight threshold. The smoothness
  comes from the existing 1/s fade-in.

**Visual check:** this was done on offscreen renders of every biome from the
smoke test, not in a browser or on a device.

- **Fixed:** a procedural top-centre bough read as a garland. It now sits just
  above the frame, and alpine has none.
- **Still visible:** procedural canopy colours are lighter and crisper than the
  painted backdrops, most noticeably the sanctuary bamboo. Painted canopy
  layers (`art/ASSET_REQUESTS.md` §2) are the intended fix.

## Foliage animation (research, 2026-10-25)

The owner asked for a few animated branches with packs of leaves, plus bushes
in the mid and near ground. This is how 2D and pixel-art games do it cheaply
and convincingly, and what Ranitas took from each idea
(`lib/game/foliage.dart`).

**Branches as hierarchical chains.** A branch is a chain of 3–6 rigid
segments from a root at the frame edge. Each segment's angle is a rest angle
plus a *lean*; the lean grows toward the tip (a cantilever bends most at its
free end) and lags the segment before it, so a gust ripples from trunk to tip
rather than snapping the whole branch at once. Full spring–pendulum
simulation (Verlet chains, as in Rayman Legends' foliage or Ori's grass) is
the convincing version, but it costs state, needs a fixed step, and drifts
under frame hitches. Ranitas instead evaluates the lean as a *function of
time and a short wind trace*: a 3 s ring buffer of the model's `wind`,
sampled each frame, read back with a lag of `x/641 × 0.5 s` (a gust front
crossing the screen with the wind) plus `0.07 s` per segment. This gives the
visible phase lag of a chain with no integration, stays deterministic, and
freezes trivially under reduced motion. Leans are clamped to ±0.36 rad, so
the geometry has a hard reach bound (`root + Σ segment + leaf radius`) that
the clear-lane test checks without sampling poses.

**Gust fronts.** The model already shapes gusts (`windTell` ramp, then a
3 s sine). What sells them visually is *travel*: things upwind move first.
The wind trace lag does that for branches and bushes alike, keyed on the
anchor's x and the wind's sign.

**Leaf packs as instanced sprites.** Drawing each leaf with rects costs a
draw call per pixel row. `Canvas.drawAtlas` / `drawRawAtlas` draws any number
of atlas cells in one call with a per-instance `RSTransform` (rotation,
uniform scale, translation) and a per-instance colour. All branch leaves of a
biome (~150) are one call; each bush slot is one call. The colour list
carries the reveal alpha; the paint's `colorFilter` carries the time-of-day
grade, so leaves darken with the scene without touching the atlas.

**Flutter versus sway, by size.** Large leaves and whole packs sway slowly
(1.7 Hz here); small leaves flicker faster (3.6 Hz). Amplitude is
`0.06 + 0.35 × |wind|` rad, so still air only breathes. Rotations are
quantised to 1/24 turn so pixel edges tick between a few crisp grids instead
of smearing.

**Leaf-flip highlight frames.** Real foliage sparkles because a leaf turning
its underside or catching the sun flashes lighter for a frame or two. The
atlas keeps a *lit* row for every leaf row (tones shifted one step up); when
a leaf's flutter phase passes 0.93 in moving air it swaps to that row for a
few frames. This is the single cheapest cue for "wind in leaves".

**Bushes.** Layered blobs anchored at the ground, sheared about the base
(`x += height × shear`) with the same lagged wind, so the top moves and the
root stays planted. The bodies are static and baked into one `Picture` per
slot and night bucket; the leaves on top are atlas instances that carry the
per-bush shear and flutter. Grotto bushes add three additive glow-moss
flecks each.

**Depth ordering.** Mid-bank bushes sit on the far shores just outside the
basin edge (behind the pads, scale 0.7, small-leaf row). Branches draw in the
canopy slot above frogs and insects, in the side quarters only. Near bushes
draw after the corner foreground, at the bottom corners, scale 1, large-leaf
row. Breathing parallax follows each slot's depth.

**Wind coupling.** Branch lean = `−(wind_lagged × 0.55 + windTell × 0.05)
× windResponse × (0.35 + 0.65 × tip fraction)`: shrinking the angle on both
sides lifts a branch pointing with the wind and pushes one pointing into it
down, like a flag, and the sign flips with the wind. Bush shear is
`wind_lagged × 0.35`, clamped to ±0.3.

**Mobile web budget.** Per frame: ~25 bark strokes (`drawLine`, no AA), one
`drawRawAtlas` for branch leaves, one per bush slot (two), two `drawPicture`
calls for bush bodies, and a handful of glow rects in grottos. The atlas is a
128 × 64 image baked once from deterministic bytes
(`LeafAtlas.pixelsFor`). Nothing allocates per frame beyond three
`Float32List`s sized to the instance count.

**Recommended architecture (taken):** procedural atlas + chains + bushes in
`foliage.dart`, hooked into the layer painter's slots; painted overrides for
the atlas (`foliage-<biome>.webp`) and a branch segment strip
(`branches-<biome>.webp`). **Painted assets that would improve it most:** a
hand-pixelled atlas per biome (the procedural leaves are readable but
generic), and bark strips with painted twigs, since the straight strokes read
as wire next to the painted trunks. A painted bush body sheet (3 silhouettes
per biome) would be the next step.

## Prime sizes and pixel scaling

The owner asked whether prime dimensions give free antialiasing when resizing.
In this pipeline they don't. Here is why, with the trade-offs, so the call can
be made deliberately:

- **No smoothing happens.** Every image here is drawn with
  `FilterQuality.none` (nearest neighbour), which never blends neighbouring
  pixels. On a non-integer scale it **duplicates some source pixels and not
  others**, so pixel widths alternate (e.g. 1-2-2-1-2). That is aliasing, not
  antialiasing.
- **Primes guarantee the uneven case.** A prime size shares no factor with any
  other size, so the ratio to any display is always non-integer and the
  unevenness is guaranteed rather than avoided. Primes stop a regular grid from
  lining up, which can hide *moiré* in some cases, but they don't smooth
  anything.
- **The pixels are already uneven before drawing.** The 1376×768 sources were
  nearest-upscaled by 1.858× into the 2557×1439 exports, which bakes uneven
  pixels into the files. They are then scaled again to the 641×359 logical
  canvas and again to the device. Three resamples compound the irregularity.
- **Where smoothing would come from:** a smoothing filter (`FilterQuality.low`
  or higher) blends neighbours on any scale, prime or not. That gives softness,
  at the cost of crisp pixels.

A whole-number re-export (e.g. 2752×1536 = 2 × 1376×768) removes one of the
three resamples and halves the file weight. It doesn't make the final
device-scale even, because screens vary. Keeping primes as a house style is
fine. The only change needed is to stop baking a non-integer resample into the
files.

**Decided 2026-10-25:** re-export at a whole number. `prepare-art.mjs` now
exports scenic art at exactly 2× its source (2752 × 1536). Downsampling the
export by 2 reproduces the source pixel for pixel. The emissive masks were
regenerated at the same size. Asset weight went from 18.17 to 18.53 MiB.

## Open questions

Answered on 2026-10-25 and removed from this list: showers and fog (now
follows nature), cycle feel (by material), drift amount (small, all pads),
riding during sleep (yes), regenerating sheets (yes, on request), the
whole-number re-export (done), and a depth-aware JEV (retrained, plus patience;
see `docs/policy.md`).

1. ~~In storms, should thunder density follow rain intensity?~~ **Decided
   2026-10-25:** it may get heavier, but briefly; downpours allow an occasional
   fuller rumble, capped at a croak's level and at least 60 s apart, and lulls
   return to the distant one (design D1).
2. ~~Which night insects are prey and which are only ambience? Should each
   biome use a fixed table or a seeded subset?~~ **Decided 2026-10-25:** all
   bugs are edible; each scenery has a fixed table with one or two signature
   species, some common species stay away, and a few species carry a voice
   that sounds only while they are on screen (design D2).
3. Should night push every biome toward one indigo, or should each biome keep
   its own palette? Would you accept a fragment-shader LUT later?
4. Do you want to approve the regenerated emissive masks (lantern, fungi,
   moon, fireflies, stars), or paint them instead? Maple, autumn-mist and mist
   have no painted light source at all; should one be painted in (lanterns on
   the bridge, a lamp in the cypress)?
5. Answered 2026-10-25: grotto water shimmer, every mushroom cluster, the
   moon, evening stars and sunset glitter now cycle (design D4). Which of them
   should be louder or quieter?
6. How many painted layers per biome are you willing to commission?
7. Should canopy layers ever cross the central play lane?
8. Do you want any giant or tiny pads beyond the default size ranges?
9. May pads slide behind one another, with the near pad occluding the far one?
10. Is a rotated-ellipse pad renderer worth it for true yaw?
11. Should frog scale be continuous, or snap between a few painted sizes?
12. Should depth jumps also be able to land on ambient pads, or in open water?
