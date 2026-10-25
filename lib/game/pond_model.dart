import 'dart:math';

import 'insect_species.dart';
import 'jump_policy.dart';
import 'rain_envelope.dart';

/// A deterministic, renderer-independent pond. Coordinates use a landscape
/// viewport with (0, 0) at the upper left. Advance with seconds, not milliseconds.
/// There are no scores, loss states, or automatic replay. Create another model
/// for a new pond. A seed reproduces a pond with the same input/update timeline.
class PondModel {
  PondModel({int? seed, double? durationOverride}) : random = Random(seed) {
    sceneSeed = seed ?? random.nextInt(1 << 30);
    if (durationOverride != null &&
        (!durationOverride.isFinite || durationOverride <= 0)) {
      throw ArgumentError.value(
        durationOverride,
        'durationOverride',
        'Must be finite and positive',
      );
    }
    _durationOverride = durationOverride;
    duration = durationOverride ?? 240;
    biome = biomes[random.nextInt(biomes.length)];
    final weatherRoll = random.nextDouble();
    weather = weatherRoll < .5
        ? 'clear'
        : weatherRoll < .8
        ? 'mist'
        : weatherRoll < .95
        ? 'drizzle'
        : 'storm';
    cycle = random.nextDouble() < .75 ? 'dusk' : 'dawn';
    period = cycle == 'dawn' ? 'night' : 'day';
    // Own seeded stream: sampling it never shifts the main draw order above.
    _rainEnvelope = RainEnvelope(seed: sceneSeed, weather: weather);
    rainIntensity = _rainEnvelope.at(0);

    // Biome-specific open-water basin so hero pads, ambient floating leaves,
    // Koi fish, and rain impacts always rest on water and never on shore rocks.
    basin = WaterBasin.forBiome(biome);
    frogs = [
      FrogState(0, basin.pad0X, basin.pad0Y),
      FrogState(1, basin.pad1X, basin.pad1Y),
    ];
    pads = [
      PadState(
        index: 0,
        x: basin.pad0X,
        y: basin.pad0Y,
        radiusX: 35,
        radiusY: 11,
      ),
      PadState(
        index: 1,
        x: basin.pad1X,
        y: basin.pad1Y,
        radiusX: 37,
        radiusY: 12,
      ),
    ];

    _fxRandom = Random(sceneSeed ^ 0x5f3759df);
    ambientPads = _generateAmbientPads();
    koi = List.generate(4, (i) {
      final y =
          basin.topY +
          18.0 +
          ((i + .4) / 4.2) * (basin.bottomY - basin.topY - 32.0);
      final left = basin.leftX(y) + 28.0;
      final right = basin.rightX(y) - 28.0;
      final startX =
          left + ((i + .5) / 4.0) * max(20.0, right - left) +
          (_fxRandom.nextDouble() - .5) * 18.0;
      return KoiState(
        index: i,
        variant: i,
        x: startX.clamp(left, right),
        y: y,
        heading: i.isEven ? 0.12 : pi - 0.12,
        swimPhase: i * 1.57,
        depth: 0.25 + (i % 3) * 0.18,
      );
    });
    tadpoles = List.generate(6, (i) {
      final y =
          basin.topY +
          14.0 +
          ((i + .3) / 6.2) * (basin.bottomY - basin.topY - 24.0);
      final left = basin.leftX(y) + 20.0;
      final right = basin.rightX(y) - 20.0;
      return TadpoleState(
        index: i,
        x: (left + _fxRandom.nextDouble() * max(20.0, right - left)).clamp(
          left,
          right,
        ),
        y: y,
        heading: _fxRandom.nextDouble() * pi * 2,
        swimPhase: i * 1.1,
      );
    });
    if (weather == 'drizzle' || weather == 'storm') {
      _updateRain(0.35);
    }
  }

  static const List<String> biomes = [
    'willow',
    'blossom',
    'cypress',
    'maple',
    'sanctuary',
    'grotto',
    'alpine',
    'lotus',
    'firefly',
    'autumn_mist',
    'jade_sanctuary',
    'crystal_grotto',
  ];

  final Random random;

  /// Stable renderer composition seed, assigned once for this pond.
  late final int sceneSeed;
  double time = 0;
  double elapsed = 0;
  double progress = 0;
  double richness = 0;
  double wind = 0;
  double windTell = 0;
  double engagement = 0;
  bool started = false;
  bool sleeping = false;
  late String biome;
  late final WaterBasin basin;

  /// Scenic landscape WebP filename matching [biome].
  String get backdropAsset => switch (biome) {
    'cypress' => 'pond-mist.webp',
    'blossom' => 'pond-blossom.webp',
    'maple' => 'pond-maple.webp',
    'sanctuary' => 'pond-sanctuary.webp',
    'grotto' => 'pond-grotto.webp',
    'alpine' => 'pond-alpine.webp',
    'lotus' => 'pond-lotus.webp',
    'firefly' => 'pond-firefly.webp',
    'autumn_mist' => 'pond-autumn-mist.webp',
    'jade_sanctuary' => 'pond-jade-sanctuary.webp',
    'crystal_grotto' => 'pond-crystal-grotto.webp',
    _ => 'pond-dusk.webp',
  };

  /// Transparent foreground parallax WebP filename matching [biome].
  String get foregroundAsset => switch (biome) {
    'blossom' ||
    'maple' ||
    'sanctuary' ||
    'lotus' ||
    'autumn_mist' ||
    'jade_sanctuary' => 'foreground-blossom.webp',
    'grotto' || 'crystal_grotto' => 'foreground-grotto.webp',
    _ => 'foreground-marsh.webp',
  };

  /// Persistent scene weather; gusts are expressed by wind and windTell.
  late String weather;

  late final RainEnvelope _rainEnvelope;

  /// Current rain intensity in `[0, 1]`: a seeded envelope inside drizzle and
  /// storm sessions (design D1), always zero in clear and mist. Updated every
  /// tick; it keeps evolving after sleep.
  double rainIntensity = 0;

  bool get raining => weather == 'drizzle' || weather == 'storm';

  /// Cloud darkening for the scene grade, from the rain intensity.
  double get cloudDarkening => RainEnvelope.cloudFor(rainIntensity);

  /// Insect spawn-budget shelter: 1 when dry, lower as rain thickens.
  double get insectShelter =>
      raining ? RainEnvelope.shelterFor(rainIntensity) : 1.0;

  /// Weather label for the ambience: a storm in a lull sounds like drizzle.
  String get audioWeather => RainEnvelope.audioLabel(weather, rainIntensity);

  /// Seeded once: dusk (75%) or dawn (25%). Does not loop after sleep.
  late final String cycle;
  late String period;

  /// A rare smooth underwater disturbance; the pads visibly wobble first.
  double get leafNudge => started && !sleeping && !_settling && progress > .45
      ? pow(max(0.0, sin(time * .071 + sceneSeed % 37)), 40).toDouble()
      : 0.0;

