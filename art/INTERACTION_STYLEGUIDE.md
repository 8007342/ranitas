# Ranitas Interaction, Lily Pad Physics & Composable Layering Styleguide

This specification defines the physical interaction model, dynamic kinematic response systems, 6-tier composable rendering architecture, and fullscreen responsive viewport layout for **Ranitas**.

---

## 1. Architectural Overview & Design Philosophy

Ranitas creates an organic, living pond ecosystem where every frog action—from the coiled anticipation of a jump, through mid-air insect strikes, to dynamic pad touchdowns and water missteps—creates tangible physical reactions in the environment.

```
       [Frog Launch Push]               [Mid-Air Arc]               [Impact Touchdown]
               │                              │                              │
               ▼                              │                              ▼
      Pad Recoil & Dip                        │                     Landing Zone Analysis
   (v_y > 0, -tilt, ripple)                   │                (offset_x, offset_y, momentum)
                                              │                              │
                                              ▼                              ▼
                                      Mid-Air Chomps                ┌──────────────────┐
                                   (tongue, catch sparkle)          │ Zone A: Center   │──> Cup Dip + 360° Ring
                                                                    │ Zone B: Mid-Pad  │──> Pitch Tilt + Plum Underside
                                                                    │ Zone C: Leaf Edge│──> Lobe Fold + Splash Arc
                                                                    └──────────────────┘
```

The interaction design adheres to four core tenets:
1. **Mechanical Tangibility**: Lily pads are floating elastic biological membranes, not rigid platforms. They pitch, cup, fold, submerge, and ripple in direct proportion to frog mass, impact velocity, and strike location.
2. **Deterministic Physics**: All spring-damper equations and kinematic systems evaluate within `PondModel`'s fixed 60 Hz substeps (`_tick(dt)`), ensuring 100% replayability and cross-platform synchronization from the scene seed.
3. **Composable Depth Layering**: 6 strict render tiers delineate background atmosphere, deep water, submerged fauna (Koi & Tadpoles), refractive water surface ripples, floating actors (pads & frogs), and foreground parallax framing.
4. **Seamless Viewport Coverage**: Zero letterbox bars on any display format (16:9, 16:10, 21:9 ultrawide, 32:9 super-ultrawide, tablets, or mobiles) through dynamic horizon bleed and cover projection.

---

## 2. Lily Pad Physical Response & Edge-Landing Kinematics (`PadState`)

The pond hosts two primary lily pads (`pads[0]` for left frog/Rana Verde, `pads[1]` for right frog/Rana Jade) positioned at normalized anchors:
- **Pad 0**: `x = 0.27`, `y = 0.69`, base radius `rx = 36px`, `ry = 11px` (aspect ratio 3.27:1)
- **Pad 1**: `x = 0.73`, `y = 0.72`, base radius `rx = 38px`, `ry = 12px` (aspect ratio 3.17:1)

### 2.1 Pad State Variables & Spring Oscillators

Each pad maintains a dynamic `PadState` tracking multi-axis displacement from hydrostatic equilibrium:

```dart
class PadState {
  PadState(this.index, this.homeX, this.homeY, this.radiusX, this.radiusY)
      : x = homeX,
        y = homeY;

  final int index;
  final double homeX, homeY;
  final double radiusX, radiusY;

  // Hydrostatic displacement & spring state
  double x, y;
  double dipY = 0.0;              // Vertical displacement in logical pixels (+ is down)
  double dipVelocity = 0.0;      // Vertical velocity (px/s)
  double tiltAngle = 0.0;         // Pitch rotation in radians (+ tilts right rim down)
  double tiltVelocity = 0.0;     // Angular velocity (rad/s)
  double driftX = 0.0;            // Lateral slide offset in pixels
  double driftVelocity = 0.0;    // Lateral velocity (px/s)

  // Edge folding & surface water wash (Zone C)
  double edgeFold = 0.0;          // Fold progression (0.0 flat .. 1.0 maximum curl)
  double edgeFoldSide = 0.0;      // -1.0 for left lobe fold, +1.0 for right lobe fold
  double waterWashAlpha = 0.0;    // Translucent wash tongue opacity (0.0 .. 0.7)

  // Dewdrop surface bead bounce
  double dewdropBounce = 0.0;     // Vertical bead displacement (px)
  double dewdropVelocity = 0.0;  // Dewdrop bounce velocity (px/s)
}
```

#### Harmonic Equations of Motion (Evaluated at 60 Hz)

1. **Vertical Hydrostatic Bobbing (`dipY`)**:
   $$\ddot{y} = -k_y \cdot dipY - c_y \cdot dipVelocity$$
   $$\text{Parameters: } k_y = 145.0\text{ s}^{-2},\quad c_y = 15.5\text{ s}^{-1}$$
   *Behavior*: Damped harmonic oscillation settling smoothly in ~0.55s without excessive oscillation.

2. **Angular Pitch Tilt (`tiltAngle`)**:
   $$\ddot{\theta} = -k_\theta \cdot tiltAngle - c_\theta \cdot tiltVelocity$$
   $$\text{Parameters: } k_\theta = 190.0\text{ s}^{-2},\quad c_\theta = 18.0\text{ s}^{-1}$$
   *Behavior*: Restores pad to horizontal plane within ~0.50s after asymmetric landing impulses.

