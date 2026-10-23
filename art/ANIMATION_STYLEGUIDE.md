# Ranitas Animation & Micro-Expression Styleguide

## Authoritative Kinematics, Ground-Plane Physics, and Micro-Expression Architecture

Ranitas pairs hand-placed pixel art and widescreen backdrops with deterministic procedural life. The illusion of a living, tranquil pond depends on **spatial grounding**, **subtle amphibian physiology**, and **natural hydrodynamics**.

This styleguide defines the canonical mathematical models, easing equations, and animation constraints for:
1. **Ground-Plane Jump Shadow Physics** (eliminating floating shadows)
2. **Discrete, Natural Frog Micro-Animations** (eliminating bloated cartoon throat/cheek balloons)
3. **Sub-Surface Aquatic Creature Kinematics** (multi-segment traveling wave spines and startle hydrodynamics)

---

## 1. Ground-Plane Jump Shadow Physics

### 1.1 The Orthographic Grounding Principle
In 2.5D / isometric perspective with an elevated light source (sky, daylight, twilight moon), shadows are optical projections cast onto the ground plane beneath an entity.

```
       Airborne Frog (x, frog.y)  --- [Altitude = groundY - frog.y]
              \
               \ (Light direction ~ vertical)
                \
  ===========================================  Pond Surface Plane (Z = 0)
        Ground Shadow (x, groundY)
```

> [!CAUTION]
> **The Airborne Y Projection Bug**:
> An entity's shadow must **NEVER** use `y = frog.y + offset`. In an aerial trajectory, `frog.y` ascends into the sky (decreasing in Y by up to 140 pixels). Tying shadow position to `frog.y` causes the shadow to float through the air with the frog, destroying depth perception and disconnecting the frog from the pond.

The shadow position must always be anchored to the **pond/lily-pad surface plane** (`groundY`), moving horizontally with the frog while scaling and fading according to **true geometric altitude**.

---

### 1.2 Mathematical Formulation of Ground-Plane Shadow

#### A. Trajectory & Coordinate Systems
Let the normalized jump phase be $p = \text{frog.jumpPhase} \in [0.0, 1.0]$.
Given launch point $(\text{fromX}, \text{fromY})$ and landing target $(\text{toX}, \text{toY})$:

$$\text{groundY}(p) = \text{fromY} + (\text{toY} - \text{fromY}) \cdot p$$

$$\text{frog.x}(p) = \text{fromX} + (\text{toX} - \text{fromX}) \cdot p$$

$$\text{arcElevation}(p) = \sin(\pi \cdot p) \cdot \left(H_{\text{action}} + \text{index} \cdot 0.018\right)$$

$$\text{frog.y}(p) = \text{groundY}(p) - \text{arcElevation}(p)$$

Where $H_{\text{action}}$ is the normalized peak jump height:
- `tap`: $H = 0.13$ (~46.7 px)
- `low`: $H = 0.25$ (~89.8 px)
- `high`: $H = 0.39$ (~140.0 px)

The instantaneous altitude above the water plane is:

$$\text{altitude}(p) = \text{groundY}(p) - \text{frog.y}(p) = \text{arcElevation}(p)$$

$$\text{maxAltitude} = H_{\text{action}} + \text{index} \cdot 0.018$$

$$\text{altNormalized} = \left(\frac{\text{altitude}}{\text{maxAltitude}}\right) \in [0.0, 1.0]$$

---

### 1.3 Shadow Radius & Umbra/Penumbra Diffusion

As an object moves away from the ground plane, diffuse ambient light softens and expands the outer penumbra while shrinking the dense core umbra:

$$\text{rx} = r_{x,\text{base}} \cdot \left(1.0 - 0.35 \cdot \text{altNormalized}\right)$$

$$\text{ry} = r_{y,\text{base}} \cdot \left(1.0 - 0.25 \cdot \text{altNormalized}\right)$$

- **At ground level** ($p = 0.0$ or $1.0$, $\text{altitude} = 0$):
  - $rx = r_{x,\text{base}} = 14.0\text{ px}$
  - $ry = r_{y,\text{base}} = 4.0\text{ px}$
- **At jump apex** ($p = 0.5$, $\text{altNormalized} = 1.0$):
  - $rx = 14.0 \cdot 0.65 = 9.1\text{ px}$
  - $ry = 4.0 \cdot 0.75 = 3.0\text{ px}$