  double get daylight => cycle == 'dawn' ? progress : 1 - progress;
  late final List<FrogState> frogs;
  late final List<PadState> pads;
  late final List<PadState> ambientPads;
  late final List<KoiState> koi;
  late final List<TadpoleState> tadpoles;
  final List<RippleState> ripples = [];
  final List<SplashDroplet> splashDroplets = [];
  final List<RaindropState> raindrops = [];
  late final Random _fxRandom;
  final List<BugState> bugs = [];

  List<PadState> _generateAmbientPads() {
    final result = <PadState>[];
    final hero0X = basin.pad0X * 641;
    final hero0Y = basin.pad0Y * 359;
    final hero1X = basin.pad1X * 641;
    final hero1Y = basin.pad1Y * 359;

    for (var i = 0; i < 7; i++) {
      var placed = false;
      for (var attempt = 0; attempt < 24 && !placed; attempt++) {
        final yn = .12 + _fxRandom.nextDouble() * .80;
        final py = basin.topY + yn * (basin.bottomY - basin.topY);
        final left = basin.leftX(py) + 22;
        final right = basin.rightX(py) - 22;
        if (right <= left) continue;
        final px = left + _fxRandom.nextDouble() * (right - left);

        // Keep ambient leaves clear of the two primary frog lily pads
        final d0 = sqrt(pow(px - hero0X, 2) + pow((py - hero0Y) * 1.8, 2));
        final d1 = sqrt(pow(px - hero1X, 2) + pow((py - hero1Y) * 1.8, 2));
        if (d0 < 52 || d1 < 52) continue;

        final tooClose = result.any((other) {
          final ox = other.x * 641;
          final oy = other.y * 359;
          return sqrt(pow(px - ox, 2) + pow((py - oy) * 1.8, 2)) < 28;
        });
        if (tooClose) continue;

        final perspective = .56 + .48 * yn;
        final rx = (9.5 + _fxRandom.nextDouble() * 11.5) * perspective;
        final ry = rx * (.28 + .07 * yn);
        result.add(
          PadState(
            index: 2 + i,
            x: px / 641,
            y: py / 359,
            radiusX: rx,
            radiusY: ry,
            isAmbient: true,
            hasLotus: i % 3 == 0,
            phase: _fxRandom.nextDouble() * pi * 2,
          ),
        );
        placed = true;
      }
    }
    result.sort((a, b) => a.y.compareTo(b.y));
    return result;
  }

  /// Normal sessions adapt within 180–360 seconds; overrides are for previews
  /// and tests. Progress never runs backwards when the duration adapts.
  late double duration;
  bool get pressing => _pressStarted != null;
  double get holdDuration =>
      _pressStarted == null ? 0 : time + _remainder - _pressStarted!;
  bool get settling => _settling;
  int aiEvaluations = 0;
  double? _durationOverride;
  double? _pressStarted;
  bool _autoLaunched = false;
  double _remainder = 0;
  double _aiClock = 0;
  double _spawnClock = 0;
  double _gustClock = 12;
  double _gustAge = -1;
  double _gustDirection = 1;
  double _tapAgitation = 0;
  double _lastRelease = -100;
  bool _settling = false;
  static const double _step = 1 / 60;

  /// Valve GameFlow-tuned single-impulse thresholds:
  /// - Release < 0.11s -> immediate 'tap' hop
  /// - Release 0.11s .. < 0.26s -> immediate 'low' (short) jump
  /// - Hold >= 0.26s -> automatic liftoff into 'high' (long) jump without
  ///   waiting for release, flying along a single unbroken parabola (zero double-jump).
  static const double _tapThreshold = .11;
  static const double _highAutoLaunchThreshold = .26;

  /// Repeated down events or presses while a frog is in flight are ignored.
  void press() {
    if (sleeping || _settling || pressing || _busy) return;
    _pressStarted = time + _remainder;
    _autoLaunched = false;
    // Tactile pad press-down feedback while coiling
    pads[frogs[0].leafIndex].dipVelocity += 4.5;
  }

  /// Releases before 0.11s launch 'tap'; before 0.26s launch 'low';
  /// holds >= 0.26s already auto-launched 'high' on the pad.
  void release() {
    if (!pressing) return;
    final held = holdDuration;
    final alreadyLaunched = _autoLaunched;
    _pressStarted = null;
    _autoLaunched = false;
    if (sleeping || _settling) return;
    if (time - _lastRelease < .3) _tapAgitation = min(1, _tapAgitation + .2);
    _lastRelease = time;
    if (alreadyLaunched || _busy) return;
    started = true;
    engagement = min(1, engagement + .075);
    final action = held < _tapThreshold - 1e-9 ? 'tap' : 'low';
    _launch(frogs[0], action);
  }

  /// Pointer cancellation before auto-launch never starts play or launches a frog.
  void cancelPress() {
    _pressStarted = null;
    _autoLaunched = false;
  }

  /// Fixed substeps keep flight, bug motion and AI independent of frame rate.
  /// Invalid/negative deltas are rejected; zero is a no-op. No time is dropped.
  void update(double dt) {
    if (!dt.isFinite || dt < 0) {
      throw ArgumentError.value(dt, 'dt', 'Must be finite and nonnegative');
    }
    _remainder += dt;
    while (_remainder + 1e-12 >= _step) {
      _remainder = max(0, _remainder - _step);
      _tick(_step);
    }
  }

  void _tick(double dt) {
    time += dt;
    rainIntensity = _rainEnvelope.at(time);
    if (started && !sleeping && !_settling) {
      elapsed += dt;
      engagement *= exp(-dt / 18);
      if (_durationOverride == null) {
        duration += (180 + 180 * engagement - duration) * (1 - exp(-dt / 12));
        duration = duration.clamp(180.0, 360.0);
      }
      final fraction = (elapsed / duration).clamp(0.0, 1.0);
      progress = max(progress, fraction * fraction * (3 - 2 * fraction));
      if (elapsed + 1e-9 >= duration) {
        progress = 1;
        _settling = true;
        cancelPress();
      }
    }
    richness = progress;
    period = cycle == 'dawn'
        ? (progress < .2
              ? 'night'
              : progress < .85
              ? 'dawn'
              : 'day')
        : (progress < .55
              ? 'day'
              : progress < .85
              ? 'dusk'
              : 'night');
    _tapAgitation *= exp(-dt / 3);
    _updateAutoLaunch();
    _updateWind(dt);
    _updateBugs(dt);
    for (final frog in frogs) {
      _updateFrog(frog, dt);
    }
    _updatePads(dt);
    _updateRipplesAndSplashes(dt);
    _updateRain(dt);
    _updateWildlife(dt);
    if (!started || sleeping) return;
    if (_settling) {
      if (!_busy) {
        for (final frog in frogs) {
          if (frog.leafIndex != frog.index) {
            _launch(frog, 'low', returning: true);
            return;
          }
        }
        sleeping = true;
        for (final frog in frogs) {
          frog.asleep = true;
          frog.tongue = 0;
          frog.chompTimer = 0;
          frog.landingTimer = 0;
          frog.swallowTimer = 0;
        }
      }
      return;
    }
    _aiClock += dt;
    if (_aiClock + 1e-9 >= .25) {
      _aiClock -= .25;
      _evaluateJev();
    }
  }

