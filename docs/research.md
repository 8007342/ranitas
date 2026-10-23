# Ranitas: evidence and experience design

Research date: 2026-10-23. Scope: tranquil Flutter/Flame pixel pond, two frogs, no HUD or score, sound unlocked by first interaction, three hold-selected jumps, gradual enrichment, coherent biome/weather variation, and eventual sleep with endless ambience.

**No human user study has been conducted for Ranitas.** This is source review and design specification, not evidence that the prototype calms people, improves health, produces change blindness, or increases enjoyment. All Ranitas numbers below are initial design parameters, not experimentally established thresholds. Acceptance scenarios specify future checks; they are not a claim that implementation or tests have passed.

## Primary findings and limits

### Valve: govern pacing with a small state machine

Michael Booth's Valve presentation describes an intensity estimate derived from gameplay events, decaying over time, and uses the maximum across survivors. Its director moves through Build Up, Sustain Peak, Peak Fade, and Relax. Peak Fade allows ongoing action to finish before consuming the rest interval. The published example sustains a peak for 3–5 seconds and relaxes for 30–45 seconds, with a progress-based escape. Booth explicitly distinguishes changing encounter frequency from changing difficulty. These are survival-horror design observations, not a controlled study of tranquil games. [Booth, *The AI Systems of Left 4 Dead*, 2009, PDF pages 79–82 and 92](https://cdn.cloudflare.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf).

Ranitas adaptation: use bounded foreground duration, companion cooldowns, gradual richness and a final settling state. The actual model does not implement Valve’s four-state director. Interaction can extend the target session within 180–360 seconds; it never resets elapsed time or reverses progress. Jumps and return swims finish before sleep. Jump physics and catch tolerance remain stable. The engagement variable is an interaction-rate proxy, not a measurement of emotion. Valve’s numbers are historical source details, not Ranitas settings.

### Gradual change: reduced transients can hide even large changes

