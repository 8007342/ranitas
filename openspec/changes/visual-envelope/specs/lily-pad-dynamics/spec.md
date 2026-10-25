## ADDED Requirements

### Requirement: Seeded varied pad layout

Each world SHALL place its two hero pads and five to nine ambient pads from its
seed, with varied sizes and positions inside the water basin. Hero pad 0 SHALL
sit in the left part of the basin and hero pad 1 in the right part. Pads SHALL
not overlap. Repeating a seed SHALL reproduce the layout.

#### Scenario: Two seeds differ

- **WHEN** two different seeds construct ponds of the same biome
- **THEN** their hero pad positions or sizes differ
- **AND** every pad lies inside the basin with its full radius.

### Requirement: Bounded, momentum-driven pad drift

Pads SHALL slide in response to frog takeoff and landing, conserving a plausible
share of the frog's horizontal momentum, then slow under water drag. They SHALL
wander gently on a smooth current and stay inside a bounded section around
their home. Pad motion SHALL stop while the frogs sleep, except for gentle bob.

#### Scenario: Landing slide

- **WHEN** a frog lands on a hero pad after a sideways jump
- **THEN** the pad slides 3–12 px in the jump's direction
- **AND** its slide speed falls below 0.1 px/s within 3 s
- **AND** it never leaves its section.

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
