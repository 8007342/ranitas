# Tiny offline action prior (depth-aware, schema 2)

`lib/game/jump_policy.dart` contains a trained 12→16→3 network: 259
parameters, a tanh hidden activation, and softmax scores ordered **tap, low,
high**. The six-decimal weight JSON payload is 2,459 bytes, below the 5 KB
budget. It uses Dart core only, with the weights compiled in as constants: no
downloads, inference runtime or asset loading. The manifest
(`assets/policy/manifest.json`) records training provenance and test data. It
is not a runtime dependency.

Schema 1 was an 8→12→3, 147-parameter prior trained on the old layout, where
both pads sat at one depth. Since the `visual-envelope` change, pads are seeded
at any depth and arc height scales with perspective. Schema 2 retrains the
prior for that geometry.

Run from the repository root (about 4 s):

```sh
node scripts/train-policy.mjs
flutter test test/jump_policy_test.dart
```

**Training setup:**

- **Method:** deterministic seeded SGD with cross entropy, per-example updates
  and a shuffled training order.
- **Data:** 24,000 training examples; 4,000 held-out examples.
- **Schedule:** 90 epochs; learning rate `.02 / (1 + epoch/45)`.
- **Seeds:** train generator 1724, held-out generator 90421, initialisation and
  shuffle 731.
- **Evaluation:** on the weights after rounding to the six exported decimals.
  No test-driven tuning or model selection is performed.

## Exact encoder

Inputs are normalised pond coordinates (x right, y down), velocity in pond
units per second, energy in [0,1], signed model wind, the target perch, and the
perspective scale (`.56 + .48·depth`) at the frog and at the target. Every
feature is clipped to [-1,1], in this order:

| Index | Formula |
| --- | --- |
| 0 | `(frogX - .5) / .5` |
| 1 | `(frogY - .75) / .2` |
| 2 | `(bugX - frogX) / .7` |
| 3 | `(frogY - bugY) / .6` |
| 4 | `bugVx / .15` |
| 5 | `bugVy / .08` |
| 6 | `2 * energy - 1` |
| 7 | `wind` |
| 8 | `(targetX - frogX) / .7` |
| 9 | `(targetY - frogY) / .3` |
| 10 | `(scaleFrom - .8) / .25` |
| 11 | `(scaleTo - .8) / .25` |

**API contract:**

- `encode` implements the table above.
- `suggest` takes the twelve named raw arguments and calls
  `choose(encode(...))`.
- `scores` accepts exactly `JumpPolicy.inputs` (12) encoded values and returns
  three finite probabilities that sum to one.
- `choose` returns the highest-scoring action, breaking exact ties in action
  order.
- **Fallback:** invalid lengths, NaN or infinite inputs, and invalid inference
  results all fall back to `[0,1,0]` / `low`.

## Synthetic teacher and measured results

**Sampled states:**

- **Basin:** top uniform in [.50,.60] and bottom in [.88,.96] (normalised
  y).
- **Pads:** the frog's pad lies at any depth inside the basin, at x
  [.20,.45] or [.55,.80]. The target pad is on the opposite side, at its own
  random depth.
- **Bug:** x [.06,.94], y [.15,.65], vx [-.15,.15], vy [-.08,.08].
- **Context:** energy [.2,1], wind [-1,1].
- **Filter:** states are kept only if some arc passes within .13 pond units of
  the bug.

**Teacher:** it picks the arc with the minimum Euclidean distance across ten
samples `p = i/12`, i = 1…10.

- **Arc table:** durations [.68,.95,1.3] s; heights [.13,.25,.39].
- **Frog position along the arc:** x interpolates to the target. y is
  `groundY - sin(pi*p)*(height+.018)*scale(p) - .025`, where `groundY`
  interpolates to the target and `scale(p)` interpolates linearly from
  `scaleFrom` to `scaleTo` (perspective is linear in depth). This is the same
  arc the model's analytical JEV evaluates.
- **Bug position:** `(bugX+bugVx*p*duration, bugY+bugVy*p*duration)`, clipped
  to x [.04,.96] and y [.12,.65].

**Result:** the run scored **3,737 / 4,000 = 93.4%** held-out teacher agreement,
against a majority-class baseline of **64.5%**. Rows below are teacher labels
and columns are network predictions:

| | tap | low | high |
| --- | ---: | ---: | ---: |
| tap | 666 | 47 | 3 |
| low | 41 | 591 | 72 |
| high | 1 | 99 | 2480 |

The manifest records these metrics and five held-out feature/score fixtures.
Dart tests compare all five against the rounded JavaScript model at 1e-12
tolerance.

This is synthetic imitation, **not reinforcement learning**, live learning, or
optimisation of real engagement. Accuracy is measured on reachable synthetic
single-bug states, not on gameplay catch rate. Softmax values are uncalibrated
imitation scores, not catch probabilities.

## Integration in `PondModel._evaluateJev`

JEV keeps its 4 Hz schedule, its guards, the full three-arc analytical
lookahead (which uses the same perspective-scaled arc) and its cooldown.

- **Prior bonus:** the prior is queried for the nearest live insect, with the
  live target perch and the perspective at both ends. Its suggestion adds
  `.008` to that action's analytical value, which only breaks near-ties.
- **Patience:** if no arc brings any insect within the catch neighbourhood
  (summed reach below `.01`), JEV waits rather than jumping, re-evaluating
  every 0.25 s for up to 4 s, and then jumps anyway.

  In a 60-seed simulation of 240 s sessions with an idle player, patience
  raised the companion's catches per jump from 0.244 to 0.416. Total catches
  rose from 1,220 to 1,284 while jumps fell from 5,005 to 3,089. These are
  simulation measurements, not a playtest.