3. **Lateral Water Drag & Drift (`driftX`)**:
   $$\ddot{x} = -k_x \cdot driftX - c_x \cdot driftVelocity$$
   $$\text{Parameters: } k_x = 65.0\text{ s}^{-2},\quad c_x = 12.0\text{ s}^{-1}$$
   *Behavior*: Pad shifts up to 3–6px laterally under foot push and elastically returns to anchor.

4. **Edge Lobe Elastic Uncurling (`edgeFold`)**:
   $$edgeFold(t + \Delta t) = edgeFold(t) \cdot \exp\left(-\frac{\Delta t}{\tau_{\text{fold}}}\right)$$
   $$\text{Parameter: } \tau_{\text{fold}} = 0.175\text{ s (full recovery in } \approx 0.65\text{s)}$$
   $$waterWashAlpha = (edgeFold \cdot 0.70).clamp(0.0, 1.0)$$

5. **Dewdrop Surface Bead Bounce (`dewdropBounce`)**:
   $$\ddot{y}_{\text{drop}} = -k_{\text{drop}} \cdot dewdropBounce - c_{\text{drop}} \cdot dewdropVelocity + 0.35 \cdot \ddot{y}_{\text{pad}}$$
   $$\text{Parameters: } k_{\text{drop}} = 310.0\text{ s}^{-2},\quad c_{\text{drop}} = 22.0\text{ s}^{-1}$$

---

### 2.2 Impact Offset & Normalization

Upon frog touchdown in `_land(FrogState frog)`, the exact landing coordinate $(frogX, frogY)$ is projected onto the target pad:

```dart
final pad = pads[frog._targetLeaf];
final normRx = pad.radiusX / PondRenderer.logicalWidth;
final normRy = pad.radiusY / PondRenderer.logicalHeight;

final impactOffsetX = ((frog.x - pad.x) / normRx).clamp(-1.0, 1.0);
final impactOffsetY = ((frog.y - pad.y) / normRy).clamp(-1.0, 1.0);
final impactOffset = math.sqrt(impactOffsetX * impactOffsetX + impactOffsetY * impactOffsetY).clamp(0.0, 1.0);
```

#### Impact Momentum Multiplier ($m_{\text{imp}}$)
The impulse applied depends on the jump height category:
- **`tap` jump** (low flight, short arc): $m_{\text{imp}} = 0.65$
- **`low` jump** (standard flight arc): $m_{\text{imp}} = 1.00$
- **`high` jump** (high trajectory, steep landing angle): $m_{\text{imp}} = 1.55$

---

### 2.3 Landing Zones Specification

```
                      Zone A: Center (|offset| < 0.35)
               ┌──────────────────────────────────────────────┐
               │  - Symmetric downward cup dip (dipY > 0)     │
               │  - Concentric 360° expanding ripples         │
               │  - Dewdrop pearl bounce                      │
               └──────────────────────────────────────────────┘
                                     │
                                     ▼
                   Zone B: Mid-Pad (0.35 <= |offset| < 0.62)
               ┌──────────────────────────────────────────────┐
               │  - Directional pitch tilt (tiltAngle)        │
               │  - Opposite rim lifts (1–2px plum underside) │
               │  - Moderate lateral drift                    │
               │  - Asymmetric ripple emission (biased)       │
               └──────────────────────────────────────────────┘
                                     │
                                     ▼
                    Zone C: Edge / Rim (|offset| >= 0.62)
               ┌──────────────────────────────────────────────┐
               │  - Leaf Edge Fold (edgeFold -> 1.0)          │
               │  - Submerged rim + translucent water tongue  │
               │  - Directional Edge Splash (5–9 droplets)    │
               │  - Frothy foam crescent                      │
               │  - High-amplitude directional ripples        │
               │  - Elastic uncurl recovery (0.65s)           │
               └──────────────────────────────────────────────┘
```

#### Zone A — Center Landing (`|offset| < 0.35`)
When the frog lands squarely in the central sweet spot:
1. **Vertical Impulse**:
   `pad.dipVelocity += 16.0 * m_imp;`
   `pad.tiltVelocity += impactOffsetX * 1.2 * m_imp;` // Minimal incidental tilt
2. **Visual Pad Cup-Dip**:
   During the first 0.15s of touchdown, the pad's inner disc compresses down by an extra 1.5px relative to its outer rim, creating a slight concave "cup" deflection.
3. **Dewdrop Scatter**:
   `pad.dewdropVelocity += 26.0 * m_imp;`
   Dewdrops sitting on leaf veins spring into the air, reaching +2.5px peak altitude before settling.
4. **Surface Wave Emission**:
   Triggers a symmetric, 360° concentric circular ripple ring from pad edge into open water:
   - Initial radius: $R_0 = pad.radiusX$
   - Propagation speed: $v_r = 52\text{ px/s}$
   - Amplitude: $A = 1.0 \times m_{\text{imp}}$

