# Ranitas world composition

## Purpose

Compose a beautiful portrait pond from original scenic art and independently
animated vegetation, water, weather, and creatures.

## Requirements

### Requirement: A coherent world is selected once

The game SHALL select a seeded willow, blossom, or cypress composition, one
compatible weather state, and a dusk or dawn light cycle. Those choices SHALL
remain stable through sleep. Random choices SHALL NOT be resampled per frame.

#### Scenario: A repeatable visit

- **WHEN** two models receive the same seed and input timeline
- **THEN** their world choices and simulated motion agree

### Requirement: The world supports large screens

The game SHALL maintain a portrait playfield on every screen orientation. Native
platforms SHALL request portrait orientation. Scenic exports SHALL use prime
1031 by 1543 dimensions and the animated logical canvas SHALL be 257 by 457.
Pixel scaling SHALL be controlled explicitly rather than relying on primality.

#### Scenario: A landscape tablet

- **WHEN** the browser becomes wider than the portrait pond
- **THEN** the complete portrait playfield remains centered with surrounding background
- **AND** the frog landing zones remain inside the playfield

### Requirement: Original assets ship locally

The web bundle SHALL include original generated scenery, procedural wildlife,
and synthesized ambience. Runtime gameplay SHALL require no API, remote model,
analytics, or third-party sound download.

#### Scenario: Production bundle

- **WHEN** the production web build completes
- **THEN** its assets include the generated landscapes and local Flutter engine
- **AND** each static file is below the Cloudflare 25 MiB limit

### Requirement: Independent world layers reveal gradually

Sky, landscape, vegetation, water, and wildlife SHALL compose in depth order.
Ambient animation and lighting SHALL enrich smoothly after the first completed
gesture, while the sleeping endpoint retains living background motion forever.

#### Scenario: The frogs finish hunting

- **WHEN** both frogs settle into synchronized sleep
- **THEN** the final light palette holds
- **AND** water, weather, plants, and appropriate wildlife continue gently
