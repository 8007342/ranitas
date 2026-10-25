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

## Provisional decisions

These are defaults so the work can proceed. Each maps to an open question
below.

| # | Topic | Default taken |
| --- | --- | --- |
| Q1 | Where rain varies | Only inside drizzle and storm sessions; clear and mist stay dry, so the spec'd weather distribution holds |
| Q2 | Storm look | Darker clouds and heavier sheets of rain; never lightning |
| Q3 | Night insects | Fixed per-biome tables; all catchable |
| Q4 | Night grade | Colour matrix (no shader), shared indigo night with per-biome overrides for grotto, crystal_grotto and sanctuary |
| Q5 | What stays lit | Lanterns, fungi, windows, moon and stars, through script-generated masks |
| Q6 | Waterfall | Procedural index map now; painted map requested |
| Q7 | Cycle feel | Blended (smooth) by default; per-region switch for hard steps |
| Q8 | New layers | Procedural canopy per biome now; painted canopy, mid-bank and foreground requested |
| Q9 | Parallax | Wind sway plus slow breathing parallax; no pointer parallax; canopy keeps the central lane clear above 30 % height |
| Q10 | Integer re-export | Deferred; requested in the asset list |
| Q11 | Drift amount | Hero wander ±6–8 px depth, slide ≤12 px per jump; ambient sections 22–30 px |
| Q12 | Pads carry frogs | Yes, including sleeping frogs (pads freeze their slow drift during sleep) |
| Q13 | Counts and sizes | 2 hero (base radius 30–40 px) + 5–9 ambient (9.5–21 px) |
| Q14 | Occlusion | Pads never overlap; frogs depth-sort with pads |
| Q15 | Yaw | Veins and lotus only |
| Q16 | Frog scale | Scales with depth, quantised to 1/16 |
| Q17 | Depth-jump targets | Hero pads are seeded at different depths, so ordinary jumps gain depth |
| Q18 | JEV retraining | Not needed now; optional polish |
| Q19 | Sheet re-quantisation | Not done; requested |

## Open questions

1. Should clear or mist sessions ever develop passing showers? That would
   change the "persistent weather" requirement.
2. In storms, should thunder density follow rain intensity?
3. Which night insects are prey and which are only ambience? Should each biome
   use a fixed table or a seeded subset?
4. Should night push every biome toward one indigo, or should each biome keep
   its own palette? Would you accept a fragment-shader LUT later?
5. Which painted elements must glow at night in each backdrop? Do you want to
   approve the script-generated emissive masks, or paint them instead?
6. Which other regions should palette-cycle (grotto water, mushroom caps, the
   alpine stream, the sanctuary lantern)?
7. For cycling, do you prefer smooth blending or the authentic hard-stepped
   90s look?
8. How many painted layers per biome are you willing to commission?
9. Should canopy layers ever cross the central play lane?
10. Should every backdrop be re-exported at an integer scale before more layers
    are added?
11. Should drift be more dramatic, with pads visibly roaming the pond?
12. Should sleeping frogs keep riding their pads' slow drift?
13. Do you want any giant or tiny pads beyond the default size ranges?
14. May pads slide behind one another, with the near pad occluding the far one?
15. Is a rotated-ellipse pad renderer worth it for true yaw?
16. Should frog scale be continuous, or snap between a few painted sizes?
17. Should depth jumps also be able to land on ambient pads, or in open water?
18. Should JEV learn depth-aware jumps? That needs retraining.
19. May the painted frog sheets be re-quantised to a hard 42×36 grid?
