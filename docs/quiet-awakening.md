# A pond that wakes without announcing it

The opening is silent and nearly still until play begins. Player jumps, charge
and landing feedback stay immediate. Decorative changes use foreground play
time, not wall time spent looking at an untouched tab. A minimum four-minute
visit leaves at least one minute to play in the fully awakened pond; the scenery
and sound continue after the frogs sleep.

## Research and design judgement

- [Simons, Franconeri & Reimer (2000), *Change Blindness in the Absence of a
  Visual Disruption*](https://journals.sagepub.com/doi/10.1068/p3104) and
  [Frey et al. (2024), *Memory representations during slow change
  blindness*](https://pmc.ncbi.nlm.nih.gov/articles/PMC11401121/) show that slow
  changes can escape attention without a distracting interruption. This
  supports continuous scene evolution, not a guarantee that every player will
  fail to notice every change.
- [NN/g, *Animation for Attention and
  Comprehension*](https://www.nngroup.com/articles/animation-usability/) explains
  that peripheral movement captures attention and that fading without a
  position shift is less distracting. New layers therefore fade in at their
  final anchors; movement amplitude grows separately. Stones never sway merely
  because vegetation shares their image.
- [GDC 2024, Em Halberstadt, *How Sound Can Make You
  Feel*](https://www.gdcvault.com/play/1034773/Audio-Summit-How-Sound-Can) discusses
  density, frequency, loudness and balance as separate dimensions of game audio.
  The volume entrance and the orchestration are separate here: turning up an
  already complete chorus would not produce the intended gradual discovery.
  The Vault currently redirects to maintenance; its session abstract was
  accessible through search, rather than the full presentation.
- [W3C guidance on animation from
  interactions](https://www.w3.org/WAI/WCAG21/Understanding/animation-from-interactions)
  supports reduced-motion preferences. Decorative sway and distant flock
  travel freeze or disappear under the existing preference.

The specific times below are artistic choices to validate with listening and
play sessions. They are not thresholds established by those studies. There
are no scores, progress indicators, attention prompts or rewards for staying
longer: the reveal supports the quiet experience itself.

## Choreography

Every entrance uses quintic smootherstep, with zero velocity and acceleration
at both ends. Amplitudes and opacity are continuous; phases advance through a
slow ambient clock. Motion is never suddenly switched on at its final speed.

| Element | Begins | Fully present |
| --- | ---: | ---: |
| Master audio level | 0 s | 10 s |
| Water motion | 0 s | 110 s |
| Water sound bed | 0 s | 60 s |
| Breeze motion / sound | 10 / 20 s | 130 / 100 s |
| Foliage motion | 25 s | 155 s |
| Weather, clouds, rain and fog | 35 s | 170 s |
| Insect voices | 50 s | 160 s |
| Aquatic wildlife motion | 55 s | 175 s |
| Glows and secondary detail | 65 s | 180 s |
| Frog chorus | 70 s | 165 s |
| Distant flocks / distant voices | 100 / 110 s | 180 s |

Individual biome layers fade over overlapping long windows. All applicable
elements have arrived by three minutes. Biome and weather rules still apply:
a dry grotto does not acquire a storm or an outdoor flock just to fill a slot.
Explicit short test sessions compress the same proportions; production does
not expose the duration override.

## Visual corrections

- Replace the old procedural-face overlays on painted frogs with small,
  pose-specific eyelids mapped through the actual atlas packing transform.
  Eye patches are clipped to opaque iris regions, independently phased per
  frog, and do not run during flight or over the sleeping pose.
- Center shared-pad landings and clamp both foot endpoints inside the pad
  ellipse. Close silhouettes may overlap; feet hanging off a rim are worse.
- Remove noisy additive radial star ramps. Star cores use local luminance
  contrast masks without the old dilated patch of sky.
- Anchor painted shore and foreground layers, and mineral canopies. Animated
  leaves remain independent. Remove 15-degree rotation snapping, origin
  snapping, abrupt bright leaf flip frames and lighting cached in night
  buckets. Grade unlit cached geometry continuously at draw time.
- Add depth-aware weather behind the playable pond: broad irregular cloud
  shadows over mountains and far lake, fine rain, distant narrow water
  patterns, fog and occasional coherent V-wing flocks. Birds stay in the sky,
  muted and grouped, unlike bright individually wandering foreground insects.

## Controls

Space and Enter retain jump control. Escape and F exit page fullscreen through
a capture-phase page listener, even when Flutter owns keyboard focus. R
disposes the old soundscape and reloads after removing pinned preview seed and
duration parameters. Browser modifier shortcuts and text input are preserved.