#### Zone B — Mid-Pad Landing (`0.35 <= |offset| < 0.62`)
Landing between the center and rim induces pronounced torque:
1. **Kinematic Tilt & Drift**:
   `final dir = impactOffsetX >= 0 ? 1.0 : -1.0;`
   `pad.dipVelocity += 11.0 * m_imp;`
   `pad.tiltVelocity += dir * 6.5 * m_imp;`
   `pad.driftVelocity += dir * 4.0 * m_imp;`
2. **Opposite Rim Lift & Plum Underside Reveal**:
   As the impact side depresses, the opposite rim rises by $\Delta h = pad.radiusX \cdot \sin(|pad.tiltAngle|)$.
   - When $\Delta h \ge 1.2\text{px}$, the underside of the pad becomes visible along the lifted rim.
   - **Plum Underside Palette**:
     - Outline / shadow seam: `#3d1f2c` (`0xff3d1f2c`)
     - Rich reddish-plum underside flesh: `#5a3344` (`0xff5a3344`)
     - Subsurface translucent rim edge: `#7a4457` (`0xff7a4457`)
   - Thickness: 1–2px crescent curve tracing the outer rim perimeter.
3. **Biased Ripple Emission**:
   Emits ripples with directional bias: 65% wave energy directed toward the impact side, 35% trailing off the lifted side.

#### Zone C — Edge / Rim Landing (`|offset| >= 0.62`): Leaf Edge Fold & Splash
An extreme foot landing on the soft outer lobe curls the flexible leaf rim underwater:
1. **Edge Fold Dynamics**:
   `pad.edgeFold = (pad.edgeFold + 0.85 * m_imp).clamp(0.0, 1.0);`
   `pad.edgeFoldSide = impactOffsetX >= 0 ? 1.0 : -1.0;`
   `pad.dipVelocity += 7.5 * m_imp;`
   `pad.tiltVelocity += pad.edgeFoldSide * 8.8 * m_imp;`
   `pad.driftVelocity += pad.edgeFoldSide * 6.0 * m_imp;`
2. **Water Tongue Wash**:
   Because the folded lobe dips 2–3px below the pond surface plane, surface water spills over the leaf edge:
   - Rendered as a translucent teal-tinted wash overlay: `#85d4cb` at alpha `waterWashAlpha` ($0.0 \dots 0.65$).
   - Sweeps inward over the folded lip across a 4–8px elliptical tongue, then recedes as `edgeFold` uncurls over 0.65s.
3. **Directional Edge Splash**:
   The impact displaces a burst of water droplets and foam into the pond:
   - **Droplet Count**: 5 to 9 discrete single-pixel / 2-pixel water beads.
   - **Velocity**:
     $$v_x = pad.edgeFoldSide \cdot (35 + 30 \cdot \text{rand})$$
     $$v_y = -(32 + 38 \cdot \text{rand})$$
     $$\text{Gravity } g = 240\text{ px/s}^2$$
   - **Foam Crescent**: A thin, 2–3px wide frothy foam arc (`0xd5ffffff` fading to `0x00ffffff` over 0.35s) clinging to the folded rim.
4. **Eccentric Directional Surface Waves**:
   Spawns an eccentric ripple wavefront ($e = 0.68$) propagating rapidly away from the folded edge into open water ($v_r = 68\text{ px/s}$, amplitude $A = 1.6 \times m_{\text{imp}}$).

---

### 2.4 Takeoff Recoil Kinematics (`_launch`)

Launching is an explosive push: the frog's hind leg webbed feet push downward and backward against the pad surface.
When `_launch(FrogState frog, String action)` executes:
1. **Opposite Downward Kick**:
   `pad.dipVelocity += 9.5 * m_launch;` // Downward kick
2. **Angular Pitch Kick**:
   Torque pushes the pad away from the launch flight trajectory:
   `final jumpDir = frog._toX >= frog._fromX ? 1.0 : -1.0;`
   `pad.tiltVelocity -= jumpDir * 3.8 * m_launch;`
3. **Takeoff Ripple Ring**:
   A crisp, moderate concentric ripple ring ($A = 0.55 \times m_{\text{launch}}$, $v_r = 46\text{ px/s}$) originates at the frog's liftoff stance position.

---

### 2.5 Belly-Flop Kinematics & Pad Wake Coupling

When an agitated frog misses the pad due to wind gusts or over-tapping (`frog.swimming = true`, `frog.bellyFlop = 1`):
1. **Crown Splash Arc**:
   Erupts at $(splashX, splashY)$ with 12–16 spray droplets radiating upward in a parabolic crown:
   $$v_x = \pm(20 \dots 65)\text{ px/s},\quad v_y = -(45 \dots 90)\text{ px/s}$$
2. **Major Surface Wake**:
   Spawns two high-amplitude concentric ripples ($A = 1.8$, expansion speed $v_r = 78\text{ px/s}$).
3. **Pad Wake Coupling**:
   When the belly-flop ripple wavefront reaches the nearest lily pad ($d < 85\text{px}$), the wave lifts and drops the pad:
   $$\Delta dipVelocity = \sin(t_{\text{wave}}) \cdot 6.0 \cdot \left(1.0 - \frac{d}{85}\right)$$
   The pad gently rocks in sympathy with the frog's struggle.

---

