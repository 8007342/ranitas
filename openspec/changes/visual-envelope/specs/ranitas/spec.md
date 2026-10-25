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