---

### 1.4 Opacity Attenuation with Altitude

The light occlusion fraction attenuates inversely with elevation. The minimum visibility floor ($0.25$) ensures the player never loses spatial tracking of their landing trajectory:

$$\text{altitudeFactor} = \text{clamp}\left(1.0 - \frac{\text{altitude}}{\text{maxAltitude}},\, 0.25,\, 1.0\right)$$

$$\alpha_{\text{shadow}} = \alpha_{\text{surfaceBase}} \cdot \text{altitudeFactor}$$

---

### 1.5 Surface Media Differentiation: Lily Pad vs. Open Water

The visual character of the shadow adapts dynamically to the receiving surface:

| Attribute | On Lily Pad Surface | Over Open Water |
| :--- | :--- | :--- |
| **Media Type** | Opaque, matte waxy cuticle | Translucent fluid, sub-surface scattering |
| **Base Opacity $\alpha_{\text{surfaceBase}}$** | `0.38` (deep, crisp contrast) | `0.22` (soft, diffused, refracted) |
| **Apex Opacity (at max altitude)** | $0.38 \times 0.25 = \mathbf{0.095}$ | $0.22 \times 0.25 = \mathbf{0.055}$ |
| **Color Cast** | Deep crevice outline (`#143534` / `#13303a`) | Abyssal sub-surface teal (`#092d3d`) |
| **Geometric Scale** | Standard ($1.0 \times rx$, $1.0 \times ry$) | Refracted spread ($1.15 \times rx$, $1.10 \times ry$) |
| **Edge Sharpness** | Hard pixel boundary | Soft multi-step dither or secondary refraction halo |

#### Surface Blend Factor
Let $d_{\text{pad}}$ be the normalized distance from the shadow position to the nearest lily pad center $(X_{\text{pad}}, Y_{\text{pad}})$:

$$d_{\text{pad}} = \sqrt{\left(\frac{x - X_{\text{pad}}}{R_{x,\text{pad}}}\right)^2 + \left(\frac{\text{groundY} - Y_{\text{pad}}}{R_{y,\text{pad}}}\right)^2}$$

$$\text{padWeight} = \text{clamp}\left(\frac{1.08 - d_{\text{pad}}}{0.16},\, 0.0,\, 1.0\right)$$

When $\text{padWeight} = 1.0$, the shadow is fully on the pad; when $\text{padWeight} = 0.0$, it is fully on open water. Transition across the pad edge is smoothly interpolated.

---

### 1.6 Dynamic Lily Pad Dip Coupling (`pad.dipY`)

Lily pads are buoyant, elastic structures resting on surface tension. When a frog crouches, launches, or lands, the pad depresses into the water column. The ground shadow must vertically track this pad displacement:

$$\text{shadowY} = \left(\text{groundY} \cdot 359.0\right) + \text{padDipY} + \text{surfaceBob}$$

Where:
1. **Takeoff Depression** ($p < 0.18$ during `launching`):
   $$\text{padDipY}_{\text{launch}} = 2.4 \cdot \left(1.0 - \frac{p}{0.18}\right)\text{ px}$$
2. **Landing Impact Depression** ($\text{landingTimer} > 0$):
   $$t_{\text{land}} = 1.0 - \text{clamp}\left(\frac{\text{landingTimer}}{0.28},\, 0.0,\, 1.0\right)$$
   $$\text{padDipY}_{\text{land}} = 3.2 \cdot \sin(t_{\text{land}} \cdot \pi) \cdot \exp(-2.5 \cdot t_{\text{land}})\text{ px}$$
3. **Pond Surface Bob**:
   $$\text{surfaceBob} = \sin(\text{time} \cdot 0.7) \cdot 0.8 \cdot \text{motion}\text{ px}$$

---

### 1.7 Reference Ground-Plane Shadow Implementation

