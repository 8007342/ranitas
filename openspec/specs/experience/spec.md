# Pond experience

## Purpose

A tranquil Flutter/Flame pixel pond with two frogs, three hold-selected jumps, a deterministic JEV companion, gradual enrichment, coherent randomized weather/biomes, and a bounded adaptive foreground session ending in sleep and endless ambience. This contract follows the agreed user request and current model; [research.md](../../../docs/research.md) separates primary evidence from implementation choices. No human user study has been conducted. No numeric parameter is claimed research-validated.

## Requirements

### Requirement: Two frogs without a HUD or score

The app SHALL present two pixel-art frogs directly in a coherent pond without a persistent HUD, score, countdown, currency, leaderboard, loss screen or completion dialog. Watching SHALL be valid participation. Flutter SHALL host the Flame scene, with logical model coordinates independent of display pixels.

#### Scenario: Opening without input

- **WHEN** the user watches the initial pond without completing a gesture
- **THEN** both frogs remain at their home leaves, the session clock and enrichment do not advance, and audio remains silent
- **AND** no interaction or catch quota is demanded.

### Requirement: Completed gesture activates play and gradual sound

The first completed pond gesture SHALL start play. Audio SHALL remain silent beforehand. Browser input may unlock a zero-gain context on pointer-down or Space/Enter keydown, but audible playback SHALL require gesture completion and a subsequent positive-richness update. Audio failure SHALL not block the pond. Native audio may remain a silent stub.

#### Scenario: Hold, release and cancellation

- **WHEN** a user holds without releasing the first gesture
- **THEN** neither the foreground session nor audible ambience begins
- **WHEN** that gesture is cancelled
- **THEN** no jump or session start occurs
- **WHEN** a subsequent intentional gesture completes
- **THEN** play begins and successfully unlocked audio grows with richness; no separate start screen appears.

### Requirement: Three stable hold-selected jumps

Pond-wide pointer input and Space/Enter SHALL control frog 0; frog 1 SHALL use JEV. Release below 0.18 s SHALL select tap, 0.18–below 0.65 s low, and at least 0.65 s high. Holding SHALL not auto-launch. Duplicate press SHALL not reset charge. While either frog is busy, only the most recent completed action SHALL be retained. Cancellation SHALL clear charge without launching.

#### Scenario: Exact hold boundaries

- **WHEN** separate gestures last 0, 179, 180, 649, 650 and 1500 ms
- **THEN** the actions are tap, tap, low, low, high and high
- **AND** the 1500 ms hold produces no action before release.

#### Scenario: Rapid input stays bounded

- **GIVEN** a frog is in flight or swimming
- **WHEN** the user completes several gestures
- **THEN** at most one latest action remains queued
- **AND** it dispatches after the pond is free, unless settling discards it.

### Requirement: Consistent arcs and harmless recovery

Tap, low and high SHALL use durations 0.68, 0.95 and 1.30 seconds and sine-arc heights 0.13, 0.25 and 0.39 logical pond heights. Companion arcs SHALL add 0.018 height for silhouette separation. Flights and swims SHALL be serialized. Wind, chaotic-tapping, and occasional underwater-pad disturbances SHALL recover without score loss or a failure state. Adaptive timing and JEV SHALL NOT alter user thresholds or arc constants.

#### Scenario: Crossing and a wind mishap

- **WHEN** a frog crosses between leaves
- **THEN** it uses the selected arc and safe perch offset without simultaneous frog flight
- **AND** a gust-related belly flop, if selected, returns it to the destination leaf through a 1.6 s swim
- **AND** misses and catches do not gate scene progression.

### Requirement: Bounded adaptive foreground duration

Normal active sessions SHALL adapt within 180–360 foreground simulation seconds, starting with a 240 s target. Engagement SHALL be a local interaction-rate proxy, never a claim about emotion. Accepted releases MAY extend the target within its bound but SHALL NOT reset elapsed time. Preview/test duration overrides SHALL remain separate from normal play.

#### Scenario: Implemented adaptation rule

