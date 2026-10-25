# Asset Requests: Visual Envelope

This list is for agents or artists who can paint images. Every asset below is
**optional**. The game looks for each one by filename in `assets/images/`. If a
file is missing or fails to decode, the game draws a procedural fallback, so you
can deliver them in any order and each one appears as soon as it ships.

The registry of optional filenames lives in code
(`lib/game/optional_assets.dart`); `RanitasGame.onLoad` loads the canopy,
mid-bank and foreground layers and `PaletteCycles.load` the cycle index maps.
Keep this file and that registry in sync.

## Shared rules

- Style: follow [STYLEGUIDE.md](STYLEGUIDE.md) and the common production
  direction in [README.md](README.md). That means crisp hand-placed square pixel
  art in the 1990s adventure-game manner: jewel teal, indigo, lavender, amber and
  peach. No text, UI, watermarks, frogs (except on the frog sheets) or animals.
- **Real pixel grid.** Paint at the logical resolution and scale up by a whole
  number, or paint on a clean grid. The current sources are soft "faux pixel"
  renders, and when the frog scales with depth they shimmer. A true grid would
  fix that.
- Transparency: use real alpha, with fully transparent pixels around every
  cut-out. RGB under alpha 0 should be black.
- Commit source PNGs to `art/source/` and run `node scripts/prepare-art.mjs` to
  export lossless WebP into `assets/images/`. Run `npm run check:assets`
  afterwards to check the file budget (Cloudflare caps each file at 25 MiB).
- **Sizes:** paint every scenic layer at the 1376 × 768 source grid (or a
  given fraction of it). `prepare-art.mjs` exports at exactly 2× (2752 × 1536),
  so each painted pixel becomes a 2 × 2 block. Don't deliver pre-scaled art at
  other sizes, because a non-integer resample makes pixel widths uneven.

Biome ids: `willow`, `blossom`, `cypress`, `maple`, `sanctuary`, `grotto`,
`alpine`, `lotus`, `firefly`, `autumn_mist`, `jade_sanctuary`, `crystal_grotto`.
In filenames, write `autumn_mist` as `autumn-mist`, and so on with hyphens.

## 1. Frog depth sheets (highest priority)

| File | Size | Grid |
| --- | --- | --- |
| `frog-meadow-depth-sheet.png` | 1031 × 521 | 4 × 2 cells |
| `frog-teal-depth-sheet.png` | 1031 × 521 | 4 × 2 cells |

Use the same character, palette and cell layout as `frog-meadow-sheet.png` and
`frog-teal-sheet.png`. In each cell the frog occupies about 40 × 36 effective
pixels, centred, with its feet on a common baseline 5 px above the bottom of the
cell. Paint each frog facing **right**; the game mirrors it for left.

| Cell | Row 0 (away from camera, back view) | Row 1 (toward camera, front view) |
| --- | --- | --- |
| 0 | `away_launch`: back ¾ view, low crouch, hind legs coiled | `toward_launch`: front ¾ view, crouched, eyes up at the viewer |
| 1 | `away_ascend`: back view, hind legs extended down, arms reaching forward | `toward_ascend`: front view, belly visible, arms reaching toward the viewer |
| 2 | `away_fall`: back view, limbs spread, toe pads visible under the body | `toward_fall`: front view, limbs spread wide, toe pads flared |
| 3 | `back_idle`: back ¾ view perched crouch (landing on a far pad) | `toward_chomp`: front view, mouth open, tongue base visible |

Prompt seed: *"4×2 pixel-art sprite sheet of the same [emerald meadow tree frog
| jewel turquoise pond frog] as the reference sheet; top row seen from behind
leaping away from the camera (crouch, ascending, descending, perched); bottom row
seen from the front leaping toward the camera (crouch, ascending, descending,
mouth open catching a bug); transparent background; crisp square pixels; same
palette."*

## 2. Canopy layers (things hanging from the top)

| File | Size | Anchor |
| --- | --- | --- |
| `canopy-<biome>.png` | 1376 × 384 (painted grid), exported 2× | top edge, full width |

These are drawn above the frogs and insects, sway with wind, and are graded
with the time of day. The layer maps 1:1 onto the top half of the 1376 × 768
source frame. **In the central 50 % of the width (x 344–1032), keep every row
below y = 230 transparent**, because that is 30 % of frame height and the frogs'
high arcs pass there. Hanging elements may reach the bottom of the layer in the left
and right quarters.

| Biome | Content |
| --- | --- |
| willow | cascading willow fronds, long thin leaf strands |
| cypress, firefly | cypress boughs with long Spanish moss strands |
| blossom, lotus | cherry branches with blossom clusters and some falling petals |
| maple, autumn_mist | crimson and gold momiji boughs |
| sanctuary, jade_sanctuary | bamboo leaves and culm tops, a hanging paper lantern on one side |
| grotto, crystal_grotto | dripping limestone stalactites, hanging vines and glowing moss (crystals for crystal_grotto) |
| alpine | pine and golden larch boughs with snow dust |

