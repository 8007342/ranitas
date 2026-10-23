# Pond ambience

All sounds are original procedural Web Audio synthesis in `web/ambience.js`.
There are no downloads, samples, field recordings, music, melodies, or package
dependencies. Noise buffers, filtered oscillators, envelopes, and randomized
intervals suggest crickets, wind, reeds, droplets, frogs, owls, rain, and distant
thunder. These are stylized synthetic impressions, not biologically accurate
calls or recordings of a real habitat.

Load the script synchronously before Flutter in the page bootstrap:

```html
<script src="ambience.js"></script>
<script src="flutter_bootstrap.js" async></script>
```

Import `lib/audio/ambience.dart` and retain one `PondAmbience` for the game.
Call `update(progress, richness, weather, sleeping)` as game state changes.
Progress and richness accept normalized numbers; invalid numbers become zero.
Progress is reserved for future scene evolution; richness controls overall gain
and frog density. Weather strings containing rain/storm/thunder (or
lluvia/tormenta) enable rain; storm/thunder/tormenta also enable thunder.
Sleeping softens overall gain and adds occasional owl calls.

Browser capture-phase pointerdown and Space/Enter keydown listeners synchronously
create/resume a single context with zero master gain, before Flutter handles the
event. Keyboard repeats, composition, modified shortcuts (Alt/Ctrl/Meta), other
keys, and synthetic unlock events are ignored. The listeners do not prevent
browser defaults or stop propagation to Flutter.

Updates before that gesture cannot arm playback. The unlocking pointer or key
must be released, followed by a positive-richness update, before audio begins.
Schedule the first game update after pointerup/keyup (or the subsequent frame);
a pointerdown/keydown-only update intentionally stays silent. An unrelated key
or pointer release does not complete a keyboard unlock. No automatic unlock is
attempted. Browser autoplay policy may still block playback. A rejected resume
mutes and suspends the existing context and resets the unlock/release state;
the next real pointerdown or Space/Enter keydown retries synchronously, without
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