## 3. Composable Multi-Layer Water, Ripples & Wildlife Architecture

To achieve authentic depth, specular luminescence, and seamless blending, Ranitas organizes rendering into **6 composable tiers**. Each tier renders strictly from back to front:

```
┌────────────────────────────────────────────────────────────────────────┐
│  Tier 5: Foreground Parallax Overlay & Weather Particles                │
│          (Framing reeds, cattails, momiji boughs, rain, mist, spores)  │
├────────────────────────────────────────────────────────────────────────┤
│  Tier 4: Floating Actors, Pads, Blooms & Surface Insects               │
│          (Lily pads, 3D rim, plum underside, fold, frogs, lotus)       │
├────────────────────────────────────────────────────────────────────────┤
│  Tier 3: Water Surface Plane & Expanding Refractive Ripples            │
│          (Specular sky sheen, dual-ring ripple highlights & shadows)   │
├────────────────────────────────────────────────────────────────────────┤
│  Tier 2: Sub-Surface Aquatic Wildlife                                  │
│          (Kohaku, Yamabuki, Showa, Asagi Koi & darting Tadpoles)       │
├────────────────────────────────────────────────────────────────────────┤
│  Tier 1: Deep Pond Water Base & Caustic Ribbons                        │
│          (Depth gradient absorption, caustic ribbons, submerged silt)  │
├────────────────────────────────────────────────────────────────────────┤
│  Tier 0: Full-Bleed Scenic Backdrop & Sky Gradient                     │
│          (Mountains, clouds, celestial bodies, atmospheric veil)       │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Tier 0: Scenic Full-Bleed Backdrop & Sky Atmosphere
- **Source Art**: Lossless WebP scenic backdrops (`assets/images/pond-*.webp`, 2752 × 1536 px, exactly 2× the 1376 × 768 sources).
- **Fallback Procedural Scenery**: 3-layer parallax mountain ridges, distant pine/willow tree treeline, and gradient sky.
- **Atmospheric Veil**: Transparent day/night color modulation:
  - Deep blue night wash: `#101f48` at alpha $0.06 + 0.60 \cdot \text{night}$
  - Golden dawn horizon veil: `#ffc68e` at alpha $\text{progress} \cdot 0.12$
  - Twinkling stars (36 seeded star motes) and biome-specific horizon light.

---

### Tier 1: Deep Pond Water Base & Sub-Surface Caustics
- **Deep Water Gradient**:
  Spans from waterline ($y \approx 145\text{px}$) to bottom canvas ($y = 359\text{px}$):
  - Waterline shelf: `#45677b` (cool sky reflection)
  - Mid-depth teal: `#184a54` (subsurface absorption)
  - Abyssal deep navy: `#092330` (floor silt)
- **Caustic Light Ribbons**:
  Sinusoidal undulating caustic bands simulating sunlight/moonlight refracting through gentle pond swells onto submerged rocks:
  $$\text{caustic}(x, y, t) = \sin(x \cdot 0.035 + t \cdot 0.8) \cdot \cos(y \cdot 0.05 - t \cdot 0.6)$$
  Color: `#5eead4` / `#8fedd6` at alpha $0.04 \dots 0.09$.
- **Submerged Pad Stems**:
  Dark sinuous green/brown stalks (`#153d36`) descending from pad centers ($x_{\text{pad}}, y_{\text{pad}}$) diagonally into the deep silt bed.

---

### Tier 2: Sub-Surface Aquatic Wildlife (Koi Fish & Tadpoles)

Sub-surface creatures are rendered **below** the water surface plane and ripples, but above the deep water base. Their appearance is modulated by water depth attenuation.

#### Four Traditional Koi Varieties (`KoiState`)

```dart
enum KoiPattern { kohaku, yamabuki, showa, asagi }

class KoiState {
  KoiState({
    required this.index,
    required this.pattern,
    required this.depth,       // 0.2 (near surface) .. 1.0 (deep floor)
    required this.anchorX,
    required this.anchorY,
    required this.swimSpeed,
  });

  final int index;
  final KoiPattern pattern;
  double depth;
  double x = 0, y = 0;
  double heading = 0;
  double finCycle = 0;
  double nibbleTimer = 0;
}
```

| Pattern | Cultural Archetype | Primary Body Palette | Accent Marking Palette | Scale Texture & Dorsal Accents |
| --- | --- | --- | --- | --- |
| **Kohaku** (紅白) | Pure Snow & Vermilion | Snow-white shiroji (`#f0ede6`) | Fiery scarlet-red hi (`#d9381e`, `#bf2611`) | Soft white fin margins, dark obsidian eye pupil (`#101f22`) |
| **Yamabuki** (山吹黄金) | Metallic Imperial Gold | Brilliant golden-yellow (`#f5b82e`) | Deep warm bronze belly (`#b88019`) | Shimmering pale yellow dorsal crown (`#ffe48a`) |
| **Showa** (昭和三色) | Midnight Sumi & Crimson | Ink-black sumi (`#1c262b`, `#121a1e`) | Crimson-red hi patches (`#cc3224`) | Crisp white shiroji flashes on pectoral fins (`#eae6db`) |
| **Asagi** (浅黄) | Indigo Diamond Net | Pale muted indigo-blue (`#5b8296`) | Rust-orange hi belly & gills (`#c94c2e`) | Diamond net-scale crosshatch dorsal pattern (`#7b9ea8`) |

