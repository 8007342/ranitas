## MODIFIED Requirements

### Requirement: Coherent seeded biomes and weather with distant thunder

The scene SHALL choose one of its twelve biomes (`willow`, `blossom`,
`cypress`, `maple`, `sanctuary`, `grotto`, `alpine`, `lotus`, `firefly`,
`autumn_mist`, `jade_sanctuary`, `crystal_grotto`) with equal seeded
probability and coherent palette/vegetation. Persistent weather SHALL be clear
50%, mist 30%, drizzle 15% or storm 5%. Within drizzle and storm, rain
intensity SHALL vary through a seeded envelope without changing the weather
kind; mist SHALL thicken toward night and MAY shed fine fog drizzle, but never
showers; clear SHALL stay dry. Gusts SHALL vary wind without replacing that weather. Storm SHALL permit
quiet distant thunder, expressly without lightning flashes. Artful
weather/species rules SHALL NOT be presented as biological validation.

#### Scenario: Seeded scene selection

- **WHEN** constructing multiple seeded sessions
- **THEN** all biome, weather and cycle choices remain within their specified sets
- **AND** repeating a seed reproduces model choices, including the rain intensity envelope
- **AND** distribution tests use a sufficiently large sample with tolerance rather than demanding exact percentages in 100 sessions.

#### Scenario: Gust warning and storm sound

- **WHEN** a gust starts after the initial 12 s clock
- **THEN** a 1.8 s wind tell precedes its 3 s sine gust with peak magnitude 0.85
- **AND** subsequent intervals are 16–36 s, or 10–30 s in storm
- **WHEN** storm audio is active
- **THEN** distant thunder may sound without a flash, using the current 22–45 s scheduling interval and 3.5 s low-pass noise voice
- **AND** listening checks assess quietness; synthesis gain alone does not prove it.

### Requirement: Gradual bounded insect emergence

Insects SHALL emerge gradually after activation with zero initial opacity, rising at 1/s. The model SHALL start with zero insects. Population growth SHALL follow richness and weather shelter, up to a target of 18 in clear/mist weather. Ambient insects SHALL continue after sleep within the population budget. Incompatible species SHALL fade at 0.3 opacity/s.

#### Scenario: Current spawn budget

- **WHEN** an active model checks spawning every 0.8 s
- **THEN** it computes `ceil((3+15*richness)*shelter*clamp(elapsed/12,0,1))`
- **AND** shelter is 1 for clear/mist; in drizzle and storm it interpolates from 0.55 at rain intensity 0.3 down to 0.25 at intensity 1, and rises toward 1 during lulls
- **AND** it spawns at most one insect when below target, giving a maximum target of 18
- **AND** a lower target does not require instant removal of existing insects.

### Requirement: Deterministic JEV companion

JEV SHALL retain analytical projection at 4 Hz, augmented by a compiled,
depth-aware 259-parameter synthetic-imitation prior that sees the target perch
and the perspective at both ends of the jump. It SHALL defer while either frog
is busy, a user action is queued or the companion is cooling down, and obey
settling/sleep. When no arc brings any insect within reach, it SHALL wait and
re-evaluate for up to 4 s before jumping anyway. The prior SHALL NOT control
timing, safety, jump thresholds or session duration. Synthetic teacher
agreement SHALL NOT be represented as real gameplay or human-study evidence.

#### Scenario: Heuristic action selection

- **WHEN** the companion is eligible to act
- **THEN** JEV evaluates ten samples for each of the three perspective-scaled arcs against projected live-insect velocity
- **AND** includes the implemented low-arc preference of 0.025 and wind penalty `abs(wind)*height*0.08`
- **AND** the nearest-live-insect prior suggestion receives only the current 0.008 additive score bonus, which can break near-ties
- **AND** landing sets a seeded cooldown of 1.1–2.4 s without remote inference.

#### Scenario: Patient companion

- **GIVEN** the companion is eligible and no insect is within reach of any arc
- **WHEN** JEV evaluates
- **THEN** it does not jump, and evaluates again 0.25 s later
- **AND** after 4 s of waiting it jumps with its best arc regardless.

#### Scenario: Synthetic evidence remains scoped

- **WHEN** reporting the 12→16→3 network trained on 24,000 synthetic depth-aware examples
- **THEN** the manifest's 93.4% agreement over 4,000 held-out synthetic examples, versus a 64.5% majority baseline, is described as teacher-action agreement
- **AND** simulation catch-per-jump figures are described as simulation, with no human study or validated calming effect inferred.

## ADDED Requirements

### Requirement: Biome night insect sets

Each biome SHALL declare which night insects appear as light fades: fireflies,
moths, mayflies or glow beetles. Night sets SHALL fade in and out on continuous
daylight rather than at period boundaries, and remain within the population
budget. Night insects SHALL be catchable like day insects.

#### Scenario: Grotto at night

- **GIVEN** the grotto biome at night in dry weather
- **THEN** glow beetles appear and fireflies may be absent
- **AND** each glowing insect stays visibly lit against the darkened backdrop.

#### Scenario: Sanctuary moths

- **GIVEN** the sanctuary biome at dusk
- **THEN** moths appear and favour the airspace near the lantern.