  bool get _busy => frogs.any((f) => f.airborne || f.swimming);

  void _updateAutoLaunch() {
    if (!pressing || _autoLaunched || sleeping || _settling) return;
    if (_busy) {
      cancelPress();
      return;
    }
    if (holdDuration >= _highAutoLaunchThreshold - 1e-9) {
      started = true;
      _autoLaunched = true;
      engagement = min(1, engagement + .075);
      _launch(frogs[0], 'high');
    }
  }

  static double _flightDuration(String action) => action == 'tap'
      ? .68
      : action == 'low'
      ? .95
      : 1.3;
  static double _height(String action) => action == 'tap'
      ? .13
      : action == 'low'
      ? .25
      : .39;
  double _leafX(int leaf) => pads[leaf].x;
  double _leafY(int leaf) => pads[leaf].y;

  // Each frog has a small perch offset when visiting the other's leaf. Flights
  // are serialized; the vertical lane additionally separates passing silhouettes.
  double _perchX(FrogState frog, int leaf) =>
      _leafX(leaf) +
      (leaf == frog.index
          ? 0
          : frog.index == 0
          ? -.045
          : .045);

  void _launch(FrogState frog, String action, {bool returning = false}) {
    final sourcePad = pads[frog.leafIndex];
    frog.action = action;
    frog._fromX = frog.x;
    frog._fromY = frog.y;
    frog._targetLeaf = returning ? frog.index : 1 - frog.leafIndex;
    frog._toX = _perchX(frog, frog._targetLeaf);
    frog._toY = _leafY(frog._targetLeaf);
    // Choose the landing point before flight, including homeward flights.
    // Nearly vertical variation keeps both perches separated on the same pad.
    final radius = .005 + random.nextDouble() * .01;
    final angle = pi / 2 + (random.nextDouble() - .5) * .4;
    final sign = random.nextBool() ? 1 : -1;
    final ySign = frogs[1 - frog.index].leafIndex == frog._targetLeaf
        ? (frog.index == 0 ? -1 : 1)
        : sign;
    frog._toX += cos(angle) * radius * sign;
    frog._toY += sin(angle) * radius * ySign;
    frog._duration = _flightDuration(action);
    frog._returning = returning;
    frog.jumpPhase = 0;
    frog.airborne = true;
    frog.landingTimer = 0;
    frog.swallowTimer = 0;
    frog.caughtInFlight = 0;
    frog.facing = frog._toX >= frog._fromX ? 1.0 : -1.0;
    frog.energy = max(.2, frog.energy - .08);

    // Takeoff recoil on source lily pad + takeoff ripple
    final launchImpulse = action == 'high'
        ? 1.25
        : action == 'low'
        ? 1.0
        : .75;
    sourcePad.dipVelocity += 9.5 * launchImpulse;
    sourcePad.tiltVelocity -= frog.facing * 3.8 * launchImpulse;
    sourcePad.driftVelocity -= frog.facing * 2.2 * launchImpulse;
    sourcePad.dewdropVelocity += 14.0 * launchImpulse;
    sourcePad.landingZone = 'takeoff';
    _emitRipple(
      x: sourcePad.x * 641 + sourcePad.driftX,
      y: sourcePad.y * 359 + 2,
      initialRadius: sourcePad.radiusX * .55,
      maxRadius: sourcePad.radiusX * 1.65,
      duration: 1.05,
      intensity: .52 * launchImpulse,
      biasX: -frog.facing * 4.0,
    );
  }

  void _updateFrog(FrogState frog, double dt) {
    frog.tongue = max(0, frog.tongue - dt * 5);
    frog.chompTimer = max(0, frog.chompTimer - dt);
    frog.landingTimer = max(0, frog.landingTimer - dt);
    frog.swallowTimer = max(0, frog.swallowTimer - dt);
    frog.cooldown = max(0, frog.cooldown - dt);
    frog.energy = min(1, frog.energy + dt * .035);
    frog.bellyFlop = max(0, frog.bellyFlop - dt * 2);
    if (frog.swimming) {
      frog._swimAge += dt;
      final p = (frog._swimAge / 1.6).clamp(0.0, 1.0);
      final s = p * p * (3 - 2 * p);
      frog.x = frog._splashX + (frog._toX - frog._splashX) * s;
      frog.y = frog._toY + .065 * (1 - s) + sin(p * pi * 4) * .006 * (1 - p);
      frog.facing = frog._toX >= frog._splashX ? 1.0 : -1.0;
      if (p >= 1) {
        frog.swimming = false;
        _land(frog);
      }
      return;
    }
    if (!frog.airborne) return;
    // Pure, single-impulse ballistic parabola from liftoff (p=0) to landing (p=1)
    frog.jumpPhase = min(1, frog.jumpPhase + dt / frog._duration);
    final p = frog.jumpPhase;
    frog.x = frog._fromX + (frog._toX - frog._fromX) * p;
    frog.y =
        frog._fromY +
        (frog._toY - frog._fromY) * p -
        sin(pi * p) * (_height(frog.action) + frog.index * .018);
    if (!_settling && p > .12 && p < .88) {
      for (final bug in bugs) {
        if (!bug.alive || bug.opacity < .25) continue;
        if (_distance(frog.x, frog.y - .025, bug.x, bug.y) < .065) {
          bug.alive = false;
          frog.tongue = 1;
          frog.chompTimer = .36;
          frog.tongueX = bug.x;
          frog.tongueY = bug.y;
          frog.caughtInFlight++;
          frog.lastCaughtSpecies = bug.species;
          frog.energy = min(1, frog.energy + .12);
          break;
        }
      }
    }
    if (p >= 1) {
      frog.airborne = false;
      final chance = .045 + .14 * _tapAgitation;
      if (!_settling &&
          !frog._returning &&
          (wind.abs() > .35 || _tapAgitation > .65 || leafNudge > .8) &&
          random.nextDouble() < chance) {
        frog.swimming = true;
        frog.bellyFlop = 1;
        frog._swimAge = 0;
        var splashX = (frog._toX + wind * .04).clamp(
          basin.leftX(frog._toY * 359) / 641 + .03,
          basin.rightX(frog._toY * 359) / 641 - .03,
        );
        final other = frogs[1 - frog.index];
        if ((splashX - other.x).abs() < .045) {
          splashX = other.x + (frog._toX <= other.x ? -.048 : .048);
        }
        frog._splashX = splashX.clamp(.12, .88);
        frog.x = frog._splashX;
        frog.y = frog._toY + .065;
        frog.facing = frog._toX >= frog._splashX ? 1.0 : -1.0;
        final sx = frog.x * 641;
        final sy = frog.y * 359;
        _emitRipple(
          x: sx,
          y: sy,
          initialRadius: 8,
          maxRadius: 68,
          duration: 1.45,
          intensity: 1.0,
        );
        _emitRipple(
          x: sx,
          y: sy,
          initialRadius: 4,
          maxRadius: 44,
          duration: 1.05,
          intensity: .8,
        );
        _emitSplashDroplets(sx, sy, count: 10, side: 0, power: 1.25);
        _startleWildlife(sx, sy, 1.35);
      } else {
        _land(frog);
      }
    }
  }

