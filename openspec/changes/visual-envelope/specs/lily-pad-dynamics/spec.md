## ADDED Requirements

### Requirement: Seeded varied pad layout

Each world SHALL place its two hero pads and four to nine ambient pads from its
seed, with varied sizes and positions inside the water basin. Hero pad 0 SHALL
sit in the left part of the basin and hero pad 1 in the right part. Pads SHALL
not overlap. Repeating a seed SHALL reproduce the layout.

#### Scenario: Two seeds differ

- **WHEN** two different seeds construct ponds of the same biome
- **THEN** their hero pad positions or sizes differ
- **AND** every pad lies inside the basin with its full radius.

### Requirement: Pad size tiers

Ambient leaves SHALL come in seeded size tiers: most between 9.5 and 21 px
base radius, some notably larger (21–28 px, close to hero size), and in about
one world in four or five a single super pad (42–54 px) in the Victoria style
with an upturned rim. A super pad SHALL be decorative only, SHALL sit wholly
behind both hero sections so every hero-to-hero flight passes in front of it,
and SHALL never overlap any pad. The large tier SHALL never reduce a world
below four ambient leaves.

#### Scenario: Super pad frequency over 300 seeds

- **WHEN** 300 seeded ponds are constructed
- **THEN** between 45 and 90 of them hold exactly one super pad
- **AND** about one ambient leaf in ten is large
- **AND** no two pad sections overlap in any of them.

#### Scenario: Super pad stays out of the jump lane

- **GIVEN** a world with a super pad
- **THEN** the super pad's section bottom lies above both hero sections' tops
- **AND** the frogs still only perch on the two hero pads.

### Requirement: Pads rotate in their plane

Every pad SHALL rotate in its own plane: a yaw angle turns the slit, veins,
rim notch and lotus anchor around the projected ellipse while the ellipse
itself stays put. Yaw SHALL be driven by the current's shear, a seeded slow
bias, passing ripples, koi wakes and off-centre takeoffs and landings, under
gentle angular drag, so pads visibly turn over tens of seconds and keep
turning while the frogs sleep. The slit SHALL be a true gap through which the
water, ripples and fish beneath are visible. A perched frog SHALL keep its
perch and stay on its pad while the pad rotates.

#### Scenario: Yaw is bounded, smooth and deterministic

- **WHEN** seeded sessions run for a minute with periodic jumps
- **THEN** every yaw stays within (−π, π] and every angular speed within 1.2 rad/s
- **AND** no frame turns a pad by more than 1.2/60 rad
- **AND** at least one pad makes a quarter turn
- **AND** yaw is identical across update partitions.

#### Scenario: Landing turns, never spins

- **WHEN** a frog lands on a hero pad
- **THEN** the pad's angular speed changes by at most 0.6 rad/s.

#### Scenario: See-through slit

- **WHEN** a pad is painted over a flat colour with its slit pointing down,
  up or diagonally
- **THEN** a pixel on the slit centreline at 0.6 of the radius shows the flat
  colour
- **AND** the pixel opposite the slit and the pixel at the centre show the leaf.

#### Scenario: Koi under a slit

- **WHEN** a koi swims under a hero pad along its slit
- **THEN** the frame changes along the slit and not under the leaf body.

### Requirement: Bounded, momentum-driven pad drift

Every pad, hero or ambient, SHALL roam a small bounded section around its
home. Pads SHALL slide in response to frog takeoff and landing, conserving a
plausible share of the frog's horizontal momentum, then slow under water drag.
Passing ripples, koi wakes and the faint wakes of other sliding pads SHALL
nudge them, and they SHALL wander gently on a smooth current. Roaming SHALL
continue while the frogs sleep, carrying the sleeping frogs with their leaves.

#### Scenario: Landing slide

- **WHEN** a frog lands on a hero pad after a sideways jump
- **THEN** the pad slides 3–12 px in the jump's direction
- **AND** within 3 s its slide speed returns to gentle ambient roaming below 1 px/s
- **AND** it never leaves its section.

#### Scenario: One landing nudges the neighbours

- **WHEN** a landing makes a pad slide faster than 2.5 px/s
- **THEN** the pad sheds faint wake ripples that carry nearby pads a little
- **AND** a pad is never carried by ripples centred on its own body.

#### Scenario: Long session stays bounded

- **WHEN** 100 seeded sessions run to sleep and 30 minutes beyond
- **THEN** no pad leaves its section or the basin, no two pads overlap
- **AND** pad positions are identical across update partitions.

### Requirement: Pads change depth with perspective

A pad's on-screen size, stem length and brightness SHALL follow its current
depth in the pond, so a pad drifting toward the viewer grows and brightens and a
receding pad shrinks and hazes. Changes SHALL be smooth with no size popping.

#### Scenario: Receding pad

- **WHEN** a pad drifts 8 px up-screen
- **THEN** its rendered radius decreases monotonically by no more than 8 %.

### Requirement: Frogs ride their pads

A perched or sleeping frog SHALL move with its pad. A frog in flight SHALL land
on its target pad even if the pad moved during the flight, without a visible
teleport.

#### Scenario: Landing on a moving pad

- **GIVEN** a target pad moving at 10 px/s
- **WHEN** a frog completes a jump to it
- **THEN** the frog lands within the pad's radius
- **AND** no frame moves the frog more than 0.03 of the frame width.