```dart
// Compute logical canvas coordinates (641 x 359 stage)
final groundYNorm = frog._fromY + (frog._toY - frog._fromY) * frog.jumpPhase;
final groundYPx = groundYNorm * 359.0;
final altitudeNorm = (groundYNorm - frog.y).clamp(0.0, 1.0);
final maxAlt = frog.maxJumpAltitude; // H_action + index * 0.018
final altFactor = (1.0 - altitudeNorm / maxAlt).clamp(0.25, 1.0);

// Determine surface media (pad vs water)
final onPad = model.isOverPad(frog.x, groundYNorm);
final baseAlpha = onPad ? 0.38 : 0.22;
final shadowAlpha = baseAlpha * altFactor;
final shadowRx = (onPad ? 14.0 : 16.0) * (1.0 - 0.35 * (altitudeNorm / maxAlt));
final shadowRy = (onPad ? 4.0 : 4.4) * (1.0 - 0.25 * (altitudeNorm / maxAlt));
final shadowColor = onPad ? frogOutlineColor : 0xff092d3d;

// Render grounded shadow at groundYPx + padDipY
renderOval(canvas, frogX * 641.0, groundYPx + padDipY, shadowRx, shadowRy, shadowColor, shadowAlpha);
```

---

## 2. Discrete, Natural Frog Micro-Animations

### 2.1 The Silhouette Discipline: Why Cartoon Throat Balloons Are Forbidden

Tree frogs and pond frogs (*Hylidae* and *Ranidae*) have sleek, aerodynamic silhouettes when perched on vegetation. While cartoon tropes often depict throats inflating into enormous external globes protruding 4–6 pixels beyond the head, this produces grotesque, broken silhouettes in pixel art.

> [!IMPORTANT]
> **The Silhouette Rule**:
> Micro-expressions must remain **internal to the character boundary**.
> 1. Swallowing and vocal sac pulses must never inflate or protrude outside the established jaw/chin outline.
> 2. Animation occurs through **subtle mesh scaling (3–4%)**, **internal color shimmer (1–2px)**, and **expressive facial pixel shifts** (squinting eyes, blushing cheeks).

---

### 2.2 Discrete Swallowing Micro-Expression (`swallowing` State)

When a frog lands after catching insects in flight, it enters the `swallowing` state for $0.88\text{ seconds}$ ($\text{swallowTimer}$).

```
[Phase A: Lip Seam & Tasp]      [Phase B: Subtle Gulp & Shimmer]     [Phase C: Contented Squint]
      (p = 0.00..0.22)                 (p = 0.22..0.65)                   (p = 0.65..1.00)
    +---------------+                +---------------+                  +---------------+
    |   o       o   | (Alert eyes)   |   -       -   | (Softening)      |   ^       ^   | (Happy crescents)
    |    \_____/    |                |    \_____/    |                  |    \_____/    |
    |      *~       | (Wing vanish)  |      ░░       | (1px shimmer)    |     ( . )     | (Settling throat)
    +---------------+                +---------------+                  +---------------+
    scaleY: 1.00                     scaleY: 0.97 (Head nod)            scaleY: 1.00
```

#### A. Base Pose
- Retain the clean, grounded perched silhouette of **Cell (0, 0)** (`idle` pose). Do not swap to an inflated or distorted sprite cell.

#### B. Vertical Head-Nod & Gulp Deformation Curves
Let progress $p = 1.0 - \text{clamp}(\text{frog.swallowTimer} / 0.88,\, 0.0,\, 1.0) \in [0.0, 1.0]$:

$$\text{nodPhase} = \sin(p \cdot \pi)$$

$$\text{scaleX} = 1.0 + 0.035 \cdot \text{nodPhase} \quad (+3.5\%\text{ max lateral expansion})$$

$$\text{scaleY} = 1.0 - 0.030 \cdot \text{nodPhase} \quad (-3.0\%\text{ max vertical compression})$$

$$\text{offsetY} = -1.2 \cdot \sin(p \cdot \pi)\text{ px} \quad (\text{subtle upward head-tilt gulp})$$

This creates a gentle, organic head-nodding gulp that conveys muscular ingestion without cartoon caricature.

#### C. Contented Happy Squinting Eyes (`^ ^`)
During mid-to-late swallow ($p \in [0.35, 0.85]$), the alert circular eyes narrow into satisfied curved crescents:
- **Upper Eyelid**: A 4px wide horizontal line with a 1px raised central peak:
  $$\text{EyeTop}(dx) = \begin{cases} y_{\text{eye}} - 1 & \text{if } dx \in \{1, 2\} \\ y_{\text{eye}} & \text{if } dx \in \{0, 3\} \end{cases}$$