  void _land(FrogState frog) {
    frog.leafIndex = frog._targetLeaf;
    frog.x = frog._toX;
    frog.y = frog._toY;
    frog.jumpPhase = 0;
    frog.facing = frog.leafIndex == 0 ? 1.0 : -1.0;
    frog.landingTimer = .28;
    if (frog.caughtInFlight > 0 && !_settling && !sleeping) {
      frog.swallowTimer = .88;
      frog.totalCatches += frog.caughtInFlight;
    }
    frog.caughtInFlight = 0;
    frog.cooldown = 1.1 + random.nextDouble() * 1.3;

    // Pad landing physics: center cup-dip, mid-pad tilt, or edge fold + splash
    final pad = pads[frog.leafIndex];
    final impactWeight = frog.action == 'high'
        ? 1.35
        : frog.action == 'low'
        ? 1.0
        : .78;
    final offsetX = ((frog.x - pad.x) / (pad.radiusX / 641)).clamp(-1.0, 1.0);
    final offsetY = ((frog.y - pad.y) / (pad.radiusY / 359)).clamp(-1.0, 1.0);
    final offsetMag = sqrt(offsetX * offsetX + offsetY * offsetY * .25);
    frog.lastImpactOffset = offsetX;
    final signX = offsetX >= 0 ? 1.0 : -1.0;
    final padPxX = pad.x * 641 + pad.driftX;
    final padPxY = pad.y * 359 + 2;

    if (offsetMag >= .58) {
      // Zone C: Edge / Rim Landing -> Leaf Edge Fold + Directional Splash + Ripples
      pad.landingZone = 'edge';
      pad.dipVelocity += 11.5 * impactWeight;
      pad.tiltVelocity += signX * 7.8 * impactWeight;
      pad.driftVelocity += signX * 5.2 * impactWeight;
      pad.edgeFold = min(1.0, pad.edgeFold + .88 * impactWeight);
      pad.edgeFoldSide = signX;
      pad.waterWashAlpha = (pad.edgeFold * .72).clamp(0.0, 1.0);
      pad.dewdropVelocity += 30.0 * impactWeight;
      final rimX = padPxX + signX * (pad.radiusX * .78);
      _emitSplashDroplets(
        rimX,
        padPxY,
        count: 7,
        side: signX,
        power: impactWeight,
      );
      _emitRipple(
        x: rimX,
        y: padPxY,
        initialRadius: 10,
        maxRadius: pad.radiusX * 2.1,
        duration: 1.35,
        intensity: .92 * impactWeight,
        biasX: signX * 9.0,
      );
      _emitRipple(
        x: padPxX,
        y: padPxY,
        initialRadius: pad.radiusX * .7,
        maxRadius: pad.radiusX * 1.75,
        duration: 1.1,
        intensity: .65 * impactWeight,
        biasX: signX * 5.0,
      );
    } else if (offsetMag >= .30) {
      // Zone B: Mid-Pad Landing -> Directional Tilt + Plum Underside Reveal
      pad.landingZone = 'mid';
      pad.dipVelocity += 13.5 * impactWeight;
      pad.tiltVelocity += signX * 5.6 * impactWeight;
      pad.driftVelocity += signX * 3.4 * impactWeight;
      pad.edgeFold = min(1.0, pad.edgeFold + .35 * impactWeight);
      pad.edgeFoldSide = signX;
      pad.waterWashAlpha = (pad.edgeFold * .45).clamp(0.0, 1.0);
      pad.dewdropVelocity += 24.0 * impactWeight;
      _emitRipple(
        x: padPxX + signX * 5,
        y: padPxY,
        initialRadius: pad.radiusX * .65,
        maxRadius: pad.radiusX * 1.85,
        duration: 1.2,
        intensity: .78 * impactWeight,
        biasX: signX * 4.5,
      );
    } else {
      // Zone A: Center Landing -> Symmetric Hydrostatic Cup-Dip + 360° Ripple
      pad.landingZone = 'center';
      pad.dipVelocity += 16.0 * impactWeight;
      pad.tiltVelocity += offsetX * 3.0 * impactWeight;
      pad.dewdropVelocity += 26.0 * impactWeight;
      _emitRipple(
        x: padPxX,
        y: padPxY,
        initialRadius: pad.radiusX * .68,
        maxRadius: pad.radiusX * 1.8,
        duration: 1.15,
        intensity: .72 * impactWeight,
      );
    }
    _startleWildlife(padPxX, padPxY, impactWeight);
  }

  /// JEV combines geometric lookahead with a synthetic-teacher-trained prior.
  void _evaluateJev() {
    aiEvaluations++;
    final frog = frogs[1];
    if (_busy || frog.cooldown > 0 || pressing) return;
    BugState? nearest;
    var nearestDistance = double.infinity;
    for (final bug in bugs) {
      if (!bug.alive) continue;
      final distance = _distance(frog.x, frog.y, bug.x, bug.y);
      if (distance < nearestDistance) {
        nearest = bug;
        nearestDistance = distance;
      }
    }
    final prior = nearest == null
        ? null
        : JumpPolicy.suggest(
            frogX: frog.x,
            frogY: frog.y,
            bugX: nearest.x,
            bugY: nearest.y,
            bugVx: nearest.vx,
            bugVy: nearest.vy,
            energy: frog.energy,
            wind: wind,
          );
    var best = double.negativeInfinity;
    var chosen = 'low';
    final target = 1 - frog.leafIndex;
    for (final action in ['tap', 'low', 'high']) {
      final flight = _flightDuration(action);
      var value = action == 'low' ? .025 : 0.0;
      for (final bug in bugs) {
        if (!bug.alive || bug.opacity < .25) continue;
        var closest = 1.0;
        for (var i = 1; i <= 10; i++) {
          final p = i / 12;
          final x = frog.x + (_perchX(frog, target) - frog.x) * p;
          final y =
              frog.y +
              (_leafY(target) - frog.y) * p -
              sin(pi * p) * (_height(action) + .018) -
              .025;
          closest = min(
            closest,
            _distance(
              x,
              y,
              (bug.x + bug.vx * p * flight).clamp(.04, .96),
              (bug.y + bug.vy * p * flight).clamp(.12, .65),
            ),
          );
        }
        value += max(0, .13 - closest);
      }
      value -= wind.abs() * _height(action) * .08;
      if (action == prior) value += .008;
      if (value > best) {
        best = value;
        chosen = action;
      }
    }
    _launch(frog, chosen);
  }

  static double _distance(double x, double y, double bx, double by) =>
      sqrt((x - bx) * (x - bx) + (y - by) * (y - by));