Bonus: `canopy-wisteria.png` (lavender wisteria racemes), usable in blossom and
sanctuary.

## 2b. Leaf atlases and branch strips (animated foliage)

The game grows animated branches and bushes from a leaf-sprite atlas
(`lib/game/foliage.dart`, design D5 "Foliage"). The procedural atlas is
readable but generic; a hand-pixelled one per biome is the single most
visible upgrade here.

| File | Size | Grid |
| --- | --- | --- |
| `foliage-<biome>.png` | 256 × 128 | 8 columns × 4 rows of 32 × 32 px cells (16 × 16 logical at 2×) |
| `branches-<biome>.png` | 576 × 32 | 6 cells of 96 × 32 px (48 × 16 logical at 2×) |

**Atlas layout.** Columns 0–3 are the *branch leaf* in four shape or tone
variants; columns 4–7 are the *bush leaf*. Row 0 holds large leaves, row 1
small leaves (about 60 % size), row 2 the lit "flip" frame of row 0 and row 3
the lit frame of row 1: the same leaf one tone lighter with a highlight
pixel, shown for a few frames when the leaf turns in the wind. Centre each
leaf in its cell; the game rotates cells about their centre by up to ±0.6 rad
plus flutter. Hanging leaves (willow blades, moss, wisteria) should hang from
the top-centre of the cell. Transparent background; alpha 0 or 255 only.

| Biome | Branch leaf (cols 0–3) | Bush leaf (cols 4–7) |
| --- | --- | --- |
| willow | thin curved willow blades | broad dark-green leaves |
| blossom | cherry blossom clusters | broad leaves |
| lotus | peach blossom clusters | wisteria raceme bits |
| cypress, firefly | Spanish moss sprigs | broad teal leaves |
| maple, autumn_mist | momiji (five lobes) in crimson, orange, gold | broad ochre leaves |
| sanctuary, jade_sanctuary | bamboo blades | bamboo blades |
| grotto | fern fronds | fern fronds |
| crystal_grotto | blue-lilac fern fronds | the same |
| alpine | pine needle tufts | broad green leaves |

**Branch strip.** Cells 0–4 are bark segments from root (thick, 3–4 px) to
tip (1–2 px), painted horizontally from the cell's left-centre (0, 16) to its
right-centre (96, 16), with small twig stubs welcome; cell 5 is a spare twig.
The game rotates each cell onto a chain segment and stretches it to the
segment's length (typically 15–30 logical px), so keep bark texture coarse.

Bonus (not wired yet): `bushes-<biome>.png`, three bush silhouettes of
96 × 48 px, to replace the procedural oval bodies under the leaves.

## 3. Mid-bank layers

| File | Size | Notes |
| --- | --- | --- |
| `midbank-<biome>.png` | 1376 × 768 | transparent; drawn after the water and before the pads |

These hold reeds, rocks and shrubs standing at the far and side shores, in front
of the painted water, so the banks get depth. Keep them outside the water basin
interior. Use the backdrop as the reference and paint only shore elements.

## 4. Per-biome foregrounds

| File | Size | Notes |
| --- | --- | --- |
| `foreground-<biome>.png` | 1376 × 768 | transparent corner framing, replacing the 3 shared ones |

Follow the existing `foreground-*.png` rules: lower-left and lower-right
corners only, central water lane fully open.

## 5. Emissive masks (lights that survive night)

| File | Size | Notes |
| --- | --- | --- |
| `emissive-<backdrop>.png` | 1376 × 768 | white = emits light, black = not; grayscale or alpha |

`scripts/make-emissive.mjs` (`npm run art:emissive`) generates first-pass masks
automatically for `pond-grotto`, `pond-crystal-grotto`, `pond-sanctuary`,
`pond-jade-sanctuary`, `pond-dusk` and `pond-firefly`. Regenerated on
2026-10-25: the masks now cover the stone lantern window, every fungus cluster,
the crescent moon, the painted fireflies and the evening star (the first pass
had dropped the lantern and the fungi as oversized blobs). The other six
backdrops have no mask because the automatic key picks petals, larch boughs,
sun glitter or dithered sky instead of lights (run the script with
`--all --preview <dir>` to see why), so painted masks are most wanted for
those. A painted mask replaces the generated one for a sharper result. Cover
lanterns, glowing mushrooms, lit windows, the moon, stars and crystal glints.

What each backdrop actually contains, checked by eye on the sources:

| Backdrop | Painted light sources | Covered today by |
| --- | --- | --- |
| `pond-grotto`, `pond-crystal-grotto` | 12 fungus clusters, crescent moon, stars, fungus reflections | regenerated mask + `cap-*`, `fungi*`, `moon`, `shimmer` cycle regions |
| `pond-sanctuary`, `pond-jade-sanctuary` | stone lantern window | regenerated mask + `lantern` region |
| `pond-dusk` | evening star | regenerated mask + `star` region |
| `pond-firefly` | evening star, ~12 painted fireflies | regenerated mask + `star` region |
| `pond-blossom`, `pond-lotus` | evening star and a faint second star | `star`, `star-faint` regions (no mask) |
| `pond-alpine` | evening star | `star` region (no mask) |
| `pond-maple`, `pond-autumn-mist` | none (the bridge is unlit) | nothing to glow; a painted mask could add lanterns on the bridge only if they are painted into the backdrop too |
| `pond-mist` | none | nothing to glow |

