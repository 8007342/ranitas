import 'dart:math';

import 'jump_policy.dart';

/// A deterministic, renderer-independent pond. Coordinates use a portrait
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
    biome = ['willow', 'blossom', 'cypress'][random.nextInt(3)];
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
    frog.energy = max(.2, frog.energy - .08);
  }

  void _updateFrog(FrogState frog, double dt) {
    frog.tongue = max(0, frog.tongue - dt * 5);
    frog.cooldown = max(0, frog.cooldown - dt);
    frog.energy = min(1, frog.energy + dt * .035);
    frog.bellyFlop = max(0, frog.bellyFlop - dt * 2);
    if (frog.swimming) {
      frog._swimAge += dt;
      final p = (frog._swimAge / 1.6).clamp(0.0, 1.0);
      final s = p * p * (3 - 2 * p);
      frog.x = frog._splashX + (frog._toX - frog._splashX) * s;
      frog.y = frog._toY + .065 * (1 - s) + sin(p * pi * 4) * .006 * (1 - p);
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
          frog.tongueX = bug.x;
          frog.tongueY = bug.y;
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
    frog.cooldown = 1.1 + random.nextDouble() * 1.3;
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
}

class FrogState {
  FrogState(this.index, this.homeX, this.homeY)
    : x = homeX,
      y = homeY,
      leafIndex = index,
      _targetLeaf = index;
  final int index;
  final double homeX, homeY;
  double x, y;
  double jumpPhase = 0;
  double tongue = 0;
  double tongueX = 0, tongueY = 0;
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