  void _updateWind(double dt) {
    if (!started || _settling || sleeping) {
      wind *= exp(-dt * 3);
      windTell = 0;
      return;
    }
    if (_gustAge < 0) {
      _gustClock -= dt;
      wind = sin(time * .31) * .06;
      windTell = 0;
      if (_gustClock <= 0) {
        _gustAge = 0;
        _gustDirection = random.nextBool() ? 1 : -1;
      }
      return;
    }
    _gustAge += dt;
    if (_gustAge < 1.8) {
      windTell = (_gustAge / 1.8).clamp(0.0, 1.0);
      wind = _gustDirection * .08 * windTell;
    } else {
      windTell = 0;
      wind =
          _gustDirection *
          sin(((_gustAge - 1.8) / 3).clamp(0.0, 1.0) * pi) *
          .85;
    }
    if (_gustAge >= 4.8) {
      _gustAge = -1;
      _gustClock = (weather == 'storm' ? 10 : 16) + random.nextDouble() * 20;
      wind = 0;
    }
  }

  /// Artistic habitat rules from the species table (`insect_species.dart`):
  /// rain shelters delicate daytime species; each biome's night set fades in
  /// on continuous daylight. Existing bugs fade when their species leaves.
  List<String> get availableSpecies {
    final context = HabitatContext(
      biome: biome,
      daylight: daylight,
      progress: progress,
      period: period,
      cycle: cycle,
      weather: weather,
      rainIntensity: rainIntensity,
    );
    return [
      for (final s in InsectSpecies.table)
        if (s.habitat(context)) s.name,
    ];
  }

  void _spawnBug() {
    final species = availableSpecies;
    final kind = species[random.nextInt(species.length)];
    final info = InsectSpecies.byName[kind]!;
    final angle = random.nextDouble() * pi * 2;
    final speed = info.speed;
    final x = .08 + random.nextDouble() * .84;
    final yRoll = random.nextDouble();
    final phase = random.nextDouble() * pi * 2;
    final (bandLow, bandHigh) = info.altitude;
    bugs.add(
      BugState(
          x: x,
          y: info.night
              ? bandLow + yRoll * (bandHigh - bandLow)
              : .2 + yRoll * .4,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed * .4,
          phase: phase,
          species: kind,
          variant: (phase * 1000).floor() & 1,
        )
        .._heading = angle
        ..opacity = 0,
    );
  }

