# Asset Requests: Visual Envelope

This list is for agents or artists who can paint images. Every asset below is
**optional**. The game looks for each one by filename in `assets/images/`. If a
file is missing or fails to decode, the game draws a procedural fallback, so you
can deliver them in any order and each one appears as soon as it ships.

The registry of optional filenames lives in code (see
`lib/game/optional_assets.dart` once `work/pond-layers` lands). Keep this file
and that registry in sync.

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
- Prime dimensions are a house convention. Keep the sizes given below.

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
| `canopy-<biome>.png` | 2557 × 719 | top edge, full width |

These are drawn above the frogs and insects, sway with wind, and are graded
with the time of day. The layer maps 1:1 onto the top half of the 2557 × 1439
frame. **In the central 50 % of the width (x 640–1918), keep every row below
y = 431 transparent**, because that is 30 % of frame height and the frogs' high
arcs pass there. Hanging elements may reach the bottom of the layer in the left
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

## 3. Mid-bank layers

| File | Size | Notes |
| --- | --- | --- |
| `midbank-<biome>.png` | 2557 × 1439 | transparent; drawn after the water and before the pads |

These hold reeds, rocks and shrubs standing at the far and side shores, in front
of the painted water, so the banks get depth. Keep them outside the water basin
interior. Use the backdrop as the reference and paint only shore elements.

## 4. Per-biome foregrounds

| File | Size | Notes |
| --- | --- | --- |
| `foreground-<biome>.png` | 2557 × 1439 | transparent corner framing, replacing the 3 shared ones |

Follow the existing `foreground-*.png` rules: lower-left and lower-right
corners only, central water lane fully open.

## 5. Emissive masks (lights that survive night)

| File | Size | Notes |
| --- | --- | --- |
| `emissive-<backdrop>.png` | 2557 × 1439 | white = emits light, black = not; grayscale or alpha |

`scripts/make-emissive.mjs` generates first-pass masks automatically. A painted
mask replaces the generated one for a sharper result. Cover lanterns, glowing
mushrooms, lit windows, the moon, stars and crystal glints.

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
| `pond-grotto` | `fungi` | mushroom glow pulse (radial) |
| `pond-sanctuary` | `lantern` | lantern flicker (radial) |

Until a painted map exists, procedural regions approximate these features.

## 7. Not yet wired (wanted later)

- `insects-night-sheet.png`: moth, mayfly and glow-beetle wing frames (8×8
  effective pixels, 4 frames each). Insects are currently drawn procedurally.
- Integer-scaled re-exports of every backdrop at 2752 × 1536 (2 × 1376 × 768),
  so every source pixel maps to a whole number of screen pixels.