#### Depth Attenuation & Soft Shadows
- **Depth Blending**:
  As koi descend ($depth \to 1.0$):
  $$color = \text{Color.lerp}(patternColor, \text{Color}(0xff103642), depth \cdot 0.75)$$
  $$opacity = (1.0 - depth \cdot 0.55) \cdot koiReveal$$
- **Subsurface Soft Shadow**:
  Render an elliptical shadow on the silt bed directly below the fish ($y + 12 + depth \cdot 18\text{px}$):
  Color `#071922` at alpha $0.15 \cdot (1.0 - depth)$.
- **Surface Nibble Micro-Ripples**:
  Rarely, a curious koi approaches the surface ($depth < 0.25$, `nibbleTimer > 0`):
  Its mouth touches the surface film, spawning two tiny circular micro-ripples ($R_{\max} = 10\text{px}$, alpha 0.30).

#### Darting Tadpoles (`TadpoleState`)
- **Visuals**:
  Tiny 3–5px teardrop bodies (`#1e2b2f`) with a flickering 3px translucent tail (`#3c5357` at alpha 0.6).
- **Boids / Schooling Behavior**:
  - Tadpoles congregate in schools of 6–10 in warm shallow water pockets ($y \approx 200 \dots 280\text{px}$).
  - Movement: Swift wriggling bursts followed by idle drifting pauses.
  - **Fleeing Reaction**: When a frog belly-flops or lands within 45px of a school, tadpoles scatter radially outward at $3\times$ speed.

---

### Tier 3: Water Surface Plane & Expanding Refractive Ripples (`RippleState`)

The surface plane represents the boundary between air and water. Ripples render **over** the sub-surface fish and deep water, creating authentic refraction highlights and shadows.

```dart
class RippleState {
  RippleState({
    required this.x,
    required this.y,
    required this.radiusX,
    required this.radiusY,
    required this.maxRadius,
    required this.amplitude,
    required this.expansionRate,
    this.eccentricity = 0.0,
    this.angle = 0.0,
    this.colorTint = 0xffffffff,
  });

  double x, y;
  double radiusX, radiusY;
  final double maxRadius;
  double amplitude;              // 1.0 (strong) .. 0.0 (dissipated)
  final double expansionRate;    // px/s
  final double eccentricity;     // 0.0 (circle) .. 0.8 (directional wedge)
  final double angle;            // Direction of propagation
  double age = 0.0;
  bool expired = false;
}
```

#### Dual-Ring Refraction Equations
Every ripple consists of two concentric pixel rings modeling the wave crest (specular reflection of the sky) and wave trough (subsurface shadow):

```
       Wave Crest (Highlight):  #c8f0ea / #ffffff  (Alpha: amp * 0.45)
          ╭──────────────────────────────────────────────────╮
         ╱                                                    ╲
        │      Wave Trough (Shadow): #0c2630 (Alpha: amp * 0.35)│
        │         ╭──────────────────────────────╮            │
        │        ╱                                ╲           │
        │       │             Origin             │           │
```

1. **Outer Crest Ring (Highlight)**:
   - Radius: $r_{\text{crest}} = r(t)$
   - Color: Sky highlight `#c8f0ea` (day) / `#ffe6c4` (dawn) / `#6dd6cd` (grotto).
   - Alpha: $A_{\text{crest}} = (1.0 - r / r_{\max}) \cdot amplitude \cdot 0.50$
2. **Inner Trough Ring (Shadow)**:
   - Radius: $r_{\text{trough}} = r(t) - 1.5\text{px}$
   - Color: Deep trough shadow `#0c2630`.
   - Alpha: $A_{\text{trough}} = (1.0 - r / r_{\max}) \cdot amplitude \cdot 0.38$

#### Comprehensive Ripple Event Matrix

| Trigger Event | Origin $(x, y)$ | Initial $R_0$ | Max $R_{\max}$ | Speed ($v_r$) | Amplitude ($A$) | Geometry |
| --- | --- | --- | --- | --- | --- | --- |
| **Center Pad Landing** | Pad center $(x_p, y_p)$ | Pad $R_x$ | $pad.R_x + 55\text{px}$ | $52\text{ px/s}$ | $1.00 \times m_{\text{imp}}$ | Concentric 360° |
| **Mid-Pad Landing** | Impact offset side | Pad $R_x$ | $pad.R_x + 65\text{px}$ | $58\text{ px/s}$ | $1.20 \times m_{\text{imp}}$ | Directional (65/35 bias) |
| **Edge Lobe Fold / Splash** | Folded rim lip | $6\text{px}$ | $95\text{px}$ | $68\text{ px/s}$ | $1.65 \times m_{\text{imp}}$ | Eccentric wavefront ($e=0.7$) |
| **Takeoff Recoil Kick** | Pad center | $12\text{px}$ | $50\text{px}$ | $46\text{ px/s}$ | $0.55 \times m_{\text{launch}}$ | Concentric 360° |
| **Belly-Flop Impact** | Splash coordinate | $4\text{px}$ | $110\text{px}$ | $78\text{ px/s}$ | $1.80$ | Concentric circular |
| **Frog Swim Breaststroke** | Hind webbed feet | $3\text{px}$ | $35\text{px}$ | $42\text{ px/s}$ | $0.45$ | V-wake trailing envelope |
| **Koi Surface Nibble** | Koi mouth coordinate | $2\text{px}$ | $14\text{px}$ | $28\text{ px/s}$ | $0.30$ | Fine concentric double ring |
| **Raindrop Touchdown** | Random pond coord | $1\text{px}$ | $9\text{px}$ | $34\text{ px/s}$ | $0.22$ | Fast micro-ring |