  void _updateBugs(double dt) {
    if (!started) return;
    bugs.removeWhere((b) => !b.alive);
    final species = availableSpecies;
    final light = InsectSpecies.lightSourceFor(biome);
    for (final bug in bugs) {
      final info = InsectSpecies.byName[bug.species] ?? InsectSpecies.table[0];
      bug.phase = (bug.phase + dt * info.wingRate) % (pi * 2);
      bug._turn =
          bug._turn * exp(-dt * 2) +
          (random.nextDouble() - .5) * sqrt(dt) * info.turn;
      bug._heading += bug._turn * dt;
      final speed = info.speed;
      final (bandLow, bandHigh) = info.altitude;
      var targetX = cos(bug._heading) * speed + wind * .025;
      var targetY =
          sin(bug._heading) * speed * .55 + sin(bug.phase) * info.bob;
      targetX += max(0, .14 - bug.x) * .8 - max(0, bug.x - .86) * .8;
      targetY +=
          max(0, bandLow - bug.y) * .8 - max(0, bug.y - bandHigh) * .8;
      if (info.lightSeeking && light != null) {
        // Moths circle the lantern: pull toward it plus a tangential drift.
        final dx = light.$1 - bug.x;
        final dy = light.$2 - bug.y;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist > .025) {
          final pull = .035 * (dist / .12).clamp(0.0, 1.0);
          targetX += (dx * pull - dy * pull * .8) / dist;
          targetY += (dy * pull * .55 + dx * pull * .5) / dist;
        }
      }
      bug.vx += (targetX - bug.vx) * (1 - exp(-dt * 3));
      bug.vy += (targetY - bug.vy) * (1 - exp(-dt * 3));
      bug.x = (bug.x + bug.vx * dt).clamp(.04, .96);
      bug.y = (bug.y + bug.vy * dt).clamp(.12, info.maxY);
      if (bug.x <= .04 || bug.x >= .96) bug.vx = -bug.vx;
      if (bug.y <= .12 || bug.y >= info.maxY) bug.vy = -bug.vy;
      bug.opacity =
          (bug.opacity + (species.contains(bug.species) ? dt : -dt * .3)).clamp(
            0.0,
            1.0,
          );
      if (bug.opacity == 0) bug.alive = false;
    }
    _spawnClock += dt;
    if (_spawnClock >= .8) {
      _spawnClock -= .8;
      final shelter = insectShelter;
      final emergence = (elapsed / 12).clamp(0.0, 1.0);
      final target = ((3 + richness * 15) * shelter * emergence).ceil();
      if (bugs.length < target) _spawnBug();
    }
  }

  void _emitRipple({
    required double x,
    required double y,
    required double initialRadius,
    required double maxRadius,
    required double duration,
    required double intensity,
    double biasX = 0,
  }) {
    if (!basin.contains(x, y, margin: 6)) return;
    if (ripples.length >= 34) ripples.removeAt(0);
    ripples.add(
      RippleState(
        x: x,
        y: y,
        initialRadius: initialRadius,
        maxRadius: maxRadius,
        duration: duration,
        intensity: intensity,
        biasX: biasX,
      ),
    );
  }

  void _emitSplashDroplets(
    double x,
    double y, {
    required int count,
    required double side,
    required double power,
  }) {
    for (var i = 0; i < count; i++) {
      if (splashDroplets.length >= 42) splashDroplets.removeAt(0);
      final spread = side == 0
          ? (i.isEven ? 1.0 : -1.0) * (16 + _fxRandom.nextDouble() * 32)
          : side * (20 + _fxRandom.nextDouble() * 34);
      final vy = -(24 + _fxRandom.nextDouble() * 30) * power;
      splashDroplets.add(
        SplashDroplet(
          x: x + (_fxRandom.nextDouble() - .5) * 4,
          y: y - 1,
          vx: spread * power,
          vy: vy,
          maxAge: .30 + _fxRandom.nextDouble() * .18,
        ),
      );
    }
  }

  void _updatePads(double dt) {
    final allPads = [...pads, ...ambientPads];
    for (final pad in allPads) {
      final padPxX = pad.x * 641 + pad.driftX;
      final padPxY = pad.y * 359 + pad.floatY;

      // 1. Wave Tripling: Expanding surface ripples rock & nudge lily pads as the wave crest passes
      for (final r in ripples) {
        final dx = padPxX - (r.x + r.biasX * r.progress);
        final dy = (padPxY - r.y) / .34;
        final dist = sqrt(dx * dx + dy * dy);
        final crestDelta = dist - r.currentRadius;
        if (crestDelta.abs() < 9.5 && dist > 3.0) {
          final waveStrength =
              r.intensity * (1.0 - r.progress) * (pad.isAmbient ? 1.35 : .75);
          pad.dipVelocity += sin(crestDelta * .45) * 16.0 * waveStrength * dt;
          pad.tiltVelocity +=
              (dx >= 0 ? 1.0 : -1.0) * 9.5 * waveStrength * dt;
          pad.driftVelocity += (dx / dist) * 14.0 * waveStrength * dt;
          if (pad.isAmbient) {
            pad.floatVelocity += (dy / dist) * 4.5 * waveStrength * dt;
          }
        }
      }

      // 2. Subsurface Fish Wake: Koi swimming near/under a pad nudge and tilt it
      for (final k in koi) {
        if (k.depth > .68) continue;
        final dx = padPxX - k.x;
        final dy = (padPxY - k.y) * 1.8;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < pad.radiusX + 18.0) {
          final wake =
              ((pad.radiusX + 18.0 - dist) / (pad.radiusX + 18.0)) *
              (1.0 - k.depth) *
              (pad.isAmbient ? 1.4 : .7);
          pad.driftVelocity += cos(k.heading) * 18.0 * wake * dt;
          if (pad.isAmbient) {
            pad.floatVelocity += sin(k.heading) * 6.5 * wake * dt;
          }
          pad.tiltVelocity += cos(k.heading) * 7.5 * wake * dt;
          pad.dipVelocity += 6.0 * wake * dt;
        }
      }

      // 3. Ambient Pond Current Drift for floating leaves
      if (pad.isAmbient) {
        pad.driftVelocity +=
            (sin(time * .38 + pad.phase) * 3.8 + wind * 5.0) * dt;
        pad.floatVelocity += cos(time * .31 + pad.phase) * 1.8 * dt;
      }

      // 4. Damped Harmonic Springs
      final ay = -145.0 * pad.dipY - 15.5 * pad.dipVelocity;
      pad.dipVelocity += ay * dt;
      pad.dipY = (pad.dipY + pad.dipVelocity * dt).clamp(-4.5, 6.5);

      final aTilt = -190.0 * pad.tiltAngle - 18.0 * pad.tiltVelocity;
      pad.tiltVelocity += aTilt * dt;
      pad.tiltAngle = (pad.tiltAngle + pad.tiltVelocity * dt).clamp(-.38, .38);

      final maxDrift = pad.isAmbient ? 9.5 : 5.0;
      final kDrift = pad.isAmbient ? 24.0 : 65.0;
      final cDrift = pad.isAmbient ? 6.5 : 12.0;
      final ax = -kDrift * pad.driftX - cDrift * pad.driftVelocity;
      pad.driftVelocity += ax * dt;
      pad.driftX = (pad.driftX + pad.driftVelocity * dt).clamp(
        -maxDrift,
        maxDrift,
      );

      final aFloat = -28.0 * pad.floatY - 7.5 * pad.floatVelocity;
      pad.floatVelocity += aFloat * dt;
      pad.floatY = (pad.floatY + pad.floatVelocity * dt).clamp(-4.0, 4.0);

      // Clamp ambient pad within water basin bounds
      if (pad.isAmbient) {
        final minX = basin.leftX(padPxY) + pad.radiusX + 4;
        final maxX = basin.rightX(padPxY) - pad.radiusX - 4;
        final worldX = pad.x * 641 + pad.driftX;
        if (worldX < minX) pad.driftX = minX - pad.x * 641;
        if (worldX > maxX) pad.driftX = maxX - pad.x * 641;
      }

      // Dewdrop bead oscillation
      final aDrop =
          -310.0 * pad.dewdropBounce - 22.0 * pad.dewdropVelocity + 0.35 * ay;
      pad.dewdropVelocity += aDrop * dt;
      pad.dewdropBounce = (pad.dewdropBounce + pad.dewdropVelocity * dt).clamp(
        -3.5,
        3.5,
      );

      // Edge fold uncurls smoothly
      pad.edgeFold *= exp(-dt / .18);
      if (pad.edgeFold < .01) pad.edgeFold = 0;
      pad.waterWashAlpha = (pad.edgeFold * .72).clamp(0.0, 1.0);
    }
  }

  void _updateRipplesAndSplashes(double dt) {
    for (final r in ripples) {
      r.age += dt;
    }
    ripples.removeWhere((r) => r.age >= r.duration);

    for (final d in splashDroplets) {
      d.age += dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.vy += 195.0 * dt;
    }
    splashDroplets.removeWhere((d) => d.age >= d.maxAge);
  }

  void _updateRain(double dt) {
    if (!raining) {
      raindrops.clear();
      return;
    }
    // Everything scales on the envelope: ~17 drops at 0.3, 42 at a downpour.
    // Streaks beyond intensity 0.7 are drawn by the renderer only, so the
    // physical drop count and the 34-ripple cap stay bounded.
    final intensity = rainIntensity;
    final targetCount = (6 + 36 * intensity).round();
    final spawnRate = 20.0 + 90.0 * intensity;
    final toSpawn = (spawnRate * dt + (_fxRandom.nextDouble() < .4 ? 1 : 0))
        .floor();

    for (var i = 0; i < toSpawn && raindrops.length < targetCount; i++) {
      final ty =
          basin.topY +
          6.0 +
          _fxRandom.nextDouble() * (basin.bottomY - basin.topY - 12.0);
      final left = basin.leftX(ty) + 10.0;
      final right = basin.rightX(ty) - 10.0;
      if (right <= left) continue;
      final tx = left + _fxRandom.nextDouble() * (right - left);
      final vy = 240.0 + _fxRandom.nextDouble() * 75.0;
      final vx = wind * 38.0 - 16.0;
      final fallTime = .45 + _fxRandom.nextDouble() * .55;
      raindrops.add(
        RaindropState(
          x: tx - vx * fallTime,
          y: ty - vy * fallTime,
          vx: vx,
          vy: vy,
          targetX: tx,
          targetY: ty,
          length: (5.0 + _fxRandom.nextDouble() * 4.5) * (.8 + .5 * intensity),
        ),
      );
    }

    final allPads = [...pads, ...ambientPads];
    for (var i = raindrops.length - 1; i >= 0; i--) {
      final drop = raindrops[i];
      drop.x += drop.vx * dt;
      drop.y += drop.vy * dt;
      if (drop.y >= drop.targetY) {
        // Raindrop impact with lily pad or pond water surface!
        PadState? hitPad;
        for (final pad in allPads) {
          final px = pad.x * 641 + pad.driftX;
          final py = pad.y * 359 + pad.floatY + pad.dipY;
          final nx = (drop.targetX - px) / pad.radiusX;
          final ny = (drop.targetY - py) / pad.radiusY;
          if (nx * nx + ny * ny <= 1.05) {
            hitPad = pad;
            break;
          }
        }
        if (hitPad != null) {
          // Raindrop strikes a lily pad: patter dip, tilt, dewdrop bounce & micro-splatter
          final px = hitPad.x * 641 + hitPad.driftX;
          final offset = ((drop.targetX - px) / hitPad.radiusX).clamp(
            -1.0,
            1.0,
          );
          final weight = hitPad.isAmbient ? 1.35 : .75;
          hitPad.dipVelocity += 3.8 * weight;
          hitPad.tiltVelocity += offset * 2.8 * weight;
          hitPad.dewdropVelocity += 11.0;
          _emitSplashDroplets(
            drop.targetX,
            drop.targetY - 1,
            count: 2,
            side: offset >= 0 ? 1 : -1,
            power: .36,
          );
        } else {
          // Raindrop strikes open pond water: concentric rain ripple + tiny splash crown
          _emitRipple(
            x: drop.targetX,
            y: drop.targetY,
            initialRadius: 1.2,
            maxRadius: 13.0 + _fxRandom.nextDouble() * 9.0,
            duration: .68,
            intensity: .30 + .14 * intensity,
          );
          if (_fxRandom.nextDouble() < .55) {
            _emitSplashDroplets(
              drop.targetX,
              drop.targetY,
              count: 2,
              side: 0,
              power: .32,
            );
          }
        }
        raindrops.removeAt(i);
      }
    }
  }

  void _startleWildlife(double impactX, double impactY, double impulse) {
    for (final k in koi) {
      final dx = k.x - impactX;
      final dy = k.y - impactY;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 155) {
        final factor = ((155 - dist) / 155) * impulse;
        k.startleTimer = max(
          k.startleTimer,
          (.65 + factor * .75).clamp(0, 1.4),
        );
        k.targetHeading = atan2(dy, dx);
        if (k.depth < .45) {
          _emitRipple(
            x: k.x,
            y: k.y,
            initialRadius: 3,
            maxRadius: 22,
            duration: .85,
            intensity: .28 * factor,
          );
        }
      }
    }
    for (final t in tadpoles) {
      final dx = t.x - impactX;
      final dy = t.y - impactY;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 140) {
        t.startleTimer = 1.0;
        t.heading = atan2(dy, dx);
      }
    }
  }

  void _updateWildlife(double dt) {
    for (final k in koi) {
      k.startleTimer = max(0, k.startleTimer - dt * .85);
      final speedBoost = 1.0 + k.startleTimer * 2.4;
      final speed = (14.0 + (k.index % 2) * 3.5) * speedBoost;
      k.swimPhase = (k.swimPhase + dt * 2.6 * speedBoost) % (pi * 20);

      final minX = basin.leftX(k.y) + 22.0;
      final maxX = basin.rightX(k.y) - 22.0;
      final minY = basin.topY + 14.0;
      final maxY = basin.bottomY - 12.0;

      if (k.x < minX + 16) {
        k.targetHeading = 0.08 * (k.index.isEven ? 1 : -1);
      } else if (k.x > maxX - 16) {
        k.targetHeading = pi - 0.08 * (k.index.isEven ? 1 : -1);
      }
      if (k.y < minY + 10) {
        k.targetHeading = pi * .35;
      } else if (k.y > maxY - 10) {
        k.targetHeading = -pi * .35;
      }

      var diff = k.targetHeading - k.heading;
      while (diff > pi) {
        diff -= pi * 2;
      }
      while (diff < -pi) {
        diff += pi * 2;
      }
      final turnRate = k.startleTimer > 0 ? 4.5 : 1.4;
      k.heading += diff.clamp(-turnRate * dt, turnRate * dt);
      k.heading += sin(time * .45 + k.index * 1.9) * .18 * dt;

      k.y = (k.y + sin(k.heading) * speed * .55 * dt).clamp(minY, maxY);
      final clampedLeft = basin.leftX(k.y) + 18.0;
      final clampedRight = basin.rightX(k.y) - 18.0;
      k.x = (k.x + cos(k.heading) * speed * dt).clamp(
        clampedLeft,
        max(clampedLeft + 1, clampedRight),
      );

      final prevDepth = k.depth;
      final targetDepth =
          (.36 +
                  (k.index % 3) * .12 +
                  sin(time * .38 + k.index * 1.7) * .26 +
                  k.startleTimer * .35)
              .clamp(.08, .92);
      k.depth += (targetDepth - k.depth) * (1 - exp(-dt * 2.8));
      k.pitch = ((k.depth - prevDepth) / max(dt, 1e-4) * 1.8).clamp(-.45, .45);
    }

    for (final t in tadpoles) {
      t.startleTimer = max(0, t.startleTimer - dt * 1.2);
      final boost = 1.0 + t.startleTimer * 2.6;
      final speed = 22.0 * boost;
      t.swimPhase = (t.swimPhase + dt * 6.8 * boost) % (pi * 20);
      t.heading += sin(time * 1.3 + t.index * 2.1) * .65 * dt;
      final minX = basin.leftX(t.y) + 14.0;
      final maxX = basin.rightX(t.y) - 14.0;
      final minY = basin.topY + 10.0;
      final maxY = basin.bottomY - 10.0;
      if (t.x < minX + 8 || t.x > maxX - 8) t.heading = pi - t.heading;
      if (t.y < minY + 6 || t.y > maxY - 6) t.heading = -t.heading;
      t.y = (t.y + sin(t.heading) * speed * .6 * dt).clamp(minY, maxY);
      t.x = (t.x + cos(t.heading) * speed * dt).clamp(
        basin.leftX(t.y) + 12.0,
        max(basin.leftX(t.y) + 14.0, basin.rightX(t.y) - 12.0),
      );
    }
  }
}

