# Ranitas Visual & Animation Styleguide (Landscape High-Res Edition)

## 1. Canvas & Aspect Ratio Architecture

Ranitas is designed for widescreen high-resolution displays in **landscape (~16:9)** orientation while preserving crisp, deliberate pixel-art scaling through prime-dimensioned surfaces:

| Layer | Dimensions (px) | Primality | Aspect Ratio | Purpose |
| --- | --- | --- | --- | --- |
| **Scenic Backdrop Exports** (`assets/images/pond-*.webp`) | `2557 × 1439` | Both prime | `1.7769:1` (~16:9) | Lossless/high-density WebP widescreen background art |
| **Foreground Parallax Overlays** (`assets/images/foreground-*.webp`) | `2557 × 1439` | Both prime | `1.7769:1` (~16:9) | Alpha-masked corner vegetation & botanical framing |
| **Frog Character Sprite Sheets** (`assets/images/frog-*-sheet.webp`) | `1031 × 521` | Both prime | `4 × 2` pose atlas | 8-pose reference & hybrid sprite atlas per frog |
| **Logical Procedural Canvas** (`PondRenderer`) | `641 × 359` | Both prime | `1.7855:1` (~16:9) | Crisp pixel-art actor, water, motif, & weather canvas |

- **Explicit Pixel Scaling**: All `Canvas.drawImageRect` and procedural primitives render with `FilterQuality.none` and `isAntiAlias = false`.
- **Stage Layout in Normalized Coordinates `(0..1, 0..1)`**:
  - **Sky & Distant Horizon**: `y = 0.00 .. 0.40`
  - **Far Bank & Reflections**: `y = 0.36 .. 0.54`
  - **Open Hunting Airspace (Bugs)**: `x = 0.04 .. 0.96`, `y = 0.12 .. 0.65`
  - **Home Lily Pad 0 (Left, Player Frog)**: `x = 0.27`, `y = 0.69`
  - **Home Lily Pad 1 (Right, Companion Frog)**: `x = 0.73`, `y = 0.72`
  - **Foreground Parallax Framing**: Lower left (`x = 0.00 .. 0.24`) and lower right (`x = 0.76 .. 1.00`), `y = 0.32 .. 1.00`, leaving the central water lane completely unobstructed.

---

## 2. Scene Styles & Biome Motifs (7 Biomes)

Every session deterministically selects one of seven cohesive landscape biomes from its seed, pairing each backdrop with a matching foreground parallax overlay and procedural environmental motif:

| Biome ID | Scenic Asset | Foreground Overlay | Palette & Signature Motifs | Procedural Motif Accents |
| --- | --- | --- | --- | --- |
| `willow` | `pond-dusk.webp` | `foreground-marsh.webp` | Jewel teal, indigo mountains, peach-pink blue-hour horizon, cascading willow boughs | Swaying cattails, willow leaf ripples, evening star |
| `cypress` | `pond-mist.webp` | `foreground-marsh.webp` | Pale apricot dawn, misty bayou indigo, dark turquoise reeds, gnarled cypress knees | Draping Spanish moss strands, low bayou mist bands |
| `blossom` | `pond-blossom.webp` | `foreground-blossom.webp` | Rose-gold & lavender twilight, sakura pink clusters, distant cliff waterfall | Drifting cherry blossom petals on air and water |
| `maple` | `pond-maple.webp` | `foreground-blossom.webp` | Crimson & amber momiji maple canopy, distant vermilion wooden bridge, cedar mist | Floating autumn maple leaves & warm amber reflections |
| `sanctuary` | `pond-sanctuary.webp` | `foreground-blossom.webp` | Emerald bamboo grove, mossy stone *tōrō* lantern, distant pagoda silhouette | Warm flickering stone-lantern reflection on water, lotus blooms |
| `grotto` | `pond-grotto.webp` | `foreground-grotto.webp` | Deep subterranean indigo-teal ravine, natural rock arch, glowing cyan/violet fungi | Bioluminescent mushroom shore glow & drifting luminous spores |
| `alpine` | `pond-alpine.webp` | `foreground-marsh.webp` | Glacier-turquoise tarn, snow-dusted alpenglow peaks, granite boulders, lupines | Crisp crystalline water shimmer, alpine wildflowers & pine needles |

---

## 3. Hero Frog Character Sheets & 10-State Animation System

The two frogs are the stars of the show and feature a **hybrid rendering pipeline** combining high-resolution generated sprite sheet atlases (`frog-meadow-sheet.webp` and `frog-teal-sheet.webp`) with high-density pixel-art pose matrices and procedural micro-expressions.