---

### Tier 4: Floating Lily Pads, Lotus Blooms & Surface Actors

Rendered directly above the water surface plane:

#### 1. Lily Pad Anatomy & Deformation
Each lily pad is drawn with procedural pixel-art precision incorporating dynamic physical deformations:
- **Ground Contact Shadow**:
  Drawn directly onto the surface water beneath the pad:
  `_oval(c, pad.x, pad.y + 4 + pad.dipY, pad.radiusX + 4, pad.radiusY + 1, 0xff092d3d, 0.40);`
- **Plum Underside (Zone B & C Lift)**:
  When `pad.tiltAngle.abs() > 0.02`, an angled sliver of `#5a3344` is drawn along the elevated perimeter.
- **Outer Thick Rim & Dorsal Face**:
  - Rim contour: Deep forest teal `#143e3a`
  - Dorsal midtone: Jewel emerald `#32776a` (maple `#3b785f`, grotto `#288588`)
  - Sunlit highlight crown: Lime-seafoam `#49947a` (grotto `#49b0a8`)
- **Radial Leaf Veins**:
  7 delicate branching vein lines radiating outward from the petiole notch: `#b7cd86` (grotto `#92efe3`) at alpha 0.28.
- **Edge Fold & Translucent Water Wash (Zone C)**:
  When `edgeFold > 0.0`:
  - The impact rim boundary shrinks inward by $pad.radiusX \cdot edgeFold \cdot 0.22$.
  - The folded lip is drawn with darkened, wet leaf tone `#1c4438`.
  - The water wash tongue is rendered over the folded edge: `#85d4cb` at alpha `waterWashAlpha`.
- **Resting Dewdrops**:
  3 crystalline water beads resting on the leaf surface:
  Offset vertically by $pad.dewdropBounce$:
  - Base bead: `#e0fbf7` (2×2px) with a pure white 1px specular dot (`#ffffff`).

#### 2. Sacred Lotus Blooms
Nestled near Pad 0 or Pad 1 in tranquil biomes (`sanctuary`, `blossom`):
- Multi-petal cupped water lily flower:
  - Outer petals: Rosy pink `#e6a7b8` / `#f0b9cd`
  - Inner petals: Soft warm white `#fff3f5`
  - Golden stamens: `#f5d795`
- Lotus blossom bobs gently in phase with water swell: $y_{\text{bloom}} + \sin(t \cdot 0.7) \cdot 0.6\text{px}$.

#### 3. Frog Characters & Mid-Air Actors
- Ground-plane contact shadow cast on lily pad (or water during swim): `#0d2726` at alpha 0.45.
- Frog character rendering utilizing `FrogSprites.renderFrog(...)` across all 10 states (`idle`, `charging`, `launching`, `ascending`, `chomping`, `falling`, `landing`, `swallowing`, `swimming`, `sleeping`).

#### 4. Airborne & Perched Insects (`BugState`)
- Flies, mosquitoes, dragonflies, butterflies, ladybugs, and fireflies navigating the open hunting airspace ($y = 0.12 \dots 0.65$).

---

### Tier 5: Foreground Parallax Reeds & Weather Atmosphere

The uppermost framing layer provides immense scenic depth:
- **Foreground Botanical Framing**:
  Transparent WebP foreground assets (`assets/images/foreground-*.webp`, 2752 × 1536 px) representing silhouette marsh vegetation, weeping willow fronds, sakura branches, or grotto rock arches.
- **Dynamic Procedural Foliage**:
  Corner reeds, cattails, and wildflowers swaying in the wind ($windTell$ and $wind$ forces):
  $$\text{sway} = \sin(t \cdot 0.65 + \text{offset}) \cdot 2.5 + wind \cdot 3.0$$
- **Weather Particles & Environmental Atmosphere**:
  - Drizzle & storm rain streaks angled by wind vector.
  - Low bayou mist ribbons drifting across the waterline.
  - Bioluminescent mushroom spores (`grotto`) and drifting momiji maple leaves (`maple`).
  - Luminous night fireflies hovering with gentle sinusoidal altitude pulses.

---

## 4. Fullscreen & Large-Display Composable Layout Specification

### 4.1 Eradication of Letterbox Bars

> [!IMPORTANT]
> The current implementation in `lib/main.dart` uses a rigid `LayoutBuilder` aspect ratio clamp (`aspectW / aspectH = 641 / 359`), resulting in black pillarbox bars on ultrawide monitors and letterbox bars on tall displays. This specification eliminates all letterboxing bars.

