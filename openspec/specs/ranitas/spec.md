# Ranitas world composition

## Purpose

Compose a beautiful widescreen landscape pond for high-resolution displays from
original scenic art, biome-matched foreground parallax overlays, hybrid
multi-pose frog sprite sheets, and independently animated vegetation, water,
weather, and creatures.

## Requirements

### Requirement: A coherent world is selected once

The game SHALL select a seeded biome composition (`willow`, `blossom`,
`cypress`, `maple`, `sanctuary`, `grotto`, or `alpine`), one compatible weather
state, and a dusk or dawn light cycle. Those choices SHALL remain stable through
sleep. Random choices SHALL NOT be resampled per frame.

#### Scenario: A repeatable visit

- **WHEN** two models receive the same seed and input timeline
- **THEN** their world choices and simulated motion agree

### Requirement: The world supports large high-resolution landscape screens

The game SHALL maintain a widescreen landscape playfield on every screen
orientation. Native platforms SHALL request landscape orientation. Scenic and
foreground exports SHALL use prime `2557 × 1439` dimensions, frog character
sprite sheets SHALL use prime `1031 × 521` dimensions, and the animated logical
canvas SHALL be `641 × 359` (both prime). Pixel scaling SHALL be controlled
explicitly rather than relying on primality.

#### Scenario: A high-resolution widescreen display

- **WHEN** the browser renders on a widescreen or ultrawide display
- **THEN** the complete 641:359 landscape playfield remains centered with surrounding background
- **AND** the frog landing zones remain inside the playfield

### Requirement: Expressive multi-state frog animations

Both frogs SHALL animate across ten distinct visual states: `idle`, `charging`,
`launching`, `ascending`, `chomping`, `falling`, `landing`, `swallowing`,
`swimming`, and `sleeping`. Catching an insect in mid-air SHALL trigger a
`chomping` pose and tongue strike in flight, followed upon landing by a
post-landing `swallowing` animation (cheek puff, throat bulge, and gulp).

#### Scenario: Mid-air catch and post-landing swallow

- **WHEN** a jumping frog intercepts a live insect in flight
- **THEN** it enters `chomping` with an extended tongue and records the catch
- **AND** upon landing on the destination lily pad it plays the `landing` squash followed by the `swallowing` animation

### Requirement: Original assets ship locally

The web bundle SHALL include original generated landscape scenery, foreground
parallax overlays, frog sprite sheets, procedural wildlife, and synthesized
ambience. Runtime gameplay SHALL require no API, remote model, analytics, or
third-party sound download.

#### Scenario: Production bundle

- **WHEN** the production web build completes
- **THEN** its assets include the generated landscapes, frog sheets, and local Flutter engine
- **AND** each static file is below the Cloudflare 25 MiB limit

### Requirement: Independent world layers reveal gradually

Sky, landscape, vegetation, water, and wildlife SHALL compose in depth order.
Ambient animation and lighting SHALL enrich smoothly after the first completed
gesture, while the sleeping endpoint retains living background motion forever.

#### Scenario: The frogs finish hunting

- **WHEN** both frogs settle into synchronized sleep
- **THEN** the final light palette holds
- **AND** water, weather, plants, and appropriate wildlife continue gently