- **Color**: Defined in the frog's dark outline palette (`#143534` for Rana Verde, `#13303a` for Rana Jade).
- **Cheek Warmth**: Soft rosy cheek blush (`#e58f8e` / `#d995a8`) gently warms up:
  $$\alpha_{\text{cheek}} = 0.40 + 0.35 \cdot \sin(p \cdot \pi)$$

#### D. Discrete Esophageal Throat Shimmer
To convey the insect passing down the digestive tract, render a **1–2px subtle highlight shimmer** that travels downward *strictly inside* the existing belly/chin contour:

$$\text{shimmerY} = y_{\text{chinTop}} + p \cdot \left(y_{\text{bellyBase}} - y_{\text{chinTop}}\right)$$

$$\text{shimmerWidth} = 3\text{ px},\quad \text{shimmerHeight} = 1\text{ px}$$

$$\text{shimmerColor} = \text{sacColor}_{\text{highlight}} \text{ (`#fff9d6`)}$$

$$\alpha_{\text{shimmer}} = 0.65 \cdot \sin(p \cdot \pi)$$

The shimmer stays bounded by the internal contour of the ventral throat; it never expands the perimeter by even 1 pixel.

#### E. Vanishing Insect Wing & Ascending Sparkle Mote
1. **Vanishing Wing Fragment** ($p < 0.22$):
   - At the lateral mouth corner $(x_{\text{mouth}} + 4 \cdot \text{facing},\, y_{\text{mouth}})$, a 2×1 px delicate wing tip (`#d4e5de`) is visible.
   - Opacity: $\alpha_{\text{wing}} = \left(1.0 - \frac{p}{0.22}\right) \cdot 0.85$.
   - Slips into the mouth seam by $p = 0.22$.
2. **Ascending Satisfaction Sparkle** ($p \in [0.45, 0.95]$):
   - A single 4-pointed golden sparkle mote (`#ffeaa6`, 3×3 px cross) emerges 12px ahead of the snout.
   - Progress: $t_{\text{sparkle}} = \frac{p - 0.45}{0.50}$.
   - Vertical drift: $\Delta y = -7.0 \cdot t_{\text{sparkle}}\text{ px}$.
   - Opacity: $\alpha = \sin(t_{\text{sparkle}} \cdot \pi) \cdot 0.85$.

---

### 2.3 Discrete Idle Vocal Sac (`idle` State)

Frogs in nature perform gentle buccal pumping (oscillating the floor of the mouth to circulate air across the lungs and vocal sac).

#### In-Boundary Throat Pulse Math
The vocal wave is driven by continuous scene time:

$$\text{vocalWave} = \max\left(0.0,\, \sin(\text{time} \cdot 2.4 + \text{index} \cdot 2.2) - 0.35\right)$$

When $\text{vocalWave} > 0$ and the frog is awake and perched:
- **Maximum Displacement**: $\Delta r \le 1.0\text{ px}$.
- The under-chin ventral region shifts by at most **1 pixel downward**, perfectly contained within the chin's bottom bounding box.
- The inner sac highlight (`#e6d88a` / `#bce6cf`) expands slightly upward into the ventral cream belly, creating an internal breathing glow rather than an external sphere.

---

### 2.4 Takeoff & Landing Squash/Stretch Curves

Every state transition utilizes distinct, non-linear easing functions to preserve mass and energy:

```
State:       CHARGING              LAUNCHING               LANDING                 SWIMMING
Curve:       Cubic Ease-In         Elastic Snap & Decay    Damped Harmonic Bounce  Sinusoidal Kick/Glide
Formula:     (3p^2 - 2p^3)         sin(t * pi) * overshoot  sin(t * 2.5pi) * e^-3.5t  sin(swimAge * 14)
```

#### A. Charging (Pre-Jump Anticipation Compression)
Holding the pointer accumulates `holdDuration` ($0.0 \to 0.65\text{ s}$):

$$c = \text{clamp}\left(\frac{\text{holdDuration}}{0.65},\, 0.0,\, 1.0\right)$$

$$c_{\text{eased}} = c^2 \cdot (3 - 2c) \quad (\text{Hermite smoothstep})$$

$$\text{scaleX} = 1.0 + c_{\text{eased}} \cdot 0.14 \quad (\text{wide, grounded footing})$$

$$\text{scaleY} = 1.0 - c_{\text{eased}} \cdot 0.20 \quad (\text{compressed body})$$