```
       Current Constrained Layout              New Composable Full-Viewport Layout
     ┌───────┬───────────────┬───────┐       ┌───────────────────────────────────────────┐
     │ BLACK │  641 × 359    │ BLACK │  ───> │  FULL-BLEED EDGE-TO-EDGE CANVAS           │
     │ PILLAR│   PLAY AREA   │ PILLAR│       │  Play area centered; water, horizon, sky  │
     │ BARS  │ (Letterboxed) │ BARS  │       │  and weather bleed 100% to viewport edges │
     └───────┴───────────────┴───────┘       └───────────────────────────────────────────┘
```

#### Specification in `lib/main.dart`:
Replace the constrained `SizedBox(width: width, height: height)` in `_PondPageState.build` with:
```dart
SizedBox.expand(
  child: Semantics(
    label: 'A peaceful widescreen pond with two little frogs...',
    child: Focus(
      // key & pointer listeners
      child: GameWidget(game: game),
    ),
  ),
)
```

---

### 4.2 Responsive Aspect Coverage & Horizon Bleed

In `PondRenderer.render(Canvas canvas, Size size, PondModel model)`:
Instead of scaling the entire canvas to fit a fixed rectangle, the renderer executes a **Cover-Fit Viewport Projection with Centered Safe Play Area**:

$$\text{scale} = \max\left(\frac{size.width}{\text{logicalWidth}},\ \frac{size.height}{\text{logicalHeight}}\right)$$

```dart
// Transform setup in PondRenderer
final scale = math.max(size.width / logicalWidth, size.height / logicalHeight);
final viewWidth = size.width / scale;
final viewHeight = size.height / scale;

// Center the logical 641 x 359 coordinate frame within the view
final offsetX = (viewWidth - logicalWidth) / 2.0;
final offsetY = (viewHeight - logicalHeight) / 2.0;

canvas.save();
canvas.clipRect(Offset.zero & size);
canvas.scale(scale, scale);
canvas.translate(offsetX, offsetY);
```

#### Horizon Bleed for Ultrawide Displays (21:9 and 32:9)
On displays wider than 16:9 ($W / H > 1.785$):
1. **Scenic Backdrop (`pond-*.webp`)**:
   Drawn with `BoxFit.cover` centered horizontally and vertically, guaranteeing zero empty pixels across any aspect ratio up to 32:9.
2. **Infinite Water Surface**:
   The pond water base, surface caustics, and distant bank reflections extend horizontally beyond the 641px frame to cover the entire `viewWidth`:
   `_rect(canvas, -offsetX, waterlineY, viewWidth, pondHeight, color);`
3. **Deep Water Shimmer & Weather Particles**:
   Weather motes and water sparkles sample coordinates across $[-offsetX \dots logicalWidth + offsetX]$, filling the peripheral field of view with gentle motion.

---

### 4.3 Safe-Zone Play Area

While the scenic atmosphere and water bleed indefinitely to the monitor boundaries, the active gameplay elements remain anchored within the optimal interaction sweet spot:

```
    |<------------------------- viewWidth (e.g. Ultrawide 21:9) ------------------------->|
    |                                                                                      |
    |  Peripheral Water Bleed   |<- - - - - Safe Play Area (641px) - - - - ->|   Bleed     |
    |                           |                                            |             |
    |    ~ ~ ~ ~ ~ ~ ~ ~ ~ ~    |      [Pad 0]                  [Pad 1]      |   ~ ~ ~ ~   |
    |     Swimming Koi          |      Rana Verde              Rana Jade     |   Reeds     |
    |                           |      (x=0.27)                (x=0.73)      |             |
```

- **Player Frog (Rana Verde / Pad 0)**: Anchored at $x = 0.27 \times logicalWidth$.
- **Companion Frog (Rana Jade / Pad 1)**: Anchored at $x = 0.73 \times logicalWidth$.
- **Insect Hunting Flight Corridor**: $x \in [0.06 \dots 0.94] \times logicalWidth$, $y \in [0.12 \dots 0.65] \times logicalHeight$.
- **Foreground Foliage Framing**: Anchors to the extreme left and right viewport edges (`-offsetX` and `logicalWidth + offsetX`), naturally framing the display regardless of monitor aspect ratio.

---

### 4.4 High-DPI & Pixel-Art Rendering Integrity

To preserve crisp, deliberate pixel-art rendering on 4K, 5K, and Retina screens:
1. `ui.Paint()..isAntiAlias = false` is enforced on all procedural canvas draw calls.
2. Sprite sheets and backdrops are drawn with `FilterQuality.none`.
3. Discrete pixel steps are rounded via `roundToDouble()` to prevent subpixel jitter during spring oscillations.

---

## 5. State Machine & Implementation Blueprint

### 5.1 Data Model Integration (`PondModel`)

