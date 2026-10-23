import 'dart:math';

import 'jump_policy.dart';

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
    frogs = [FrogState(0, .27, .69), FrogState(1, .73, .72)];
    pads = [
      PadState(index: 0, x: .27, y: .69, radiusX: 36, radiusY: 11),
      PadState(index: 1, x: .73, y: .72, radiusX: 38, radiusY: 12),
    ];
    _fxRandom = Random(sceneSeed ^ 0x5f3759df);
    koi = List.generate(4, (i) {
      final startX = 135.0 + i * 115.0 + (_fxRandom.nextDouble() - .5) * 30.0;
      final startY = 232.0 + (i % 2) * 44.0 + (_fxRandom.nextDouble() - .5) * 18.0;
      return KoiState(
        index: i,
        variant: i,
        x: startX,
        y: startY,
        heading: i.isEven ? 0.12 : pi - 0.12,
        swimPhase: i * 1.57,
        depth: 0.25 + (i % 3) * 0.18,
      );
    });
    tadpoles = List.generate(6, (i) {
      return TadpoleState(
        index: i,
        x: 120.0 + i * 76.0 + (_fxRandom.nextDouble() - .5) * 24.0,
        y: 215.0 + (i % 3) * 36.0,
        heading: _fxRandom.nextDouble() * pi * 2,
        swimPhase: i * 1.1,
      );
    });
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
  }

  static const List<String> biomes = [
    'willow',
    'blossom',
    'cypress',
    'maple',
    'sanctuary',
    'grotto',
    'alpine',
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

  /// Scenic landscape WebP filename matching [biome].
  String get backdropAsset => switch (biome) {
    'cypress' => 'pond-mist.webp',
    'blossom' => 'pond-blossom.webp',
    'maple' => 'pond-maple.webp',
    'sanctuary' => 'pond-sanctuary.webp',
    'grotto' => 'pond-grotto.webp',
    'alpine' => 'pond-alpine.webp',
    _ => 'pond-dusk.webp',
  };

  /// Transparent foreground parallax WebP filename matching [biome].
  String get foregroundAsset => switch (biome) {
    'blossom' || 'maple' || 'sanctuary' => 'foreground-blossom.webp',
    'grotto' => 'foreground-grotto.webp',
    _ => 'foreground-marsh.webp',
  };

  /// Persistent scene weather; gusts are expressed by wind and windTell.
  late String weather;

  /// Seeded once: dusk (75%) or dawn (25%). Does not loop after sleep.
  late final String cycle;
  late String period;

  /// Renderer palette interpolation: dawn dark blue -> golden sunrise,
  /// dusk warm daylight -> blue night. Continues to hold its endpoint asleep.
  /// A rare smooth underwater disturbance; the pads visibly wobble first.
  double get leafNudge => started && !sleeping && !_settling && progress > .45
      ? pow(max(0.0, sin(time * .071 + sceneSeed % 37)), 40).toDouble()
      : 0.0;

  double get daylight => cycle == 'dawn' ? progress : 1 - progress;
  late final List<FrogState> frogs;
  late final List<PadState> pads;
  late final List<KoiState> koi;
  late final List<TadpoleState> tadpoles;
  final List<RippleState> ripples = [];
  final List<SplashDroplet> splashDroplets = [];
  late final Random _fxRandom;
  final List<BugState> bugs = [];

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
  double _remainder = 0;
  double _aiClock = 0;
  double _spawnClock = 0;
  double _gustClock = 12;
  double _gustAge = -1;
  double _gustDirection = 1;
  double _tapAgitation = 0;
  double _lastRelease = -100;
  String? _queuedAction;
  bool _settling = false;
  static const double _step = 1 / 60;

  /// Repeated down events are ignored. The first completed gesture starts play.
  void press() {
    if (sleeping || _settling || pressing) return;
    _pressStarted = time + _remainder;
  }

  /// Holds below .18s tap, below .65s jump low, otherwise jump high.
  /// While busy, only the most recent gesture is retained (no runaway queue).
  void release() {
    if (!pressing) return;
    final held = holdDuration;
    _pressStarted = null;
    if (sleeping || _settling) return;
    started = true;
    if (time - _lastRelease < .3) _tapAgitation = min(1, _tapAgitation + .2);
    _lastRelease = time;
    engagement = min(1, engagement + .075);
    _queuedAction = held < .18 - 1e-9
        ? 'tap'
        : held < .65 - 1e-9
        ? 'low'
        : 'high';
    _dispatch();
  }

  /// Pointer cancellation never starts play or launches a frog.
  void cancelPress() => _pressStarted = null;

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
        _queuedAction = null;
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
    _updateWind(dt);
    _updateBugs(dt);
    for (final frog in frogs) {
      _updateFrog(frog, dt);
    }
    _updatePads(dt);
    _updateRipplesAndSplashes(dt);
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
    _dispatch();
    _aiClock += dt;
    if (_aiClock + 1e-9 >= .25) {
      _aiClock -= .25;
      _evaluateJev();
    }
  }

  bool get _busy => frogs.any((f) => f.airborne || f.swimming);

  void _dispatch() {
    if (_queuedAction == null || _busy || _settling || sleeping) return;
    _launch(frogs[0], _queuedAction!);
    _queuedAction = null;
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
  static double _leafX(int leaf) => leaf == 0 ? .27 : .73;
  static double _leafY(int leaf) => leaf == 0 ? .69 : .72;

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
    frog._toX += cos(angle) * radius * sign;
    frog._toY += sin(angle) * radius * sign;
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
      x: sourcePad.x * 641,
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
        frog._splashX = (frog._toX + wind * .04).clamp(.05, .95);
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
    final padPxX = pad.x * 641;
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
  /// At 4 Hz, eligible decisions project bugs through three candidate arcs;
  /// one prior suggestion gives only a small tie-break bonus. Teacher imitation
  /// does not establish gameplay efficacy. Timing and safety stay geometric.
  void _evaluateJev() {
    aiEvaluations++;
    final frog = frogs[1];
    if (_busy || frog.cooldown > 0 || _queuedAction != null) return;
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

  /// Artistic habitat rules: rain shelters delicate daytime species; luminous
  /// insects occur only in dry twilight/darkness. Existing bugs fade on change.
  List<String> get availableSpecies {
    final dry = weather == 'clear' || weather == 'mist';
    final light = period == 'day' || (period == 'dawn' && progress >= .55);
    return [
      if (weather != 'storm' && light) 'fly',
      'mosquito',
      if (dry && light && progress >= .12) 'dragonfly',
      if (weather == 'clear' && light && progress >= .25) 'butterfly',
      if (dry && light && progress >= .38) 'ladybug',
      if (dry && !light && (cycle == 'dawn' || progress >= .55)) 'firefly',
    ];
  }

  void _spawnBug() {
    final species = availableSpecies;
    final kind = species[random.nextInt(species.length)];
    final angle = random.nextDouble() * pi * 2;
    final speed = kind == 'dragonfly'
        ? .12
        : kind == 'butterfly'
        ? .045
        : .07;
    bugs.add(
      BugState(
          x: .08 + random.nextDouble() * .84,
          y: .2 + random.nextDouble() * .4,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed * .4,
          phase: random.nextDouble() * pi * 2,
          species: kind,
        )
        .._heading = angle
        ..opacity = 0,
    );
  }

  void _updateBugs(double dt) {
    if (!started) return;
    bugs.removeWhere((b) => !b.alive);
    final species = availableSpecies;
    for (final bug in bugs) {
      bug.phase =
          (bug.phase + dt * (bug.species == 'mosquito' ? 13 : 5)) % (pi * 2);
      // Correlated angular noise, smooth velocity relaxation, and soft edge
      // steering produce meanders instead of independent positional jitter.
      bug._turn =
          bug._turn * exp(-dt * 2) +
          (random.nextDouble() - .5) * sqrt(dt) * 1.8;
      bug._heading += bug._turn * dt;
      final speed = bug.species == 'dragonfly'
          ? .12
          : bug.species == 'butterfly'
          ? .045
          : .07;
      var targetX = cos(bug._heading) * speed + wind * .025;
      var targetY = sin(bug._heading) * speed * .55 + sin(bug.phase) * .008;
      targetX += max(0, .14 - bug.x) * .8 - max(0, bug.x - .86) * .8;
      targetY += max(0, .22 - bug.y) * .8 - max(0, bug.y - .58) * .8;
      bug.vx += (targetX - bug.vx) * (1 - exp(-dt * 3));
      bug.vy += (targetY - bug.vy) * (1 - exp(-dt * 3));
      bug.x = (bug.x + bug.vx * dt).clamp(.04, .96);
      bug.y = (bug.y + bug.vy * dt).clamp(.12, .65);
      if (bug.x <= .04 || bug.x >= .96) bug.vx = -bug.vx;
      if (bug.y <= .12 || bug.y >= .65) bug.vy = -bug.vy;
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
      final shelter = weather == 'storm'
          ? .25
          : weather == 'drizzle'
          ? .55
          : 1.0;
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
    if (ripples.length >= 28) ripples.removeAt(0);
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
      if (splashDroplets.length >= 36) splashDroplets.removeAt(0);
      final spread = side == 0
          ? (i.isEven ? 1.0 : -1.0) * (18 + _fxRandom.nextDouble() * 34)
          : side * (22 + _fxRandom.nextDouble() * 34);
      final vy = -(26 + _fxRandom.nextDouble() * 32) * power;
      splashDroplets.add(
        SplashDroplet(
          x: x + (_fxRandom.nextDouble() - .5) * 4,
          y: y - 1,
          vx: spread * power,
          vy: vy,
          maxAge: .32 + _fxRandom.nextDouble() * .18,
        ),
      );
    }
  }

  void _updatePads(double dt) {
    for (final pad in pads) {
      // Vertical hydrostatic spring: y'' = -145 y - 15.5 y'
      final ay = -145.0 * pad.dipY - 15.5 * pad.dipVelocity;
      pad.dipVelocity += ay * dt;
      pad.dipY = (pad.dipY + pad.dipVelocity * dt).clamp(-4.5, 6.5);

      // Pitch/roll spring: theta'' = -190 theta - 18 theta'
      final aTilt = -190.0 * pad.tiltAngle - 18.0 * pad.tiltVelocity;
      pad.tiltVelocity += aTilt * dt;
      pad.tiltAngle = (pad.tiltAngle + pad.tiltVelocity * dt).clamp(-.38, .38);

      // Lateral drift spring: x'' = -65 x - 12 x'
      final ax = -65.0 * pad.driftX - 12.0 * pad.driftVelocity;
      pad.driftVelocity += ax * dt;
      pad.driftX = (pad.driftX + pad.driftVelocity * dt).clamp(-5.0, 5.0);

      // Dewdrop bead oscillation
      final aDrop =
          -310.0 * pad.dewdropBounce - 22.0 * pad.dewdropVelocity + 0.35 * ay;
      pad.dewdropVelocity += aDrop * dt;
      pad.dewdropBounce = (pad.dewdropBounce + pad.dewdropVelocity * dt).clamp(
        -3.5,
        3.5,
      );

      // Edge fold uncurls smoothly over ~0.65s
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
      d.vy += 195.0 * dt; // Gravity
    }
    splashDroplets.removeWhere((d) => d.age >= d.maxAge);

    // Subtle rain surface ripples during drizzle/storm
    if ((weather == 'drizzle' || weather == 'storm') &&
        ripples.length < 18 &&
        _fxRandom.nextDouble() < (weather == 'storm' ? .28 : .12)) {
      _emitRipple(
        x: 70 + _fxRandom.nextDouble() * 500,
        y: 195 + _fxRandom.nextDouble() * 140,
        initialRadius: 1.5,
        maxRadius: 14 + _fxRandom.nextDouble() * 10,
        duration: .75,
        intensity: .32,
      );
    }
  }

  void _startleWildlife(double impactX, double impactY, double impulse) {
    for (final k in koi) {
      final dx = k.x - impactX;
      final dy = k.y - impactY;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 155) {
        final factor = ((155 - dist) / 155) * impulse;
        k.startleTimer = max(k.startleTimer, (.65 + factor * .75).clamp(0, 1.4));
        k.targetHeading = atan2(dy, dx);
        // Subtle subsurface swirl ripple when startled near surface
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

      // Smooth bank avoidance inside the pond basin (x: 85..555, y: 195..336)
      if (k.x < 105) {
        k.targetHeading = 0.08 * (k.index.isEven ? 1 : -1);
      } else if (k.x > 535) {
        k.targetHeading = pi - 0.08 * (k.index.isEven ? 1 : -1);
      }
      if (k.y < 205) {
        k.targetHeading = pi * .35;
      } else if (k.y > 328) {
        k.targetHeading = -pi * .35;
      }

      // Shortest angular turn toward targetHeading + gentle meander
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

      k.x = (k.x + cos(k.heading) * speed * dt).clamp(72.0, 568.0);
      k.y = (k.y + sin(k.heading) * speed * .55 * dt).clamp(192.0, 338.0);
      final baseDepth = .24 + (k.index % 3) * .16 + sin(time * .3 + k.index) * .08;
      k.depth = (baseDepth + k.startleTimer * .28).clamp(.15, .85);
    }

    for (final t in tadpoles) {
      t.startleTimer = max(0, t.startleTimer - dt * 1.2);
      final boost = 1.0 + t.startleTimer * 2.6;
      final speed = 22.0 * boost;
      t.swimPhase = (t.swimPhase + dt * 6.8 * boost) % (pi * 20);
      t.heading += sin(time * 1.3 + t.index * 2.1) * .65 * dt;
      if (t.x < 95 || t.x > 545) t.heading = pi - t.heading;
      if (t.y < 200 || t.y > 332) t.heading = -t.heading;
      t.x = (t.x + cos(t.heading) * speed * dt).clamp(80.0, 560.0);
      t.y = (t.y + sin(t.heading) * speed * .6 * dt).clamp(195.0, 336.0);
    }
  }
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
  });
  final int index;
  final double x, y;
  final double radiusX, radiusY;
  double dipY = 0;
  double dipVelocity = 0;
  double tiltAngle = 0;
  double tiltVelocity = 0;
  double driftX = 0;
  double driftVelocity = 0;
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

class BugState {
  BugState({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.phase,
    required this.species,
  });
  double x, y, vx, vy, phase;
  String species;
  bool alive = true;
  double opacity = 1;
  double _heading = 0, _turn = 0;
}