$$\text{offsetY} = c_{\text{eased}} \cdot 2.2\text{ px} \quad (\text{settling into pad})$$

#### B. Launching (Explosive Extension, $p \in [0.0, 0.18]$)
At liftoff, stored elastic energy releases explosively into an elongated aerodynamic shape:

$$t_{\text{launch}} = \frac{p}{0.18} \in [0.0, 1.0]$$

$$\text{stretch} = \sin(t_{\text{launch}} \cdot \pi)$$

$$\text{scaleX} = 0.86 + 0.14 \cdot t_{\text{launch}} \quad (\text{narrowing})$$

$$\text{scaleY} = 1.0 + 0.22 \cdot \text{stretch} \quad (\text{longitudinal extension up to +22\%})$$

$$\text{hindLegExtension} = 6.0 \cdot \text{stretch}\text{ px}$$

#### C. Landing (Damped Harmonic Impact Squash, $0.28\text{ s}$ Window)
Touching down on the target lily pad triggers an elastic impact that rapidly settles:

$$t_{\text{land}} = 1.0 - \text{clamp}\left(\frac{\text{landingTimer}}{0.28},\, 0.0,\, 1.0\right) \in [0.0, 1.0]$$

$$\text{dampedSquash} = \sin(t_{\text{land}} \cdot 2.5 \cdot \pi) \cdot \exp(-3.5 \cdot t_{\text{land}})$$

$$\text{scaleX} = 1.0 + \text{dampedSquash} \cdot 0.18$$

$$\text{scaleY} = 1.0 - \text{dampedSquash} \cdot 0.20$$

$$\text{offsetY} = \max\left(0.0,\, \text{dampedSquash}\right) \cdot 2.4\text{ px}$$

Concentric impact ripples propagate outward from the pad perimeter:

$$R_{\text{ripple}}(t_{\text{land}}) = 15.0 + t_{\text{land}} \cdot 14.0\text{ px},\quad \alpha_{\text{ripple}} = (1.0 - t_{\text{land}}) \cdot 0.35$$

#### D. Swimming (Belly-Flop & Submerged Frog-Kick Recovery)
When landing in open water, the frog executes breaststroke kick cycles:

$$\text{kickPhase} = \sin(\text{swimAge} \cdot 14.0)$$

$$\text{buoyancyBob} = \cos(\text{swimAge} \cdot 7.0) \cdot 0.8\text{ px}$$

- **Power Stroke** ($\text{kickPhase} > 0$):
  - Hind legs thrust backward: $\text{legSpread} = 4.0 + \text{kickPhase} \cdot 5.0\text{ px}$.
  - Body accelerates forward along spline toward the home pad.
- **Recovery Stroke** ($\text{kickPhase} < 0$):
  - Hind legs tuck inward toward torso: $\text{legSpread} = 4.0 - |\text{kickPhase}| \cdot 2.5\text{ px}$.
  - Body glides on momentum.

---

## 3. Sub-Surface Aquatic Creature Kinematics (Koi Fish & Tadpoles)

The pond depth layer features swimming sub-surface creatures (mature Japanese Nishikigoi and developing tadpoles) that inhabit the dark water column beneath the lily pads.

```
       [Head: S0] ---> [Body: S1] ---> [TailBase: S2] ---> [TailTip: S3]
           |               |                 |                    |
        Heading        Pectoral          Peduncle             Caudal Fin
        (A0 = 0.8)     (A1 = 1.8)        (A2 = 3.6)           (A3 = 6.2)
```

---

### 3.1 Articulated 5-Element Swimming Spine

Sub-surface fish deform along a discrete articulated skeletal chain consisting of 5 key nodes:

1. **Segment 0: Head / Rostrum** ($i = 0$):
   - Houses the olfactory sensors, eyes, and mouth.
   - Low lateral sway amplitude to maintain forward gaze stability.
2. **Segment 1: Body / Torso** ($i = 1$):
   - Mass center, dorsal ridge, and anchor for left/right pectoral fins.
3. **Segment 2: Tail Base / Peduncle** ($i = 2$):
   - Flexible muscular narrowing providing articulation between torso and fin.
4. **Segment 3: Tail Tip / Caudal Fin** ($i = 3$):
   - High-amplitude, flexible trailing edge that generates forward thrust.
