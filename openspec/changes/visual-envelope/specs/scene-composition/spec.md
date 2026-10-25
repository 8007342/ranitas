## ADDED Requirements

### Requirement: Continuous time-of-day grading

The scenic backdrop and every painted layer SHALL be colour-graded continuously
from daylight through sunset, dusk and night, following the session's
`daylight` value, without flat full-screen washes, flicker or scene cuts. A
biome MAY declare its own night tint. The endpoint grade SHALL hold after sleep.

#### Scenario: Dusk session darkens gradually

- **GIVEN** a dusk-cycle session
- **WHEN** daylight falls from 1 to 0
- **THEN** the backdrop warms toward a sunset tone, then cools and darkens through dusk to night
- **AND** the mean luminance of the graded backdrop decreases monotonically after the sunset peak
- **AND** no single frame changes mean luminance by more than 1 %.

#### Scenario: Dawn reverses the grade

- **GIVEN** a dawn-cycle session
- **WHEN** daylight rises from 0 to 1
- **THEN** the same keyframes play in reverse order.

### Requirement: Emissive light survives darkness

Light sources painted into a backdrop (lanterns, bioluminescent fungi, lit
windows) SHALL stay luminous as the scene darkens when an emissive mask exists
for that backdrop. Missing masks SHALL fall back to plain grading.

#### Scenario: Sanctuary lantern at night

- **GIVEN** the sanctuary biome with its emissive mask
- **WHEN** daylight reaches 0
- **THEN** pixels inside the mask keep at least 70 % of their daylight luminance while unmasked pixels darken.

### Requirement: Palette-cycled scenery

Waterfalls, streams and glows SHALL be able to animate by cycling a colour ramp
through an index map, in the manner of 1990s scenery. Each region SHALL declare
its ramp, frame rate and whether frames blend smoothly or step, chosen by
material: water and bioluminescence blend smoothly, fire steps hard. Index maps MAY
be procedural or painted. Reduced motion SHALL freeze cycling on its first frame.

#### Scenario: Blossom waterfall flows

- **GIVEN** the blossom biome
- **WHEN** time advances by one cycle period
- **THEN** the waterfall region shows every ramp shift once and returns to its first frame
- **AND** pixels outside the region are unchanged by the cycle.

### Requirement: Data-driven layered composition

Each biome SHALL compose an ordered stack of layers in slots: far bank, mid
bank, canopy (anchored to the top of the frame), near corner, and particles.
Layers SHALL sway with depth-weighted amplitude and wind response. Canopy
layers SHALL stay above 30 % of frame height across the central 50 % of width
so jump arcs and insects remain readable. Layer reveal SHALL follow richness.

#### Scenario: Willow canopy

- **GIVEN** the willow biome
- **WHEN** richness exceeds 0.2
- **THEN** willow fronds hang from the top edge in front of the frogs, sway with wind, and leave the central airspace clear.

#### Scenario: Canopy sheds particles

- **GIVEN** a canopy layer that declares an emitter (petals, leaves, drips, spores)
- **WHEN** the scene is active or asleep
- **THEN** particles fall from that layer's bounds at a bounded rate, drift with wind, and dissolve on the water with a small ripple.

### Requirement: Optional painted asset contract

Every new painted asset SHALL be optional. The game SHALL load each named
optional asset when present and SHALL render a procedural fallback when it is
absent or fails to decode, without errors visible to the player. The list of
optional assets and their exact formats SHALL be documented.

#### Scenario: Missing depth sheet

- **WHEN** `frog-meadow-depth-sheet.webp` is not bundled
- **THEN** away and toward poses render from procedural pixel art
- **AND** the scene loads normally.

### Requirement: Evolving rain intensity

Within drizzle and storm sessions rain SHALL vary continuously through a seeded
intensity envelope, including lulls and, in storms, at least one downpour.
Intensity SHALL drive drop density, streak length, impact ripples, cloud
darkening and insect shelter. Weather SHALL follow nature: clear sessions stay
dry (rain needs cloud); mist never produces showers (fog forms in stable air),
but its fog SHALL thicken as daylight fades and thin as it returns, and thick
fog MAY shed a fine fog drizzle no stronger than 0.15. Rain SHALL never produce
lightning or flashes.

#### Scenario: Fog drizzle at night

- **GIVEN** a mist session
- **WHEN** daylight is 1
- **THEN** the fog is thin and no drizzle falls
- **WHEN** daylight approaches 0
- **THEN** the fog is thick and fine drizzle may come and go, never above intensity 0.15.

#### Scenario: A storm breathes

- **GIVEN** a storm session
- **WHEN** 360 s of foreground simulation elapse
- **THEN** rain intensity spans at least 0.4 between its lowest and highest values
- **AND** it never changes by more than 0.05 per second.