### Character Profiles
1. **Frog 0 — "Rana Verde" (Player-Controlled Meadow Tree Frog)**:
   - **Dorsal Palette**: Deep forest outline (`#143534`), emerald shadow (`#3d7a52`), meadow green midtone (`#6db364`), sunlit lime highlight (`#a8db74`), golden-lime spots (`#cde88b`).
   - **Ventral & Accents**: Warm cream belly (`#f4eec1`) with soft golden throat sac (`#e6d88a`), coral-orange toe pads (`#ee8468`), rosy cheek blush (`#e58f8e`), large glossy amber-gold eyes (`#ffeaad`) with vertical obsidian pupils.
2. **Frog 1 — "Rana Jade" (JEV Companion Pond Frog)**:
   - **Dorsal Palette**: Deep abyssal teal outline (`#13303a`), slate-teal shadow (`#2e6b72`), jewel turquoise midtone (`#4ea69a`), seafoam-mint highlight (`#89d6be`), pale aqua dorsolateral stripes (`#b6ebd4`).
   - **Ventral & Accents**: Pale honey-cream belly (`#efe8bd`) with pearlescent throat sac (`#d6e5b8`), warm peach-coral toe pads (`#e29578`), lavender-rose cheek blush (`#d995a8`), large warm golden eyes (`#ffe39f`).

### Animation States & Pose Transitions
Each frog transitions smoothly across **10 distinct visual states** driven by deterministic `FrogState` properties in `PondModel`:

1. **`idle` (Perched & Breathing)**:
   - Gentle sinusoidal ribcage/back breathing, periodic rhythmic throat-sac vocalization pulse, subtle eye-tracking toward the nearest live bug, and natural double-blinks.
2. **`charging` (Crouch / Anticipation)**:
   - Triggered while holding pointer/key (or just before launch): body compresses low onto the lily pad, hind knees tuck high and wide, front paws grip the pad edge, eyes narrow in focused anticipation.
3. **`launching` (Takeoff Push, `jumpPhase < 0.18`)**:
   - Explosive upward extension at liftoff: torso angles ~40° toward the target pad, hind legs kick straight back with webbed toes splayed, leaving a subtle pad depresión and water ring.
4. **`ascending` (Upward Arc, `0.18 <= jumpPhase < 0.44`)**:
   - Streamlined aerodynamic arc: arms reach forward toward the flight path, hind legs trail smoothly behind, dorsal highlights catch the sky light.
5. **`chomping` (Mid-Air Apex & Bug Catch, `tongue > 0` or `0.44 <= jumpPhase < 0.58` during catch)**:
   - Wide-open mouth (`#8f3247` cavity with `#e87a90` tongue base), eyes wide with excitement, elastic sticky-tipped pixel tongue whipping out to the target insect (`tongueX, tongueY`) with a dew-drop tip and catch sparkle.
6. **`falling` (Descending Arc, `0.58 <= jumpPhase < 1.0`)**:
   - Parachuting descent: limbs spread outward, webbed toes and coral/peach toe pads flared downward to spot the landing lily pad, belly curved softly.
7. **`landing` (Pad Impact Squash, `landingTimer > 0`)**:
   - Upon touching down on the destination lily pad (`0.28s` window): elastic squash-and-settle posture, wide planted feet, gentle concentric water ripple around the lily pad.
8. **`swallowing` (Post-Landing Bug Gulp, `swallowTimer > 0`)**:
   - Triggered automatically when a frog lands after catching one or more bugs in mid-air (`0.85s` sequence):
     - **Phase A (Cheek Puff)**: Cheeks puff out wide (`+3px` lateral bulge), mouth tightly closed in a satisfied curve, tiny bug wing/leg silhouette briefly visible at the lip corner.
     - **Phase B (Throat Bulge & Gulp)**: The vocal/throat sac inflates into a round golden-cream bulge as the frog tilts its head up and gulps (`y - 1.5px` head bob).
     - **Phase C (Happy Squint)**: Eyes curve into happy `^ ^` crescents with a rosy cheek glow as the throat settles.
9. **`swimming` (Belly-Flop Splash & Frog-Kick Recovery)**:
   - Initial crown splash droplets (`bellyFlop > 0`), followed by a submerged-body frog-kick cycle: eyes and nose poking above the water line, rhythmic alternating hind-leg breaststroke kicks (`sin(swimAge * 14)`), and trailing V-shaped wake ripples back to the pad.
10. **`sleeping` (Synchronized Rest)**:
    - Curled loaf posture on the home lily pad: limbs tucked snugly against the body, eyelids closed with peaceful curved lashes, slow deep breathing, and floating pixel `z Z` marks.
