# QA evidence

Automated model QA uses `flutter test test/pond_soak_test.dart`. Tests enforce the agreed adaptive 180–360 second model contract, first completed gesture activation, and at most one latest pending gesture while busy. The superseded fixed 480-second and one-insect-after-sleep proposal is not the acceptance contract.

The deterministic soak covers seeds 0–99, all four weather states in both dawn/dusk cycles, idle sessions and repeated-input sessions, followed by 1,800 seconds of simulated foreground time after both frogs sleep. It checks finite coordinates, exactly two frogs, weather-specific insect-list bounds (18 clear/mist, 10 drizzle, 5 storm), monotone progression, duration bounds, synchronized sleep by 366 seconds, frozen frog positions and session progress after sleep, ignored sleeping input, and no further companion decisions. These are bounds on the entire retained bug list, including fading/dead entries, rather than only visible/live insects.

Additional reproducible cases cover 60 seconds before any input for 100 seeds, cancellation without activation, zero-delta updates, 1,000 busy gestures versus one pending gesture, and identical seeded trajectories under one-second versus 60 Hz update partitions for 12 seeds. Pausing is tested only as the model host omitting updates/zero delta; platform lifecycle delivery is not exercised.

## Results

On 2026-10-23, `flutter test test/pond_soak_test.dart` passed all five tests in approximately 50 seconds. All eight weather/cycle combinations occurred. Measured maxima for the entire retained bug list were 18 awake and 18 asleep; per-weather maxima were clear 18, mist 18, drizzle 10 and storm 5. Every sampled session slept by 366 seconds, and every 30-minute post-sleep simulation preserved sleep, frog positions, elapsed session time and endpoint lighting despite repeated input. No nonfinite coordinates or unbounded bug-list growth were observed. `flutter analyze test/pond_soak_test.dart` reported no issues. A direct local `dart analyze` could not resolve Flutter test packages because this forge runs Flutter in its shared toolchain image; the successful Flutter analysis is the relevant result.

Reviewed model SHA-256: `fda6319eeab89f571eae56e4b3b6bd65c573f314a877bea045367cb409b0042a` (unchanged through the final run). No material model defect was found within this coverage. The earlier claimed activation, queue and fixed-deadline defects came from invalid stale-proposal expectations; those claims are withdrawn.

Static review supports the bounded-list result: `lib/game/pond_model.dart:451` removes dead bugs before each tick's update, and lines 493–494 gate spawning against a weather-scaled target. Lines 163–178 prevent further companion actions after sleep and synchronize both asleep flags. The reviewed model has no gameplay score or loss path; learned-policy ranking scores are internal action preferences, not a player score.

## Limitations

No browser interaction or listening session has been done by this QA sidecar. No human usability, calming-effect, accessibility, audio quality, memory-profiler, or device performance claims are made. The 30-minute test verifies retained model list bounds, not Dart heap or browser resource usage. One-second observations execute the model's internal 60 Hz simulation, but do not inspect every internal substep. Seeds 0–99 are a reproducible finite sample, not all possible integer seeds. No score/loss state is exposed in the reviewed model; absence of rendered score/loss UI remains a renderer/browser check.

Renderer review is pending while `lib/game/pond_renderer.dart` is absent. Frog, tongue and insect coordinate agreement cannot yet be assessed.