5. **Pectoral Fins (Left & Right)**:
   - Lateral stabilizers that articulate with counter-phase flapping.

---

### 3.2 Travelling Sinusoidal Wave Mechanics

Fish propulsion is governed by a **retrograde travelling undulatory wave** that moves backward along the body faster than the fish's forward swimming speed.

#### Lateral Spine Displacement Formula
The lateral offset $\Delta \perp(i, t)$ perpendicular to the fish's heading for segment $i \in \{0, 1, 2, 3\}$ is:

$$\Delta \perp(i, t) = A(i) \cdot \sin\left(\text{swimPhase} - i \cdot 0.90\right)$$

Where:
- $\text{swimPhase} = \omega_{\text{swim}} \cdot \text{time} + \phi_{\text{individual}}$
- **Phase Lag Constant** ($0.90\text{ rad}$ per segment): Creates the fluid backward-traveling wave.
- **Quadratic Amplitude Envelope** $A(i)$: Increases from nose to tail:

$$A(i) = 0.8 + 0.6 \cdot i^2 \implies \begin{cases} A(0) = 0.8\text{ px} & (\text{head}) \\ A(1) = 1.8\text{ px} & (\text{body}) \\ A(2) = 3.6\text{ px} & (\text{tail base}) \\ A(3) = 6.2\text{ px} & (\text{caudal tip}) \end{cases}$$

#### Pectoral Fin Oscillation
The left and right pectoral fins articulate with a phase offset to stabilize yaw:

$$\theta_{\text{pectoral, L}} = \theta_{\text{base}} + \sin(\text{swimPhase} \cdot 1.1 + 0.4) \cdot 0.35\text{ rad}$$

$$\theta_{\text{pectoral, R}} = -\theta_{\text{base}} - \sin(\text{swimPhase} \cdot 1.1 + 0.4) \cdot 0.35\text{ rad}$$

---

### 3.3 Creature Kinematic Profiles: Koi vs. Tadpole

| Parameter | Nishikigoi (Koi Fish) | Anuran Tadpole |
| :--- | :--- | :--- |
| **Body Length** | $22\text{ px}$ (large, stately) | $9\text{ px}$ (tiny, quick) |
| **Cruise Speed $v_{\text{cruise}}$** | $18.0\text{ px/s}$ | $28.0\text{ px/s}$ |
| **Wave Frequency $\omega_{\text{swim}}$** | $2.4\text{ rad/s}$ | $6.5\text{ rad/s}$ (fast tail flutter) |
| **Phase Lag per Segment** | $0.90\text{ rad}$ | $1.35\text{ rad}$ (whip-like tail ribbon) |
| **Spine Distribution** | Balanced (Head 25%, Torso 35%, Tail 40%) | Globular (Head/Body 50%, Tail 50%) |
| **Palette** | Sunkissed apricot (`#e8aa85`), cream (`#f5d9ac`), cedar (`#bf8b72`) | Charcoal black (`#1a2d33`), olive shadow (`#2e4745`), translucent fin (`#5b827e`) |
| **Sub-surface Depth** | Deep ($Y \in [260, 320]$, $\alpha \approx 0.18..0.30$) | Shallow ($Y \in [220, 290]$, $\alpha \approx 0.35..0.55$) |

---

### 3.4 Hydrodynamic Disturbance & Startle/Scatter Response

Sub-surface creatures detect pressure waves produced by frog landings or belly flops through their lateral line organ.

```
       Frog Impact Point (X_impact, Y_impact)
                *  (Splash / Pad Dip)
               / \
              /   \ Shockwave (R_startle = 160 px)
             v     v
        [Koi A]   [Koi B]
          \         /
           \       /  (Turn-away vector & burst speed)
            v     v
```

#### A. Trigger Events
1. **Frog Pad Landing**: Occurs at $(\text{frog.x}, \text{groundY})$ when $\text{frog.landingTimer}$ initializes ($0.28\text{ s}$).
2. **Frog Belly Flop**: Occurs at $(\text{splashX}, \text{toY} + 0.065)$ when $\text{frog.swimming}$ begins ($1.0\text{ s}$).

#### B. Spatial Detection & Impulse Strength
Let $D = \text{distance}\left(\text{creature.pos},\, \text{impact.pos}\right)$:

