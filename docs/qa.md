# QA evidence

Automated model QA uses `flutter test test/pond_soak_test.dart`. Tests enforce the agreed adaptive 180–360 second model contract, first completed gesture activation, and at most one latest pending gesture while busy.

The deterministic soak covers seeds 0–99, all four weather states in both dawn/dusk cycles, idle sessions and repeated-input sessions, followed by 1,800 seconds of simulated foreground time after both frogs sleep. It checks finite coordinates, exactly two frogs, weather-specific insect-list bounds (18 clear/mist, 10 drizzle, 5 storm), monotone progression, duration bounds, synchronized sleep by 366 seconds, frozen frog positions and session progress after sleep, ignored sleeping input, and no further companion decisions. These are bounds on the entire retained bug list, including fading/dead entries, rather than only visible/live insects.

Additional reproducible cases cover 60 seconds before any input for 100 seeds, cancellation without activation, zero-delta updates, 1,000 busy gestures versus one pending gesture, and identical seeded trajectories under one-second versus 60 Hz update partitions for 12 seeds. Pausing is tested only as the model host omitting updates/zero delta; platform lifecycle delivery is not exercised.

## Results

The final full `flutter test` run passes all 22 tests; `flutter analyze` reports no issues.

On 2026-10-23, `flutter test test/pond_soak_test.dart` passed all five tests in approximately 50 seconds. All eight weather/cycle combinations occurred. Measured maxima for the entire retained bug list were 18 awake and 18 asleep; per-weather maxima were clear 18, mist 18, drizzle 10 and storm 5. Every sampled session slept by 366 seconds, and every 30-minute post-sleep simulation preserved sleep, frog positions, elapsed session time and endpoint lighting despite repeated input. No nonfinite coordinates or unbounded bug-list growth were observed. `flutter analyze test/pond_soak_test.dart` reported no issues. A direct local `dart analyze` could not resolve Flutter test packages because this forge runs Flutter in its shared toolchain image; the successful Flutter analysis is the relevant result.

Reviewed model SHA-256: `0bf7725967d2a20e1ffda62edf0163abd9a3f56836d70e8fc2e84598c71f9431` (unchanged through the final run). No material model defect was found within this coverage.

Static review supports the bounded-list result: `lib/game/pond_model.dart:451` removes dead bugs before each tick's update, and lines 493–494 gate spawning against a weather-scaled target. Lines 163–178 prevent further companion actions after sleep and synchronize both asleep flags. The reviewed model has no gameplay score or loss path; learned-policy ranking scores are internal action preferences, not a player score.

## Limitations

The model QA sidecar did not perform browser checks. Integration checks below cover the browser separately. No human usability, calming-effect, accessibility, audio quality, memory-profiler, or device performance claims are made. The 30-minute test verifies retained model list bounds, not Dart heap or browser resource usage. One-second observations execute the model's internal 60 Hz simulation, but do not inspect every internal substep. Seeds 0–99 are a reproducible finite sample, not all possible integer seeds. No score/loss state is exposed in the reviewed model; absence of rendered score/loss UI remains a renderer/browser check.

Renderer smoke checks now render three seeded worlds before input, during activity, and after sleep, writing inspection images to `build/scene-checks`. These frames were visually inspected. The renderer uses the model’s normalized coordinates for frogs, tongues, and insects.

## Browser integration

Chromium phone emulation (428 × 926, DPR 1 for inspection) and desktop
(1280 × 720) show a complete centered portrait scene without gameplay HUD.
Production WebP backgrounds and the alpha foreground layer return HTTP 200.
A fresh mobile page creates zero AudioContexts before interaction. Trusted
touch-down/release creates one running context. A real release-stack resume
fix was required for mobile activation. Simulated visibility events suspend
and resume an already-started context without creating another. No runtime
exceptions appeared in the inspected console. These are automated browser
checks, not tests on physical phones or audible listening.

The generated art set totals about 6.8 MiB. The production bundle includes
multiple local Flutter engine variants; only the browser-selected engine is
fetched. Every static file passes the 25 MiB asset gate, and Wrangler deploy
dry-run succeeds. Native Android/iOS packaging and native audio are unverified;
the native audio wrapper is currently a no-op.