/// Per-biome trapezoidal open-water basin in logical `641 × 359` coordinates
/// and grounded hero lily pad coordinates (`pad0X, pad0Y`, `pad1X, pad1Y`).
class WaterBasin {
  const WaterBasin({
    required this.topY,
    required this.bottomY,
    required this.topLeftX,
    required this.topRightX,
    required this.bottomLeftX,
    required this.bottomRightX,
    required this.pad0X,
    required this.pad0Y,
    required this.pad1X,
    required this.pad1Y,
  });

  final double topY;
  final double bottomY;
  final double topLeftX;
  final double topRightX;
  final double bottomLeftX;
  final double bottomRightX;
  final double pad0X;
  final double pad0Y;
  final double pad1X;
  final double pad1Y;

  double leftX(double y) {
    final t = ((y - topY) / max(1.0, bottomY - topY)).clamp(0.0, 1.0);
    return topLeftX + (bottomLeftX - topLeftX) * t;
  }

  double rightX(double y) {
    final t = ((y - topY) / max(1.0, bottomY - topY)).clamp(0.0, 1.0);
    return topRightX + (bottomRightX - topRightX) * t;
  }

  bool contains(double x, double y, {double margin = 0}) {
    if (y < topY + margin || y > bottomY - margin) return false;
    return x >= leftX(y) + margin && x <= rightX(y) - margin;
  }

