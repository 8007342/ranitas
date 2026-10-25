# Original Ranitas Art & Styleguide

Generated with the built-in image generation tool for this project. Source PNGs
are retained in `art/source/`; the Flutter bundle includes lossless/high-res WebP
exports from `assets/images/`. Rebuild exports with `node scripts/prepare-art.mjs`.

The visual-envelope delivery adds twelve biome-specific canopy, mid-bank,
foreground, leaf-atlas and branch-strip sets, plus regenerated side-view frogs
and new depth sheets. See [GENERATION.json](GENERATION.json) for the prompt set
and [ASSET_REQUESTS.md](ASSET_REQUESTS.md) for delivery details. Validate their
dimensions, alpha, clear lanes and lookup data with `npm run check:art`.
Leaf atlases remain 256 × 128, branch strips 576 × 32, and numeric cycle maps
641 × 359; only scenic layers and emissive masks receive the 2× export.

All exported scenic backdrops (`pond-*.webp`) and foreground parallax overlays
(`foreground-*.webp`) are **2752 × 1536 pixels**: exactly 2× their 1376 × 768
sources, so each source pixel is an exact 2 × 2 block. Earlier exports used a
prime 2557 × 1439, which baked a non-integer 1.858× nearest-neighbour resample
and uneven pixel widths into the files (see `docs/visual-envelope.md`). Frog
character sheets (`frog-*-sheet.webp`) are **1031 × 521 pixels**. The
procedural animated layer uses a **641 × 359** logical canvas. Scaling to the
screen is explicit and nearest-neighbour.

See [STYLEGUIDE.md](STYLEGUIDE.md) for the complete visual architecture, color
palettes, and 10-state frog animation specification.

## Scenic Backdrop Prompt Set (16:9 Widescreen Landscape)

Common production direction: exquisite detailed hand-placed crisp square pixel
art reminiscent of 1990s adventure-game scenery; widescreen landscape source;
open reflective pond in central and lower 60%; richly planted left/right banks
and framing upper-corner branches; layered distant hills; jewel teal, indigo,
lavender, amber and peach; peaceful still atmosphere. No frogs, animals,
typography, UI, or watermarks. Frogs and wildlife are independently animated
layers.

- `pond-dusk` (`willow` biome): quiet magical freshwater bog at blue hour;
  peach-pink horizon; indigo mountains and distant willow trees; lavender sky
  with delicate clouds and a single star; mossy shores, water lilies, reeds and
  flowers at left and right edges.
- `pond-mist` (`cypress` biome): cypress freshwater bayou at misty blue dawn;
  Spanish moss; layered indigo mountains; warm pale apricot horizon; dark
  turquoise reeds, wet rocks and water lilies; moody lavender, teal and moss
  palette.
- `pond-blossom` (`blossom` biome): spring woodland pond at lavender-blue
  twilight; peach sunset horizon; framing cherry branches covered in tiny pink
  blossom clusters; gnarled trunks, ferny moss banks, flowers; distant flowering
  woodland and cliffside waterfall; rose-gold, teal, lavender and indigo palette.
- `pond-maple` (`maple` biome): autumn Japanese maple pond at warm amber-violet
  dusk; overarching crimson and gold momiji branches in upper corners; distant
  vermilion wooden bridge in cedar mist; mossy stepping stones and floating
  maple leaves at outer shores.
- `pond-sanctuary` (`sanctuary` biome): tranquil bamboo and stone-lantern
  sanctuary pond at twilight; mossy stone *tōrō* lantern with warm amber glow on
  the left bank; emerald bamboo stalks and leaves framing upper corners; distant
  pagoda silhouette against indigo hills; lotus buds and river stones.
- `pond-grotto` (`grotto` biome): enchanted limestone ravine grotto opening to a
  starry twilight sky through a natural rock arch; hanging vines, ferns, and
  glowing cyan, violet, and amber bioluminescent mushrooms along rocky banks;
  glass-clear deep indigo-teal pond.
- `pond-alpine` (`alpine` biome): high-mountain glacial meadow tarn at alpenglow
  twilight; framing pine and golden larch boughs; granite boulders, cushion
  moss, and alpine lupines and edelweiss on outer shores; snow-dusted peaks
  reflecting in turquoise water.

## Foreground Parallax Overlays (16:9 Transparent Alpha)

- `foreground-marsh`: genuine transparent foreground overlay; cattails, mossy
  stones, ferns, cream/mauve flowers and two pink lotus blooms around lower
  left and right corners with an open widescreen center.
- `foreground-blossom`: genuine transparent foreground overlay; mossy garden
  rocks, iris blades, Japanese ferns, fallen blossom/maple petals, and blooming
  pink/gold water lilies at lower corners.
- `foreground-grotto`: genuine transparent foreground overlay; wet mossy
  limestone rocks, curling fern fronds, glowing cyan/violet bioluminescent
  mushroom clusters, and luminous teal lotus pads at lower corners.

## Hero Frog Character Sheets (Hybrid Sprite Atlas + Pixel-Matrix Animation)

- `frog-meadow-sheet`: Frog 0 (Player frog) 4×2 pose sheet — emerald-meadow tree
  frog with lime-gold highlights, cream belly, coral toe pads, and golden eyes.
- `frog-teal-sheet`: Frog 1 (Companion JEV frog) 4×2 pose sheet — jewel
  turquoise-teal pond frog with seafoam stripes, honey belly, and amber eyes.
