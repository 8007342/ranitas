# Pond ambience

All sounds are original procedural Web Audio synthesis in `web/ambience.js`.
There are no downloads, samples, field recordings, music, melodies, or package
dependencies. Noise buffers, filtered oscillators, envelopes, and randomized
intervals suggest crickets, wind, reeds, droplets, frogs, owls, rain, distant
thunder, and a few insects that sing only while they are on screen (field
crickets, katydids, bees, cicadas). These are stylized synthetic impressions,
not biologically accurate calls or recordings of a real habitat.

Load the script synchronously before Flutter in the page bootstrap:

```html
<script src="ambience.js"></script>
<script src="flutter_bootstrap.js" async></script>
```

Import `lib/audio/ambience.dart` and retain one `PondAmbience` for the game.
Call `update(progress, richness, weather, sleeping, {rainIntensity, species, elapsedSeconds})`
as game state changes. Progress and richness accept normalized numbers; invalid
numbers become zero. Progress is reserved for future scene evolution; richness
controls overall gain and density. `elapsedSeconds` follows foreground play
time: the master fades from silence over ten seconds, while water, breeze,
rain, insect voices, frogs and distant calls enter on staggered smooth curves
over three minutes. See [the choreography](quiet-awakening.md). The completed
mix remains present after sleep. Weather strings containing
rain/storm/thunder (or lluvia/tormenta) enable full rain; drizzle uses 35% rain
gain and a gentler wind increase. Storm/thunder/tormenta also enable thunder.
Sleeping permits occasional owl calls without dropping the finished mix level.

The additional arguments are optional at both ends. JavaScript accepts the old
four-argument form, derives a reveal time from richness, and retains distant
thunder without species voices when those arguments are omitted.

**Thunder follows the rain.** `rainIntensity` (0–1, the model's rain envelope)
shapes thunder while the storm label is active. A pure `thunderPlan(rain, now,
lastHeavyAt, rnd)` chooses each rumble: the distant rumble is unchanged
(low-pass 180 Hz noise, 3.5 s, gain 0.18, every 22–45 s). While the rain is a
downpour (intensity ≥ 0.75) a heavier rumble may take a slot instead, with a
35–75 % chance rising with intensity, never within 60 s of the previous heavy
one. It stays brief and soft: 0.05 s attack, 1.6 s decay, low-passed at 260 Hz,
gain capped at 0.26, which is the level of one croak syllable. Lulls fall under
the threshold and return to distant rumbles on their own. There is never a
lightning flash; the picture does not react to thunder. `thunderPlan`,
`parseSpecies` and the `thunderLimits` constants are exposed on
`window.ranitasAudio` for tests only; `npm run test:ambience` runs them under
Node with a stub window and no `AudioContext`.

**Insect voices.** `species` is the model's compact presence string of visible
voiced insects, for example `cricket:3,bee:1` (`PondModel.speciesPresence`;
only insects at opacity ≥ 0.25 count, so a voice ends with the last singer).
Each voice plays only while its count is positive, follows the richness-scaled
intervals of the other events, shares the 24-voice limit, and gets slightly
denser, never louder, with more singers (gain saturates at three):

| Voice | Species / sceneries | Synthesis | Gain |
| --- | --- | --- | --- |
| `cricket` | field crickets at night in maple and autumn_mist | four 50 ms sine pulses at 4.1–4.8 kHz, every 0.9–2.4 s, above the generic cricket bed | ≤ 0.028 |
| `katydid` | katydids at night in cypress and firefly | three 70 ms bandpassed noise ticks (2.9–3.5 kHz, Q 5), every 2.4–6 s | ≤ 0.04 |
| `bee` | bees by day in blossom, sanctuary, jade_sanctuary, alpine | 215–250 Hz sawtooth under a 1.1 kHz lowpass, 1.1–1.9 s with a slow attack, panned, every 3–7.5 s | ≤ 0.03 |
| `cicada` | cicadas on warm afternoons in maple, sanctuary, jade_sanctuary | 104–126 Hz square under a 4.2 kHz lowpass, 2.6–4.2 s swell with a 1 s attack, every 7–15 s | ≤ 0.022 |

Water striders, whirligigs, damselflies, craneflies, stoneflies, cave crickets,
jewel beetles and fungus gnats are silent.

Browser capture-phase pointerdown and Space/Enter keydown listeners synchronously
create/resume a single context with zero master gain, before Flutter handles the
event. Matching trusted pointerup/keyup also synchronously retries resume,
even while the press attempt is pending, for mobile release-time activation.
A canceled pointer never completes the release gate or starts audio. Older
resume results cannot override the latest release attempt. Keyboard repeats, composition, modified shortcuts (Alt/Ctrl/Meta), other
keys, and synthetic unlock events are ignored. The listeners do not prevent
browser defaults or stop propagation to Flutter.

Updates before that gesture cannot arm playback. The unlocking pointer or key
must be released, followed by a positive-richness update, before audio begins.
Schedule the first game update after pointerup/keyup (or the subsequent frame);
a pointerdown/keydown-only update intentionally stays silent. An unrelated key
or pointer release does not complete a keyboard unlock. No automatic unlock is
attempted. Browser autoplay policy may still block playback. A rejected resume
mutes and suspends the existing context and resets the unlock/release state;
the matching trusted release or next real pointerdown/Space/Enter keydown
retries synchronously, without
creating another context. Scene updates are retained even before unlocking.
Updates after release while resume is pending are applied when it succeeds;
pre-gesture updates alone still cannot start playback. After rejection, a new
gesture release and positive-richness update are required again.

Hidden tabs immediately mute, cancel the scheduler, stop transient voices, and
suspend the context. Visibility restores only previously started, unsuspended
ambience. Explicit suspend persists across visibility changes. Resume never
starts an unstarted scene. Reduced-motion preferences do not imply audio mute.
Use richness zero to fade to silence; use suspend for immediate silence.

There are three looping noise beds, at most 24 short voices, and one 250 ms
scheduler. Events schedule at most 0.95 seconds ahead; missed events never catch
up in a burst. Ended voices disconnect every node. Dispose removes listeners,
stops sources, disconnects nodes, clears the interval, and closes the singleton
context permanently for that page. Multiple Dart wrappers share this lifecycle;
disposing one ends audio for all of them. Reload the page to recreate it.

The master target is bounded to 0–0.32, with quieter sleeping gain and smooth
normal transitions. Perceived loudness depends on browser and device volume.
The script must be included by the host page; this change does not edit the
shared bootstrap or introduce Flutter call sites.

Native Flutter targets currently use `ambience_stub.dart`: all four methods are
intentional no-ops and produce no audio. Web Audio is browser-only. Native
synthesis could be added through Flutter MethodChannels, but a Dart channel alone
cannot synthesize sound: each supported platform would need a registered channel
handler, a native synthesis/audio engine, and lifecycle/audio-focus handling.
Those platform implementations are outside this web target and are not supplied.