- **GIVEN** a normal session with no duration override
- **WHEN** a release is accepted
- **THEN** engagement increases by 0.075, capped at 1
- **AND** each active update decays engagement by `exp(-dt/18)` and moves duration toward `180 + 180*engagement` by factor `1-exp(-dt/12)`, clamping duration to 180–360 s.

#### Scenario: Idle and sustained interaction both finish

- **WHEN** running one session with only its initial gesture and another with frequent accepted releases
- **THEN** each enters settling when elapsed reaches its current duration, no later than 360 foreground simulation seconds plus one 1/60 s step
- **AND** neither can be prolonged indefinitely by interaction.

### Requirement: Monotone enrichment into dusk or dawn

Scene richness SHALL follow monotone smoothed session progress. The seeded cycle SHALL be dusk with probability 75% or dawn with probability 25%. Palette and environmental detail SHALL develop gradually without lightning flashes, flicker or scene cuts. The cycle SHALL retain its endpoint after sleep. No requirement SHALL depend on a human failing to notice a change.

#### Scenario: Adaptation never reverses the scene

- **WHEN** the duration target changes during a session
- **THEN** `f=clamp(elapsed/duration,0,1)`, `progress=max(previousProgress,f*f*(3-2*f))`, and `richness=progress`
- **AND** progress does not decrease even when engagement raises duration.

#### Scenario: Cycle landmarks

- **GIVEN** a dusk cycle
- **WHEN** progress crosses 0.55 and 0.85
- **THEN** the period moves from day to dusk to night
- **GIVEN** a dawn cycle
- **WHEN** progress crosses 0.20 and 0.85
- **THEN** the period moves from night to dawn to day
- **AND** daylight interpolation is `1-progress` for dusk and `progress` for dawn.

### Requirement: Settling returns frogs home before endless rest

At the adaptive endpoint the model SHALL discard queued input, cancel charge and stop ordinary jumps. It SHALL let existing flight/swimming finish, return each visiting frog home through serialized low jumps, then set both asleep. Short return choreography MAY follow the active-session bound. Ambient insects, water and sound SHALL continue afterward without an automatic restart or wake-up.

#### Scenario: A busy endpoint

- **GIVEN** a frog is airborne or swimming when elapsed reaches duration
- **WHEN** settling begins
- **THEN** that motion completes and each frog away from home returns with a 0.95 s low jump
- **AND** both sleep on their own leaves without teleporting or an end dialog.

#### Scenario: Staying after sleep

- **WHEN** the scene remains foregrounded for 30 minutes after sleep and receives additional taps
- **THEN** the frogs remain asleep and the endpoint palette holds
- **AND** ambience continues with bounded insect population, no score summary and no replay prompt.

### Requirement: Deterministic JEV companion

JEV SHALL retain analytical projection at 4 Hz, augmented by the compiled 147-parameter synthetic-imitation prior. It SHALL defer while either frog is busy, a user action is queued or the companion is cooling down, and obey settling/sleep. The prior SHALL NOT control timing, safety, jump thresholds or session duration. Synthetic teacher agreement SHALL NOT be represented as real gameplay or human-study evidence.

#### Scenario: Heuristic action selection

- **WHEN** the companion is eligible to act
- **THEN** JEV evaluates ten samples for each of the three arcs against projected live-insect velocity
- **AND** includes the implemented low-arc preference of 0.025 and wind penalty `abs(wind)*height*0.08`
- **AND** the nearest-live-insect prior suggestion receives only the current 0.008 additive score bonus, which can break near-ties
- **AND** landing sets a seeded cooldown of 1.1–2.4 s without remote inference.

#### Scenario: Synthetic evidence remains scoped

- **WHEN** reporting the 8→12→3 network trained on 18,000 synthetic examples
- **THEN** the manifest’s 94.4% agreement over 4,000 held-out synthetic examples, versus 60.6% majority baseline, is described as teacher-action agreement
- **AND** no actual catch-rate improvement, human study or validated calming effect is inferred.

### Requirement: Gradual bounded insect emergence

Insects SHALL emerge gradually after activation with zero initial opacity, rising at 1/s. The model SHALL start with zero insects. Population growth SHALL follow richness and weather shelter, up to a target of 18 in clear/mist weather. Ambient insects SHALL continue after sleep within the population budget. Incompatible species SHALL fade at 0.3 opacity/s.

