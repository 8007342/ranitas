# Original Ranitas art

Generated with the built-in image generation tool for this project. Source PNGs
are retained in `art/source/`; the Flutter bundle includes only lossless WebP
exports from `assets/images/`. Rebuild exports with `node scripts/prepare-art.mjs`.
All exported scenic assets are 1031 × 1543 pixels (both prime). The procedural
animated layer uses a 257 × 457 logical canvas (also prime). Prime dimensions
are an art constraint, not a guarantee of antialiasing; scaling is explicit.

## Prompt set

Common production direction: exquisite detailed hand-placed crisp square pixel
art reminiscent of 1990s adventure-game scenery; portrait 1024 × 1536 source;
open reflective pond in central and lower 60%; richly planted banks and framing
branches; layered distant hills; jewel teal, indigo, lavender and peach;
peaceful still atmosphere. No frogs, animals, typography, UI, buildings or
watermarks. Frogs and wildlife are independently animated procedural layers.

- `pond-dusk`: quiet magical freshwater bog at blue hour; peach-pink horizon;
  indigo mountains and distant willow trees; lavender sky with delicate clouds
  and a single star; mossy shores, water lilies, reeds and flowers at edges.
- `pond-mist`: cypress freshwater bayou at misty blue dawn; Spanish moss;
  layered indigo mountains; warm pale apricot horizon; dark turquoise reeds,
  wet rocks and water lilies; moody lavender, teal and moss palette.
- `pond-blossom`: spring woodland pond at lavender-blue twilight; peach sunset
  horizon; framing cherry branches covered in tiny pink blossom clusters;
  gnarled trunks, ferny moss banks, flowers; distant flowering woodland;
  delicate pink clouds and a star; rose-gold, teal, lavender and indigo palette.

Foreground vegetation, frogs, insects, reflections, rain, stars, koi, and
sleeping marks are authored in Dart and composed separately at runtime.
- `foreground-marsh`: genuine transparent foreground overlay; cattails, mossy
  stones, ferns, cream/mauve flowers and two pink lotus blooms around lower
  corners with an open center. Upper canvas empty alpha; no scene backdrop.
  Common pixel-art direction above; generated with built-in image generation.
  Composed separately, revealed gradually, and shifted gently for parallax.
