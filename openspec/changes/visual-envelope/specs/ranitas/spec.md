## MODIFIED Requirements

### Requirement: Expressive multi-state frog animations

Both frogs SHALL animate across ten distinct visual states: `idle`, `charging`,
`launching`, `ascending`, `chomping`, `falling`, `landing`, `swallowing`,
`swimming`, and `sleeping`. Catching an insect in mid-air SHALL trigger a
`chomping` pose and tongue strike in flight, followed upon landing by a
post-landing `swallowing` animation (cheek puff, throat bulge, and gulp).
Airborne states SHALL additionally have away (back view) and toward (front
view) variants chosen by jump direction, drawn from an optional painted depth
sheet or from procedural pixel art.

#### Scenario: Mid-air catch and post-landing swallow

- **WHEN** a jumping frog intercepts a live insect in flight
- **THEN** it enters `chomping` with an extended tongue and records the catch
- **AND** upon landing on the destination lily pad it plays the `landing` squash followed by the `swallowing` animation

#### Scenario: Depth jump uses a view variant

- **WHEN** a frog jumps toward the viewer
- **THEN** its launching, ascending, falling and chomping poses use the front view.

### Requirement: The world supports large high-resolution landscape screens

The game SHALL maintain a widescreen landscape playfield on every screen
orientation. Native platforms SHALL request landscape orientation. Scenic and
foreground exports SHALL be a whole-number multiple of their source art
(currently `2752 × 1536`, exactly 2 × `1376 × 768`), so that every source pixel
becomes an equal block and no uneven resample is baked into the files. Frog
character sprite sheets SHALL use `1031 × 521` dimensions, and the animated
logical canvas SHALL be `641 × 359`. Pixel scaling SHALL be controlled
explicitly rather than relying on primality.

#### Scenario: A high-resolution widescreen display

- **WHEN** the browser renders on a widescreen or ultrawide display
- **THEN** the complete 641:359 landscape playfield remains centered with surrounding background
- **AND** the frog landing zones remain inside the playfield

#### Scenario: Exact export blocks

- **WHEN** a scenic export is sampled back down by its whole-number factor
- **THEN** it reproduces its source art pixel for pixel.