## 6. Palette-cycle index maps (waterfalls, streams, glows)

| File | Size | Notes |
| --- | --- | --- |
| `cycle-<backdrop>-<region>.png` | 641 × 359 | lossless grayscale; full logical frame |

The gray level encodes the ramp slot: `slot = round(gray / 16)`, from 1 to 15,
and 0 means outside the region. Paint the slots as a gradient along the flow
direction, for example top to bottom for a waterfall, repeating every N slots so
the cycle reads as moving water. The colour ramps are defined in code beside
the region. Wanted regions:

| Backdrop | Region | Flow |
| --- | --- | --- |
| `pond-blossom` | `waterfall` | cliffside waterfall, falling |
| `pond-alpine` | `stream` | melt stream into the tarn |
| `pond-crystal-grotto` | `seep` | water seep down the rock wall |
| `pond-grotto` | `fungi`, `cap-*` | mushroom glow pulses (radial, one per cluster) |
| `pond-grotto` | `shimmer` | fungus and moon light on the water (sparse glints) |
| `pond-sanctuary` | `lantern` | lantern flicker (radial) |
| any with a star | `star` | twinkle (radial) |
| any with a reflection band | `glitter`, `sheen` | sun, alpenglow or fog light on far water (sparse glints) |

The regions wired in code, with their logical rectangles, are listed in the
design (`openspec/changes/visual-envelope/design.md`, D4). `pond-lotus` shares
the blossom regions, `pond-crystal-grotto` the grotto ones, `pond-firefly` the
dusk ones, `pond-autumn-mist` the maple ones and `pond-jade-sanctuary` the
sanctuary ones; a painted map named for any of those backdrops and regions
replaces the procedural one.

Until a painted map exists, procedural regions approximate these features.

## 7. Regenerations (approved 2026-10-25)

The owner approved regenerating existing assets wherever it improves the
result.

- `frog-meadow-sheet.png` and `frog-teal-sheet.png`: repaint the same 8 poses
  on a **true 42×36 pixel grid** per cell, with hard edges, no anti-aliasing,
  and the styleguide palette only. Scale each cell up by a whole number inside
  the 1031×521 sheet. This stops the shimmer when frogs scale with depth, and
  it lets the depth sheets in §1 match.
- Backdrops whose glow masks didn't key cleanly (`pond-blossom`, `pond-maple`,
  `pond-lotus`, `pond-alpine`, `pond-mist`, `pond-autumn-mist`): no repaint
  needed. A painted `emissive-*.png` (§5) is enough.
- Backdrop and foreground re-exports at a whole-number scale: **done**
  (2752 × 1536 = 2 × source, made by script, no repaint needed). Future painted
  art should follow the size rule under Shared rules.

## 8. Not yet wired (wanted later)

- `insects-night-sheet.png`: moth, mayfly and glow-beetle wing frames (8×8
  effective pixels, 4 frames each). Insects are currently drawn procedurally.
- `insects-scenery-sheet.png` (optional): the signature species of each
  scenery, 8×8 effective pixels, 4 frames each, one row per species, in the
  order of `InsectSpecies.table` (`lib/game/insect_species.dart`). The
  procedural sprites in `_bug` stay as the fallback and set the read of each:
  - `waterstrider`: thin dark body, four splayed legs, surface dimples
    (willow, lotus, blossom, sanctuary, jade_sanctuary).
  - `whirligig`: glossy black bead with a bronze glint, faint wake (willow,
    cypress, firefly).
  - `damselfly`: level needle body, blue or emerald variant, paired folded
    wings (lotus, blossom, jade_sanctuary).
  - `bee`: amber and black stripes, wing blur (blossom, sanctuary,
    jade_sanctuary, alpine).
  - `cicada`: stout olive body, wide clear wings laid back (maple, sanctuary,
    jade_sanctuary).
  - `cricket`: dark brown hopper, long antennae, bent hind leg (maple,
    autumn_mist, night).
  - `katydid`: leaf-green upright wings, antennae forward (cypress, firefly,
    night).
  - `cranefly`: thread body, dangling legs, two slow wings (autumn_mist,
    cypress).
  - `stonefly`: slate body, flat wings, two tail filaments (alpine).
  - `cavecricket`: pale humpback, very long antennae (grotto, crystal_grotto).
  - `jewelbeetle`: metallic jade carapace with a travelling glint
    (jade_sanctuary).
  - `fungusgnat`: a speck with a faint cyan halo (crystal_grotto).
- Whole-number re-exports: done (§7).