Simons, Franconeri and Reimer report two experiments showing change blindness without an intervening visual disruption. Their abstract says sufficiently gradual changes sometimes fail to attract attention; one experiment produced more detections with a disruption than without. The accessible publisher abstract supports this qualitative claim, but supplies no reusable Ranitas timing threshold. [*Change Blindness in the Absence of a Visual Disruption*, Perception 29(10), 1143–1154, 2000](https://journals.sagepub.com/doi/10.1068/p3104).

Rensink, O'Regan and Clark's interruption experiments concern brief blanks between scene versions and support a role for focused attention in change detection. This is a different manipulation from smooth enrichment. [Author-hosted abstract, *On the Failure to Detect Changes in Scenes Across Brief Interruptions*, 2000](https://www2.psych.ubc.ca/~rensink/publications/abs.00.12.html).

Ranitas interpretation: interpolate lighting and reveal small environmental details slowly, while keeping frogs and landing places readable. Do not add flicker, blank screens, camera cuts, or distraction tricks to conceal changes. A viewer noticing every change is acceptable. “Gradual” and “calming” are separate hypotheses; neither paper establishes therapeutic benefit or an ethical mandate to hide changes.

### Atrapa: verified tiny local weights, with provenance caveats

Inspected repository snapshot: [`8007342/atrapa`, commit `df3d4f3e16b2353013c4d625e8e3a7617b1b236e`](https://github.com/8007342/atrapa/tree/df3d4f3e16b2353013c4d625e8e3a7617b1b236e). The Atrapa Markdown inspection did not establish an expansion for “JEV.” Ranitas now explicitly names its own `_evaluateJev` routine: deterministic analytical jump evaluation augmented by a small synthetic-imitation prior. This local implementation is verified separately from the Atrapa learned-policy reference.

| Evidence inspected | What it establishes |
| --- | --- |
| [Trainer README](https://github.com/8007342/atrapa/blob/df3d4f3e16b2353013c4d625e8e3a7617b1b236e/packages/atrapa_train/README.md) | Describes a shared pure-Dart simulation/encoder, imitation from a free-space teacher, then REINFORCE self-play against snapshots and teacher; separate selection/evaluation seeds; exported parity observations/logits/actions. |
| [Delivered manifest](https://github.com/8007342/atrapa/blob/df3d4f3e16b2353013c4d625e8e3a7617b1b236e/assets/policies/default/manifest.json) | Declares `freespace-v1-2026-10-22-it2575`, dense 252→64→32→3, ReLU hidden layers, linear logits, 18,371 parameters, float32 little-endian weights and SHA-256. Repository tree lists weights.bin as 73,484 bytes (about 71.8 KiB), consistent with 4 bytes per parameter. Reports training/evaluation provenance; results were not independently reproduced here. |
| [Dart evaluator](https://github.com/8007342/atrapa/blob/df3d4f3e16b2353013c4d625e8e3a7617b1b236e/lib/policy/local_policy.dart) | Checks checksum, schemas, action order, connected dimensions, finite values, byte count and output shape; chooses first maximum logit. It caps weight bytes at 400,000 and layer count at 16. Inference owns neither game state nor time. |
| [Bundle contract](https://github.com/8007342/atrapa/blob/df3d4f3e16b2353013c4d625e8e3a7617b1b236e/docs/policy-bundle.md) | Requires baseline fallback, parity tolerance and immutable local weights. Its opening “no trained game weights” status is stale relative to the committed manifest/binary; the example 252→64→3 architecture is not the delivered architecture. |

Current Ranitas now includes a trained **synthetic geometric imitation prior**, alongside analytical JEV. [Training source](../scripts/train-policy.mjs), [compiled Dart constants](../lib/game/jump_policy.dart) and [manifest](../assets/policy/manifest.json) show an 8→12→3 tanh/softmax network with 147 parameters, trained offline on 18,000 synthetic examples. The manifest reports 3,776/4,000 held-out teacher-action agreements (94.4%), versus a 60.6% majority-action baseline, evaluated after rounding export weights to six decimal places. This documentation pass inspected artifacts; it did not rerun training. The announced companion `docs/policy.md` was not yet present at inspection.

The synthetic dataset retains single-insect geometric states where at least one candidate arc passes within 0.13 normalized distance. Separate seeded training and held-out samples measure imitation on that generator, not actual catches, complete multi-insect gameplay, latency on devices, comfort or human preference. **No human user study has been conducted.** The result does not establish real gameplay improvement or validate any experience parameter.

Current integration keeps analytical projection at 4 Hz and applies the prior's nearest-live-insect suggestion as a small additive score bonus: **0.008 in the inspected model** (approximately the announced 0.01). It can affect near-tied scores, not only exact ties. Analytical projection, cooldowns, user-input priority, fixed arcs and settling remain authoritative. This is deterministic inference from learned constants, with no online training or inference service. The policy evaluator falls back to the low action for invalid features/numerics. Further learned control remains optional future work; the existing prior must no longer be described as merely proposed. A paired prior-on/off gameplay evaluation would be needed before claiming benefit.

## Synchronized implementation parameters

Synchronized against the current shared `lib/game/pond_model.dart`, `lib/main.dart`, `lib/game/ranitas_game.dart`, `web/ambience.js` and `test/pond_model_test.dart` on 2026-10-23. These are authored implementation choices, not research-validated parameters. Tests were read, not executed as part of this documentation update. Concurrent implementation changes may require another synchronization.

| System | Current behavior / parameter |
| --- | --- |
| Start and audio | The first completed pond gesture starts play. Pointer-down or Space/Enter keydown may unlock a zero-gain Web Audio context; playback additionally requires release and a subsequent positive-richness update. No fixed two-second intro fade is specified. Native audio is currently a silent stub. |
| Input | Anywhere in the pond controls frog 0; frog 1 is JEV-controlled. Release <0.18 s selects `tap`, 0.18–<0.65 s `low`, ≥0.65 s `high`. No hold-triggered automatic launch. Duplicate press is ignored; cancellation does not start play. While busy, only the latest gesture is retained. |
| Arcs | Tap/low/high durations 0.68/0.95/1.30 s; sine-arc heights 0.13/0.25/0.39 of logical pond height. Companion adds 0.018 height to separate silhouettes. Flights/swims are serialized. |
| Adaptive foreground session | Initial target 240 s. Each accepted release adds 0.075 to engagement, capped at 1; decay `exp(-dt/18)`. Target approaches `180 + 180 * engagement` with factor `1-exp(-dt/12)`, clamped to 180–360 s. Elapsed time is never reset. |
| Progress/enrichment | `f=clamp(elapsed/duration,0,1)`; `progress=max(previousProgress, f*f*(3-2*f))`; `richness=progress`. This replaces scheduled detail reveals and a fixed eight-minute arc. |
| Settling and sleep | At elapsed ≥ duration, discard queued action, cancel hold and stop ordinary launches. Finish existing flight/swim, then sequential 0.95 s low returns for frogs away from home; sleep when both are home. The 180–360 s bound applies to active foreground play, followed by this short return choreography. |
| JEV | Evaluate at 4 Hz; skip when either frog is busy, companion is cooling down or user action is queued. Evaluate 10 samples on each of three candidate arcs against projected insect velocity. Add low-arc preference 0.025; penalize wind × arc height × 0.08. Landing cooldown 1.1–2.4 s. Compiled 147-parameter synthetic-imitation prior contributes a 0.008 suggestion bonus; no online learning, model download or remote inference. |
| Insect emergence | The latest model starts with **zero** bugs, then checks spawning every 0.8 s after activation. Earlier code created seven immediately; that has been superseded by gradual emergence. Spawn opacity is 0, rising at 1/s; incompatible species fade at 0.3/s. |
| Insect population | Target `ceil((3 + 15*richness) * shelter * clamp(elapsed/12,0,1))`; shelter is 1 for clear/mist, 0.55 drizzle, 0.25 storm. Maximum targets are 18, 10 and 5 respectively. One bug is spawned per eligible check. This is a spawn target, not instant population replacement. Sleep retains ambient insects. |
| Insect movement | Base speeds: dragonfly 0.12, butterfly 0.045, others 0.07 normalized width/s. Correlated angular noise, velocity relaxation `1-exp(-3*dt)`, wind drift and soft edge steering; hard safety bounds x=0.04–0.96 and y=0.12–0.65. These base speeds are not hard total-speed ceilings. |
| Biome/cycle | Seeded uniform choice of willow, blossom or cypress; dusk 75%, dawn 25%. Dusk period thresholds: day before progress 0.55, dusk before 0.85, then night. Dawn: night before 0.20, dawn before 0.85, then day. Endpoint holds after sleep. |
| Weather | Persistent seeded clear 50%, mist 30%, drizzle 15%, storm 5%. Gusts vary wind without replacing weather. Storm is allowed with quiet distant thunder; no lightning flashes. |
| Gusts and recovery | Initial gust clock 12 s; 1.8 s visible tell followed by a 3 s sine gust, peak magnitude 0.85. Later intervals 16–36 s, or 10–30 s in storm. Wind decays during settling/sleep. Gust landings may cause a harmless 1.6 s return swim, never a loss. |
| Audio levels | Web master target `0.32*richness`, multiplied by 0.7 while sleeping, smoothed with 0.6 s time constant. Storm thunder: low-pass noise at 180 Hz, 3.5 s voice, gain 0.12 before master, scheduling interval 22–45 s. These synthesis gains do not establish perceived loudness on a device. |

The current model uses fixed 1/60 s substeps and a seeded random generator. Equal seed plus equal timestamped input reproduces model behavior across update partitions; procedural audio uses separate browser randomness. The Flame adapter currently clamps frame deltas to 0.05 s, so session bounds refer to accumulated foreground simulation time, not a guarantee of wall-clock duration during stalls.

## Coherent biomes, weather and species

Willow, blossom and cypress are the agreed art profiles. Keep their palettes, bank vegetation, water and reflected lighting coherent across the whole scene. They are art-direction categories, not ecological survey results. Persistent weather and the dusk/dawn cycle supply the current model’s species filters; do not invent a separate biome-specific species matrix or enforce the superseded marsh/woodland/meadow profiles.

Mosquitoes remain available. Flies require light and non-storm weather. Dragonflies require clear/mist weather, light and progress ≥0.12; butterflies require clear weather, light and progress ≥0.25; ladybugs require clear/mist weather, light and progress ≥0.38. Fireflies require clear/mist weather and darkness/twilight. In this model light means `period == day`, or dawn with progress ≥0.55. Existing incompatible insects fade rather than vanishing instantly. These are stylized habitat rules, not biological claims. Dragonflies are expressly included, with faster smooth trajectories than butterflies.

The audio bridge currently recognizes rain/storm/thunder strings for its rain bed. The model emits `drizzle`; that exact token is not recognized by the inspected audio rain regex. This is an integration gap to check with the audio owner, not a reason to rename agreed weather or edit code in this task. Thunder support already exists for `storm`; perceived quietness still needs listening checks. No flash is necessary or allowed.

## Ethical engagement and validation

The goal is comfortable voluntary presence, including the user-requested adaptive 3–6 minute active session. Interaction may extend duration within that bound; it must not endlessly defer rest, reverse scene progress or change jump thresholds to induce more play. The existing engagement scalar is a local activity proxy, not a psychological diagnosis. Ordinary companion jumps continue without input; the earlier proposed ban on new activity after 20 idle seconds is not part of this implementation.

There are no scores, streaks, currency, scarcity rewards, catch quotas, loss states, return notifications or automatic replay. Sleep is reached even after one gesture and no further input. After sleep, ambient water, insects and sound continue indefinitely without an automatic wake-up or mandatory restart. The user can leave freely.

Backgrounding cancels pending hold, pauses the engine and suspends audio. Foreground return may resume previously started ambience; a new unlock is not required for every return. It cannot start a never-activated session or play a backlog of missed events. The current input surface includes a semantic description and Space/Enter alternatives. Separate mute/reduced-motion controls remain possible future accessibility work; they are not claimed implemented or newly imposed as release requirements here.

Engineering validation should cover hold boundaries, latest-action queue behavior, seeded model replay, monotone progress under changing duration, completion after idle and sustained input, return swims, species filtering, weather/cycle probabilities, and bounded ambient population after sleep. Audio requires gesture, cancellation, lifecycle and storm listening checks. These checks establish technical behavior only. No human user study has been conducted. A future voluntary study should report consent, methods, sample, limitations and negative responses; it must not call automated play a human study or treat session length as proof of wellbeing.

## Superseded research proposals

The previous fixed 480 s session, 250 ms first hold threshold, 0.65/0.85/1.05 s arcs, 0.08/0.14/0.21 heights, three-awake/one-asleep bug caps, 20–40 s director quiet states, six timed reveals, marsh/woodland/meadow profiles, 50/50 dusk/dawn, thunder prohibition and mandatory fresh-gesture resume were unvalidated proposals. They are **rejected alternatives, not requirements**. The earlier seven-bug constructor has also been replaced in the latest model by gradual zero-to-target emergence. No cited paper validated either set of game parameters.

## Integration handoff

The [experience spec](../openspec/specs/experience/spec.md) follows the agreed experience and inspected model. Describe JEV as analytical projection with a small trained synthetic-imitation prior; preserve stable hold thresholds, monotone 180–360 s adaptive progress and guaranteed settling. Teacher-action agreement is not gameplay efficacy. Preserve storm thunder and dragonflies. Verify the drizzle-to-audio mapping and listen to thunder on real output devices. Recheck concurrent model changes before claiming a final implementation snapshot; acceptance scenarios below are checks to run, not a claim of completed validation.