#### Scenario: Current spawn budget

- **WHEN** an active model checks spawning every 0.8 s
- **THEN** it computes `ceil((3+15*richness)*shelter*clamp(elapsed/12,0,1))`
- **AND** shelter is 1 for clear/mist, 0.55 for drizzle and 0.25 for storm
- **AND** it spawns at most one insect when below target, giving maximum targets of 18, 10 and 5 respectively
- **AND** a lower target does not require instant removal of existing insects.

### Requirement: Smooth species-specific motion including dragonflies

Insects SHALL use correlated angular drift, smoothly relaxed velocities and soft edge steering rather than independent position jitter. Dragonflies SHALL be included when their light/weather conditions allow. Base speed SHALL be 0.12 for dragonflies, 0.045 for butterflies and 0.07 for others in normalized width/second. These SHALL NOT be treated as hard total-speed ceilings after wind and steering.

#### Scenario: Reproducible bounded trajectories

- **GIVEN** equal seed and input at equal simulation timestamps
- **WHEN** the pure model advances through different update partitions
- **THEN** its fixed 1/60 s steps reproduce trajectories within numerical tolerance
- **AND** velocity relaxes with factor `1-exp(-3*dt)` and position remains within x=0.04–0.96 and y=0.12–0.65
- **AND** edge safety reflection remains permitted.

#### Scenario: Dragonflies and delicate insects fit the scene

- **GIVEN** light means day, or dawn with progress at least 0.55
- **WHEN** weather is clear/mist and light is present
- **THEN** dragonflies become available at progress 0.12 and ladybugs at 0.38
- **AND** butterflies require clear weather and progress 0.25
- **AND** mosquitoes remain available, flies require non-storm light, and fireflies require clear/mist twilight or darkness.

### Requirement: Coherent seeded biomes and weather with distant thunder

The scene SHALL choose willow, blossom or cypress with equal seeded probability and coherent palette/vegetation. Persistent weather SHALL be clear 50%, mist 30%, drizzle 15% or storm 5%. Gusts SHALL vary wind without replacing that weather. Storm SHALL permit quiet distant thunder, expressly without lightning flashes. Artful weather/species rules SHALL NOT be presented as biological validation.

#### Scenario: Seeded scene selection

- **WHEN** constructing multiple seeded sessions
- **THEN** all biome, weather and cycle choices remain within their specified sets
- **AND** repeating a seed reproduces model choices
- **AND** distribution tests use a sufficiently large sample with tolerance rather than demanding exact percentages in 100 sessions.

#### Scenario: Gust warning and storm sound

- **WHEN** a gust starts after the initial 12 s clock
- **THEN** a 1.8 s wind tell precedes its 3 s sine gust with peak magnitude 0.85
- **AND** subsequent intervals are 16–36 s, or 10–30 s in storm
- **WHEN** storm audio is active
- **THEN** distant thunder may sound without a flash, using the current 22–45 s scheduling interval and 3.5 s low-pass noise voice
- **AND** listening checks assess quietness; synthesis gain alone does not prove it.

### Requirement: Respectful engagement and lifecycle

The app SHALL avoid streaks, scarcity rewards, catch quotas, loss penalties, return notifications and psychological profiling. Bounded adaptation SHALL honor the requested engagement length without resetting progress. Backgrounding SHALL cancel hold, pause simulation and suspend sound. Foregrounding MAY resume previously activated ambience without a fresh gesture but SHALL NOT start an unactivated session or replay missed events.

#### Scenario: Background during charge

- **GIVEN** an active scene at 100 foreground simulation seconds with a pending hold
- **WHEN** it backgrounds for ten minutes and returns
- **THEN** charge is cancelled and simulation continues from its prior state without ten minutes of catch-up
- **AND** previously activated audio may resume subject to browser policy, without a sound backlog.

#### Scenario: Honest evidence boundary

- **WHEN** reporting implementation or validation
- **THEN** automated checks are described as technical checks, JEV as deterministic analytical projection with a trained synthetic-imitation prior, and duration/motion values as authored parameters
- **AND** no human study, calming effect or research validation is claimed without corresponding evidence.