```dart
class PondModel {
  // Existing fields ...
  
  /// The two primary dynamic lily pads in the pond.
  late final List<PadState> pads;

  /// Active water surface ripples propagating across the pond.
  final List<RippleState> ripples = [];

  /// Sub-surface wildlife actors.
  final List<KoiState> koi = [];
  final List<TadpoleState> tadpoles = [];

  // Inside constructor:
  // pads = [
  //   PadState(0, 0.27, 0.69, 36.0, 11.0),
  //   PadState(1, 0.73, 0.72, 38.0, 12.0),
  // ];
  // _initWildlife();
}
```

### 5.2 Kinematic Step Integration (`_tick`)

Within `PondModel._tick(double dt)`:

```dart
void _updatePads(double dt) {
  for (final pad in pads) {
    // 1. Vertical Damped Harmonic Oscillator
    final ay = -145.0 * pad.dipY - 15.5 * pad.dipVelocity;
    pad.dipVelocity += ay * dt;
    pad.dipY += pad.dipVelocity * dt;

    // 2. Pitch Angular Damped Harmonic Oscillator
    final aTheta = -190.0 * pad.tiltAngle - 18.0 * pad.tiltVelocity;
    pad.tiltVelocity += aTheta * dt;
    pad.tiltAngle += pad.tiltVelocity * dt;

    // 3. Lateral Restoring Drift Spring
    final ax = -65.0 * pad.driftX - 12.0 * pad.driftVelocity;
    pad.driftVelocity += ax * dt;
    pad.driftX += pad.driftVelocity * dt;

    // 4. Edge Fold Elastic Recovery
    pad.edgeFold *= math.exp(-dt / 0.175);
    pad.waterWashAlpha = (pad.edgeFold * 0.70).clamp(0.0, 1.0);

    // 5. Dewdrop Bead Bounce
    final aDrop = -310.0 * pad.dewdropBounce - 22.0 * pad.dewdropVelocity + 0.35 * ay;
    pad.dewdropVelocity += aDrop * dt;
    pad.dewdropBounce += pad.dewdropVelocity * dt;
  }
}

void _updateRipples(double dt) {
  ripples.removeWhere((r) => r.expired);
  for (final r in ripples) {
    r.age += dt;
    r.radiusX += r.expansionRate * dt;
    r.radiusY += r.expansionRate * (padAspectRatio) * dt;
    final progress = (r.radiusX / r.maxRadius).clamp(0.0, 1.0);
    r.amplitude = (1.0 - progress) * (1.0 - progress);
    if (progress >= 1.0) r.expired = true;
  }
}
```

---

## 6. Verification & Test Checklist

When testing implementations against this styleguide:

- [ ] **Zone A Check**: Center landing produces symmetric downward pad dip, balanced dewdrop bounce, and circular concentric ripple ring.
- [ ] **Zone B Check**: Mid-pad landing produces visible pitch tilt, opposite rim lift showing 1–2px reddish-plum underside (`0xff5a3344`), and biased ripple emission.
- [ ] **Zone C Check**: Edge touchdown curls the leaf lobe downward (`edgeFold > 0`), triggers translucent water tongue overlay (`waterWashAlpha > 0`), emits 5–9 droplet splash arc, and elastically uncurls back to flat over 0.65s.
- [ ] **Takeoff Recoil**: Launching kicks pad downward and tilts away from jump vector.
- [ ] **Belly-Flop**: Missing pad spawns crown splash and wake wave that rocks adjacent pads.
- [ ] **Composable Layers**: Koi and tadpoles render under surface ripples; ripples modulate water surface with highlight/shadow rings; pads and frogs render above surface ripples.
- [ ] **Koi Patterns**: Kohaku (snow/vermilion), Yamabuki (gold), Showa (black/red/white), and Asagi (indigo/rust) exhibit depth-attenuated colors.
- [ ] **Fullscreen Layout**: Resizing browser or running on ultrawide display fills 100% of viewport with zero letterbox bars while keeping pads centered in safe arena.

---

## 7. Valve GameFlow-Tuned Jump Controller & Input Responsiveness

Following Valve's GameFlow / playtesting responsiveness principles:
1. **Near-Immediate Takeoff (`<= 60ms` Anticipation)**:
   - Pressing mouse, touch, or `Space`/`Enter` never traps the frog in an indefinite crouch.
   - Within `0.06s` (60ms) of `press()`—or immediately upon `release()` if tapped faster than `0.06s`—the frog launches into the air.
2. **Variable Jump Height via Release Timing (Sustain Window)**:
   - **Lift immediately (`holdDuration < 0.18s`)**: Quick `'tap'` hop (`height = 0.13`, `duration = 0.68s`).
   - **Lift around takeoff / early ascent (`0.18s <= holdDuration < 0.52s`)**: Small/medium `'low'` jump (`height = 0.25`, `duration = 0.95s`).
   - **Hold long past takeoff (`holdDuration >= 0.52s`)**: High/long `'high'` jump (`height = 0.39`, `duration = 1.30s`), smoothly blending the vertical arc height in flight with $C^0$ continuity.
3. **Zero Mid-Air Input Queueing**:
   - Any `press()` or tap while a frog is `airborne` or `swimming` (`_busy == true`) is **ignored**, preventing accidental buffered jumps after landing.
4. **Global Desktop Spacebar Support**:
   - `HardwareKeyboard.instance` handles `Space` and `Enter` globally across the browser viewport even before a canvas focus click.
