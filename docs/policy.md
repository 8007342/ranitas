# Tiny offline action prior

`lib/game/jump_policy.dart` contains an actually trained 8→12→3 network:
147 parameters, tanh hidden activation, softmax scores ordered **tap, low, high**.
The six-decimal numeric weight JSON payload is 1,422 bytes, below 5 KB.
It uses Dart core only, with compiled constants: no downloads, inference runtime,
asset loading, or pubspec asset registration. The manifest is training provenance
and test data, not a runtime dependency.

Run from the repository root:

```sh
node scripts/train-policy.mjs
flutter test test/jump_policy_test.dart
```

The script uses only Node built-ins and writes the Dart policy and manifest.
It uses deterministic seeded SGD (cross entropy, per-example updates, shuffled
training order), 18,000 training examples, 90 epochs, initial learning rate .025
with epoch decay `.025 / (1 + epoch/45)`. Independent train/test generator seeds
are 1724 and 90421; initialization/shuffle seed is 731. Evaluation happens after
rounding weights to the actual exported six decimals. No test-driven tuning or
model selection is performed.

## Exact encoder

Use normalized pond coordinates (x right, y down), velocity in pond units per
second, energy in [0,1], and signed model wind. Every encoded feature is clipped
to [-1,1], in this order:

| Index | Formula |
| --- | --- |
| 0 | `(frogX - .5) / .5` |
| 1 | `(frogY - .7) / .1` |
| 2 | `(bugX - frogX) / .7` |
| 3 | `(frogY - bugY) / .6` |
| 4 | `bugVx / .15` |
| 5 | `bugVy / .08` |
| 6 | `2 * energy - 1` |
| 7 | `wind` |

`encode` implements this contract; `suggest` accepts these eight named raw
arguments and calls `choose(encode(...))`. `scores` accepts exactly eight encoded
values, returning three finite probabilities summing to one. `choose` returns
the highest-scoring action, breaking exact ties in action order. Invalid lengths,
NaN/infinite inputs, or invalid inference results fall back to `[0,1,0]` / `low`.
Raw nonfinite values produce an invalid encoded vector so the same fallback
applies, including overflow during encoding. Finite encoded values are clipped.

## Synthetic teacher and measured results

Frog origin is sampled around either leaf: x = .27 or .73 ± .03, y = .69 or .72
± .015. The destination is the opposite nominal leaf. Bug x is uniform [.08,.92],
y [.2,.6], vx [-.15,.15], vy [-.08,.08]; energy [.2,1], wind [-1,1].
States are retained only if some arc passes within .13 pond units of the bug.
Independent PRNG streams generate train and held-out sets.

The teacher picks the arc with minimum Euclidean distance across ten samples
`p=i/12`, i=1…10. Durations are [.68,.95,1.3] seconds; heights [.13,.25,.39].
Frog x interpolates to the opposite leaf; frog y is
`frogY + (destinationY-frogY)*p - sin(pi*p)*(height+.018) - .025`.
Bug position is `(bugX+bugVx*p*duration, bugY+bugVy*p*duration)`, clipped to
x [.04,.96], y [.12,.65]. Exact teacher ties prefer tap, then low, then high.
Energy and wind are sampled context but do not affect this geometric teacher.

The completed run scored **3,776 / 4,000 = 94.4%** held-out teacher agreement.
The majority-class baseline is **60.6%**. Rows below are teacher labels; columns
are network predictions:

| | tap | low | high |
| --- | ---: | ---: | ---: |
| tap | 594 | 32 | 0 |
| low | 27 | 849 | 74 |
| high | 0 | 91 | 2333 |

The manifest records these metrics and five independent held-out feature/score
fixtures. Dart tests compare all five against the rounded JavaScript model at
1e-12 tolerance, check action order, encoder values, fallback, and bounded scores.

This is synthetic imitation, **not reinforcement learning**, live learning, or
real user engagement optimization. Accuracy is on reachable synthetic single-bug
states, not measured gameplay catch rate. The teacher omits multiple-bug utility,
low-action preference, wind penalty, actual perch offsets, landing randomness,
future meandering, cooldown, and busy state. Energy has no learned causal role;
wind penalties remain the analytical evaluator's responsibility. Softmax values
are uncalibrated imitation scores, not catch probabilities.

## Integration snippet (parent-owned change)

Keep `_evaluateJev` at 4 Hz, its existing guards, full three-arc lookahead,
catch logic and cooldown. For a selected live, visible target bug, compute once:

```dart
final priorAction = JumpPolicy.suggest(
  frogX: frog.x, frogY: frog.y,
  bugX: bug.x, bugY: bug.y,
  bugVx: bug.vx, bugVy: bug.vy,
  energy: frog.energy, wind: wind,
);
```

Inside the existing action loop, after computing analytical value:

```dart
value += action == priorAction ? .010 : 0.0;
```

A .008–.012 bonus makes this a small action preference; it can overturn analytical
value differences smaller than the bonus. Choose target selection explicitly in
the parent; skip the bonus if there is no eligible bug or raw input is nonfinite.
Do not launch directly from `suggest`. `pond_model.dart` is intentionally unchanged.
