import 'dart:math';

/// Seeded, piecewise-smooth rain intensity for drizzle and storm sessions
/// (design D1 of the visual-envelope change).
///
/// The envelope is a pure function of `(seed, weather, time)`: it owns its own
/// `Random` stream, so sampling it never disturbs the model's main draw order,
/// and the node list extends lazily in a fixed order, so the value at a time
/// does not depend on how the caller partitioned its updates.
///
/// Nodes are 45–150 s apart and joined by smoothstep, which bounds the slope
/// to `1.5 × Δv / Δt ≤ 1.5 × 0.95 / 45 ≈ 0.032 /s`, inside the 0.05 /s limit.
class RainEnvelope {
  RainEnvelope({required int seed, required String weather})
    : kind = weather == 'storm'
          ? 'storm'
          : weather == 'drizzle'
          ? 'drizzle'
          : 'dry',
      _random = Random(seed ^ 0x2e7a9d1b) {
    if (kind == 'dry') return;
    _times.add(0);
    _values.add(
      kind == 'storm'
          ? _range(stormStartMin, stormStartMax)
          : _range(drizzleStartMin, drizzleStartMax),
    );
  }

  /// `storm`, `drizzle` or `dry` (clear and mist never rain).
  final String kind;
  final Random _random;
  final List<double> _times = [];
  final List<double> _values = [];
  int _cursor = 0;

  static const double segmentMin = 45;
  static const double segmentMax = 150;
  static const double lullMin = .05;
  static const double lullMax = .12;

  static const double stormStartMin = .35;
  static const double stormStartMax = .48;
  static const double stormDownpourMin = .88;
  static const double stormDownpourMax = 1.0;
  static const double stormLowMin = .35;
  static const double stormLowMax = .6;
  static const double stormHighMin = .6;
  static const double stormHighMax = .88;

  static const double drizzleStartMin = .2;
  static const double drizzleStartMax = .45;
  static const double drizzleLowMin = .15;
  static const double drizzleLowMax = .3;
  static const double drizzleHighMin = .35;
  static const double drizzleHighMax = .55;

  bool get isDry => kind == 'dry';

  double _range(double lo, double hi) => lo + _random.nextDouble() * (hi - lo);

  /// Appends one node. Exactly the same draws happen for a given history, so
  /// the sequence is reproducible however far ahead a caller samples.
  void _append() {
    final previous = _values.last;
    final duration = _range(segmentMin, segmentMax);
    final roll = _random.nextDouble();
    final double next;
    if (kind == 'storm') {
      if (_values.length == 1) {
        // Every storm has a guaranteed downpour inside its first 150 s.
        next = _range(stormDownpourMin, stormDownpourMax);
      } else if (previous >= .7) {
        next = roll < .25
            ? _range(lullMin, lullMax)
            : _range(stormLowMin, stormLowMax);
      } else {
        next = roll < .6
            ? _range(stormDownpourMin, stormDownpourMax)
            : _range(stormHighMin, stormHighMax);
      }
    } else {
      if (previous > .33) {
        next = roll < .2
            ? _range(lullMin, lullMax)
            : _range(drizzleLowMin, drizzleLowMax);
      } else {
        next = _range(drizzleHighMin, drizzleHighMax);
      }
    }
    _times.add(_times.last + duration);
    _values.add(next);
  }

  /// Intensity in `[0, 1]` at [time] seconds; zero for dry sessions.
  double at(double time) {
    if (kind == 'dry') return 0;
    final t = time.isFinite ? max(0.0, time) : 0.0;
    while (_times.last <= t) {
      _append();
    }
    if (t < _times[_cursor]) _cursor = 0;
    while (_times[_cursor + 1] <= t) {
      _cursor++;
    }
    final t0 = _times[_cursor];
    final t1 = _times[_cursor + 1];
    final u = ((t - t0) / (t1 - t0)).clamp(0.0, 1.0);
    final s = u * u * (3 - 2 * u);
    final v0 = _values[_cursor];
    final v1 = _values[_cursor + 1];
    return (v0 + (v1 - v0) * s).clamp(0.0, 1.0);
  }

  /// Insect shelter for a rain intensity (experience spec): 1 when dry, 0.55
  /// at intensity 0.3, 0.25 at intensity 1, rising back toward 1 in lulls.
  static double shelterFor(double intensity) {
    final i = intensity.clamp(0.0, 1.0);
    if (i <= .3) return 1 - (1 - .55) * (i / .3);
    return .55 - .30 * ((i - .3) / .7);
  }

  /// Cloud darkening in `[0, 1]`, used by the scene grade.
  static double cloudFor(double intensity) {
    final c = ((intensity - .06) / .84).clamp(0.0, 1.0);
    return c * c * (3 - 2 * c);
  }

  /// Weather label handed to the ambience (no API change): storm audio only
  /// while the rain is actually heavy.
  static String audioLabel(String weather, double intensity) {
    if (weather != 'drizzle' && weather != 'storm') return weather;
    return intensity >= .6 ? 'storm' : 'drizzle';
  }
}
