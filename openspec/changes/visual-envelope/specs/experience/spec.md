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

#### Scenario: Thunder follows the downpour, briefly

- **GIVEN** storm audio is active and the ambience receives the rain intensity
- **WHEN** a thunder slot falls while intensity is at least 0.75
- **THEN** a heavier rumble MAY sound instead of the distant one, still low-passed, with a short attack and a decay no longer than 1.6 s, and a gain capped at the level of one frog croak syllable
- **AND** heavy rumbles are at least 60 s apart, so they never repeat back to back
- **WHEN** the intensity falls below 0.75 (a lull)
- **THEN** thunder returns to the distant rumble
- **AND** no lightning, flash or screen brightening accompanies any thunder
- **AND** an ambience caller that omits the rain intensity gets distant thunder only.

### Requirement: Smooth species-specific motion including dragonflies

Insects SHALL use correlated angular drift, smoothly relaxed velocities and soft edge steering rather than independent position jitter. Dragonflies SHALL be included when their light/weather conditions allow. Base speed SHALL come from the species table: 0.12 for dragonflies, 0.045 for butterflies, 0.07 for flies, mosquitoes, ladybugs and fireflies, and each other species' own tabled value, in normalized width/second. A species MAY scale the vertical share of its heading (surface skaters stay near zero) and MAY spawn inside its altitude band. These SHALL NOT be treated as hard total-speed ceilings after wind and steering.

#### Scenario: Reproducible bounded trajectories

- **GIVEN** equal seed and input at equal simulation timestamps
- **WHEN** the pure model advances through different update partitions
- **THEN** its fixed 1/60 s steps reproduce trajectories within numerical tolerance
- **AND** velocity relaxes with factor `1-exp(-3*dt)` and position remains within x=0.04–0.96 and y=0.12–0.65, or down to a species' own floor (at most 0.72) for insects that work the water surface
- **AND** edge safety reflection remains permitted.

#### Scenario: Dragonflies and delicate insects fit the scene

- **GIVEN** light means day, or dawn with progress at least 0.55
- **WHEN** weather is clear/mist and light is present
- **THEN** dragonflies become available at progress 0.12 and ladybugs at 0.38, in the sceneries that admit them
- **AND** butterflies require clear weather and progress 0.25, in the sceneries that admit them
- **AND** mosquitoes remain available in the sceneries that admit them, flies require non-storm light, and fireflies require clear/mist twilight or darkness.

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
moths, mayflies, glow beetles, crickets or katydids. Night sets SHALL fade in
and out on continuous daylight rather than at period boundaries, and remain
within the population budget. Night insects SHALL be catchable like day insects.

#### Scenario: Grotto at night

- **GIVEN** the grotto biome at night in dry weather
- **THEN** glow beetles appear and fireflies may be absent
- **AND** each glowing insect stays visibly lit against the darkened backdrop.

#### Scenario: Sanctuary moths

- **GIVEN** the sanctuary biome at dusk
- **THEN** moths appear and favour the airspace near the lantern.

### Requirement: Insects that match the scenery

Every scenery SHALL have one or two signature insect species that appear only
there or in a few related sceneries, and some common species SHALL be absent
from sceneries they do not suit. Every scenery SHALL keep at least one species
available in every weather and at every hour. All species SHALL be catchable.
Some species MAY carry an ambient voice; that voice SHALL play only while the
species is visible on screen, synthesized, quiet, and under the same richness
and concurrency rules as the rest of the ambience. The matching SHALL be
presented as artistic natural history, not biological validation.

#### Scenario: Signature species stay home

- **WHEN** the habitat rules are evaluated for every biome across day, dusk, night, dawn and all four weathers with several rain intensities
- **THEN** each biome has at least one signature species, at least one of which appears in no more than three sceneries
- **AND** no signature species is ever available outside its declared sceneries
- **AND** stoneflies appear only in alpine, jewel beetles only in jade_sanctuary and fungus gnats only in crystal_grotto.

#### Scenario: Common species keep away where they do not fit

- **GIVEN** alpine, grotto or crystal_grotto
- **THEN** mosquitoes are never available
- **GIVEN** grotto, crystal_grotto or autumn_mist
- **THEN** butterflies are never available
- **AND** the baseline remains where it fits: willow has mosquitoes, blossom butterflies, lotus dragonflies.

#### Scenario: Singers are heard only while present

- **GIVEN** the maple biome through a clear dusk
- **WHEN** daylight is high
- **THEN** cicadas are available and crickets are not
- **WHEN** daylight reaches 0
- **THEN** crickets are available and the model reports their visible count as `cricket:N`, with no cicada entry once the cicadas have faded
- **AND** a scenery without voiced species reports an empty presence string.
