## ADDED Requirements

### Requirement: Perspective-scaled frogs

A frog's rendered size SHALL follow the perspective of the point on the pond
beneath it, including during flight, so jumps between pads at different depths
grow or shrink the frog smoothly. Arc height SHALL scale with the same factor.
Flight duration SHALL not change with depth.

#### Scenario: Jumping away

- **GIVEN** a source pad nearer the viewer than the target pad
- **WHEN** the frog jumps
- **THEN** its rendered size decreases monotonically through the flight
- **AND** it lands at the target pad's perspective scale.

### Requirement: Direction-aware jump views

Jumps SHALL select side, away (back view) or toward (front view) poses from the
jump's screen-space direction. Mostly horizontal jumps SHALL use the existing
side poses mirrored by direction. Away and toward views SHALL cover launch,
ascent and descent, and toward views SHALL include a catch pose.

#### Scenario: Jump to a far pad

- **WHEN** the jump direction is more than 35° up-screen from horizontal after depth weighting
- **THEN** the frog shows its back-view launch, ascent and descent poses.

### Requirement: Atmospheric depth cues

Frogs farther from the viewer SHALL appear slightly hazier and less opaque, more
so at night, and their shadows and reflections SHALL scale with perspective.
Frogs SHALL be ordered with pads by depth so a far frog passes behind near pads.

#### Scenario: Far frog at night

- **GIVEN** a frog on the farthest pad at night
- **THEN** it is drawn with visible haze and reduced opacity but remains clearly recognisable.