$$I_{\text{startle}} = \text{clamp}\left(1.0 - \frac{D}{R_{\text{startle}}},\, 0.0,\, 1.0\right),\quad R_{\text{startle}} = 160.0\text{ px}$$

#### C. Kinematic Response Dynamics
1. **Impulse Speed Burst**:
   The creature's swimming speed surges instantaneously:
   $$v_{\text{startle}} = v_{\text{cruise}} + I_{\text{startle}} \cdot 65.0\text{ px/s}$$
   The speed relaxes exponentially back to cruising speed:
   $$v(t + \Delta t) = v_{\text{cruise}} + \left(v(t) - v_{\text{cruise}}\right) \cdot \exp(-2.2 \cdot \Delta t)$$
2. **Frequency Coupling**:
   Undulatory wave frequency accelerates proportionally to swimming velocity:
   $$\omega_{\text{swim}}(t) = \omega_{\text{base}} \cdot \left(\frac{v(t)}{v_{\text{cruise}}}\right)$$
3. **Turn-Away Steering Vector**:
   Creatures steer away from the disturbance vector:
   $$\vec{u}_{\text{flee}} = \frac{\text{creature.pos} - \text{impact.pos}}{\|\text{creature.pos} - \text{impact.pos}\|}$$
   $$\theta_{\text{target}} = \text{atan2}\left(u_{\text{flee}, y},\, u_{\text{flee}, x}\right)$$
   The fish rotates toward $\theta_{\text{target}}$ with a maximum turn rate of $4.8\text{ rad/s}$.
4. **Evasive Submersion Dive**:
   During active flight ($I_{\text{startle}} > 0.3$), the creature dives deeper into the dark water column to evade the surface threat:
   $$\Delta z_{\text{dive}} = I_{\text{startle}} \cdot 18.0\text{ px}$$
   $$\alpha_{\text{startle}} = \alpha_{\text{base}} \cdot \left(1.0 - 0.45 \cdot I_{\text{startle}}\right)$$
   This softens the creature's silhouette and makes it appear to plunge into the pond depths, gradually re-emerging over $2.5\text{ seconds}$ as peace returns.

---

## 4. Animation Parameters & Constants Summary

| System | Variable / Symbol | Canonical Value | Units / Range | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Shadow** | $r_{x,\text{base}},\, r_{y,\text{base}}$ | `14.0`, `4.0` | Pixels | Perched frog shadow dimensions |
| **Shadow** | $\alpha_{\text{padBase}},\, \alpha_{\text{waterBase}}$ | `0.38`, `0.22` | Normalized ($0..1$) | Base shadow opacity on pad vs water |
| **Shadow** | $\text{minAltitudeFactor}$ | `0.25` | Normalized ($0..1$) | Minimum shadow visibility at flight apex |
| **Micro-Expr** | $\text{scaleX}_{\text{swallow}},\, \text{scaleY}_{\text{swallow}}$ | `+0.035`, `-0.030` | Amplitude fraction | Subtle vertical head-nod gulp |
| **Micro-Expr** | $T_{\text{swallow}}$ | `0.88` | Seconds | Duration of bug swallow satisfaction state |
| **Micro-Expr** | $\Delta r_{\text{vocalSac}}$ | $\le 1.0$ | Pixels | In-boundary under-chin breathing modulation |
| **Easing** | $T_{\text{charge}}$ | `0.65` | Seconds | Time to full pre-jump crouch compression |
| **Easing** | $T_{\text{landing}}$ | `0.28` | Seconds | Impact squash and pad-dip window |
| **Koi Kinematics** | $\omega_{\text{swim}}$ | `2.4` | Radians / sec | Base swimming tail undulation frequency |
| **Koi Kinematics** | $\Delta\phi_{\text{segment}}$ | `0.90` | Radians | Travelling wave phase lag per spine segment |
| **Koi Kinematics** | $A(0), A(1), A(2), A(3)$ | `0.8, 1.8, 3.6, 6.2` | Pixels | Spine lateral deflection envelope |
| **Startle** | $R_{\text{startle}}$ | `160.0` | Pixels | Shockwave detection radius for pad/flop impact |
| **Startle** | $v_{\text{boost, max}}$ | `+65.0` | Pixels / sec | Maximum burst speed addition upon startle |
| **Startle** | $\lambda_{\text{relax}}$ | `2.2` | $\text{s}^{-1}$ | Exponential relaxation rate back to cruise speed |