  static WaterBasin forBiome(String biome) => switch (biome) {
    'grotto' || 'crystal_grotto' => const WaterBasin(
      topY: 248,
      bottomY: 328,
      topLeftX: 244,
      topRightX: 396,
      bottomLeftX: 188,
      bottomRightX: 452,
      pad0X: .36,
      pad0Y: .77,
      pad1X: .63,
      pad1Y: .78,
    ),
    'sanctuary' || 'jade_sanctuary' => const WaterBasin(
      topY: 244,
      bottomY: 328,
      topLeftX: 246,
      topRightX: 434,
      bottomLeftX: 192,
      bottomRightX: 456,
      pad0X: .36,
      pad0Y: .76,
      pad1X: .65,
      pad1Y: .76,
    ),
    'alpine' => const WaterBasin(
      topY: 238,
      bottomY: 330,
      topLeftX: 224,
      topRightX: 428,
      bottomLeftX: 176,
      bottomRightX: 462,
      pad0X: .34,
      pad0Y: .75,
      pad1X: .65,
      pad1Y: .76,
    ),
    'maple' || 'autumn_mist' => const WaterBasin(
      topY: 228,
      bottomY: 326,
      topLeftX: 206,
      topRightX: 436,
      bottomLeftX: 184,
      bottomRightX: 454,
      pad0X: .33,
      pad0Y: .73,
      pad1X: .66,
      pad1Y: .75,
    ),
    'cypress' => const WaterBasin(
      topY: 242,
      bottomY: 328,
      topLeftX: 218,
      topRightX: 420,
      bottomLeftX: 182,
      bottomRightX: 450,
      pad0X: .33,
      pad0Y: .75,
      pad1X: .65,
      pad1Y: .76,
    ),
    'blossom' || 'lotus' => const WaterBasin(
      topY: 236,
      bottomY: 328,
      topLeftX: 206,
      topRightX: 440,
      bottomLeftX: 174,
      bottomRightX: 466,
      pad0X: .32,
      pad0Y: .74,
      pad1X: .66,
      pad1Y: .75,
    ),
    _ => const WaterBasin(
      topY: 228,
      bottomY: 328,
      topLeftX: 210,
      topRightX: 432,
      bottomLeftX: 186,
      bottomRightX: 452,
      pad0X: .34,
      pad0Y: .73,
      pad1X: .65,
      pad1Y: .75,
    ),
  };
}

class FrogState {
  FrogState(this.index, this.homeX, this.homeY)
    : x = homeX,
      y = homeY,
      leafIndex = index,
      facing = index == 0 ? 1.0 : -1.0,
      _targetLeaf = index;
  final int index;
  final double homeX, homeY;
  double x, y;
  double jumpPhase = 0;
  double tongue = 0;
  double tongueX = 0, tongueY = 0;
  double chompTimer = 0;
  double landingTimer = 0;
  double swallowTimer = 0;
  int caughtInFlight = 0;
  int totalCatches = 0;
  String? lastCaughtSpecies;
  double lastImpactOffset = 0;
  double facing;
  double energy = 1;
  bool airborne = false;
  bool swimming = false;
  bool asleep = false;
  int leafIndex;
  String action = 'tap';
  double cooldown = 1;
  double bellyFlop = 0;
  double _fromX = 0, _fromY = 0, _toX = 0, _toY = 0;
  double _duration = 1, _swimAge = 0, _splashX = 0;
  int _targetLeaf;
  bool _returning = false;

  double get swimAge => _swimAge;
  double get fromX => _fromX;
  double get fromY => _fromY;
  double get toX => _toX;
  double get toY => _toY;
  int get targetLeaf => _targetLeaf;

  /// Ground-plane Y coordinate on the pond/pad surface directly beneath the frog.
  double get groundY =>
      airborne ? (_fromY + (_toY - _fromY) * jumpPhase) : y;

  /// Vertical height above the pond/pad surface (`0.0` when perched or swimming).
  double get altitude => airborne ? max(0.0, groundY - y) : 0.0;

  /// Current animation state name across the 10-state frog animation system.
  String currentPose({bool charging = false}) {
    if (asleep) return 'sleeping';
    if (swimming) return 'swimming';
    if (airborne) {
      if (tongue > 0 || chompTimer > 0) return 'chomping';
      if (jumpPhase < .18) return 'launching';
      if (jumpPhase < .52) return 'ascending';
      return 'falling';
    }
    if (charging) return 'charging';
    if (landingTimer > 0) return 'landing';
    if (swallowTimer > 0) return 'swallowing';
    return 'idle';
  }
}

class PadState {
  PadState({
    required this.index,
    required this.x,
    required this.y,
    required this.radiusX,
    required this.radiusY,
    this.isAmbient = false,
    this.hasLotus = false,
    this.phase = 0,
  });
  final int index;
  final double x, y;
  final double radiusX, radiusY;
  final bool isAmbient;
  final bool hasLotus;
  final double phase;
  double dipY = 0;
  double dipVelocity = 0;
  double tiltAngle = 0;
  double tiltVelocity = 0;
  double driftX = 0;
  double driftVelocity = 0;
  double floatY = 0;
  double floatVelocity = 0;
  double edgeFold = 0;
  double edgeFoldSide = 1;
  double waterWashAlpha = 0;
  double dewdropBounce = 0;
  double dewdropVelocity = 0;
  String landingZone = 'none';
}

class KoiState {
  KoiState({
    required this.index,
    required this.variant,
    required this.x,
    required this.y,
    required this.heading,
    required this.swimPhase,
    required this.depth,
  }) : targetHeading = heading;
  final int index;
  final int variant;
  double x, y;
  double heading;
  double targetHeading;
  double swimPhase;
  double depth;
  double pitch = 0;
  double startleTimer = 0;
}

class TadpoleState {
  TadpoleState({
    required this.index,
    required this.x,
    required this.y,
    required this.heading,
    required this.swimPhase,
  });
  final int index;
  double x, y;
  double heading;
  double swimPhase;
  double startleTimer = 0;
}

class RippleState {
  RippleState({
    required this.x,
    required this.y,
    required this.initialRadius,
    required this.maxRadius,
    required this.duration,
    required this.intensity,
    this.biasX = 0,
  });
  final double x, y;
  final double initialRadius;
  final double maxRadius;
  final double duration;
  final double intensity;
  final double biasX;
  double age = 0;

  double get progress => (age / duration).clamp(0.0, 1.0);
  double get currentRadius =>
      initialRadius + (maxRadius - initialRadius) * (1 - pow(1 - progress, 2));
}

class SplashDroplet {
  SplashDroplet({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.maxAge,
  });
  double x, y, vx, vy;
  final double maxAge;
  double age = 0;
}

class RaindropState {
  RaindropState({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.targetX,
    required this.targetY,
    required this.length,
  });
  double x, y;
  final double vx, vy;
  final double targetX, targetY;
  final double length;
}

class BugState {
  BugState({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.phase,
    required this.species,
    this.variant = 0,
  });
  double x, y, vx, vy, phase;
  String species;

  /// Small per-insect look variation (glow beetles: 0 cyan, 1 violet).
  final int variant;
  bool alive = true;
  double opacity = 1;
  double _heading = 0, _turn = 0;
}
