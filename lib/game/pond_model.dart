import 'dart:math';

import 'insect_species.dart';
import 'jump_policy.dart';
import 'rain_envelope.dart';
import 'awakening.dart';

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
    rainIntensity = _rainAt(0);

    // Biome-specific open-water basin so hero pads, ambient floating leaves,
    // Koi fish, and rain impacts always rest on water and never on shore rocks.
    basin = WaterBasin.forBiome(biome);

    // Pad layout and all cosmetic randomness come from the fx stream so the
    // main stream keeps its biome/weather/cycle draw order across versions.
    _fxRandom = Random(sceneSeed ^ 0x5f3759df);
    _noiseSeed = (sceneSeed ^ 0x3c6ef372) & 0x7fffffff;
    // About a quarter of worlds grow one super pad. The basins are too small
    // for one beside the jump lane, so those worlds seed both heroes in the
    // near band and the super pad takes the far shore behind them.
    _wantsSuperPad =
        _fxRandom.nextDouble() < _superPadChance &&
        basin.bottomY - basin.topY >= _superPadBasinHeight;
    pads = _placeHeroPads(nearBand: _wantsSuperPad);
    var ambient = _generateAmbientPads(allowLarge: true);
    if (ambient.length < 4) {
      // The tightest basins keep at least four leaves: retry without the
      // large tier (same seeded stream, so the layout stays reproducible).
      ambient = _generateAmbientPads(allowLarge: false);
    }
    ambientPads = ambient;
    frogs = [
      FrogState(0, pads[0].x, pads[0].y),
      FrogState(1, pads[1].x, pads[1].y),
    ];
    koi = List.generate(4, (i) {
      final y =
          basin.topY +
          18.0 +
          ((i + .4) / 4.2) * (basin.bottomY - basin.topY - 32.0);
      final left = basin.leftX(y) + 28.0;
      final right = basin.rightX(y) - 28.0;
      final startX =
          left +
          ((i + .5) / 4.0) * max(20.0, right - left) +
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

  /// Foreground play time drives the reveal; decorative motion keeps living
  /// after sleep. Short explicit test sessions preserve these proportions.
  double get awakeningSeconds =>
      _durationOverride == null ? elapsed : progress * 180;
  double ambientTime = 0;
  double get ambientMotion => Awakening.water(awakeningSeconds);
  double get foliageMotion => Awakening.foliage(awakeningSeconds);
  double get weatherReveal => Awakening.weather(awakeningSeconds);
  double get wildlifeReveal => Awakening.wildlife(awakeningSeconds);
  double get distantReveal => Awakening.distant(awakeningSeconds);
  double get glowReveal => Awakening.glow(awakeningSeconds);
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

  double _rainAt(double t) => weather == 'mist'
      ? _rainEnvelope.at(t) * RainEnvelope.fogDrizzleGate(mistDensity)
      : _rainEnvelope.at(t);

  /// Current rain intensity in `[0, 1]`: a seeded envelope inside drizzle and
  /// storm sessions (design D1), fine fog drizzle (at most 0.15) when a mist
  /// session's fog is thick, and always zero in clear weather. Updated every
  /// tick; it keeps evolving after sleep.
  double rainIntensity = 0;

  /// Fog density for mist sessions (0 otherwise): thickens toward night.
  double get mistDensity =>
      weather == 'mist' ? RainEnvelope.mistDensityFor(daylight) : 0.0;

  bool get raining =>
      weather == 'drizzle' ||
      weather == 'storm' ||
      (weather == 'mist' && rainIntensity > 0);

  /// Cloud darkening for the scene grade, from the rain intensity.
  double get cloudDarkening =>
      RainEnvelope.cloudFor(rainIntensity) * weatherReveal;

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
  late final int _noiseSeed;
  final List<BugState> bugs = [];

  /// Lily pad dynamics constants (design D6). The landing share and linear
  /// drag are tuned above the first draft so a sideways hop reads as a 3–12 px
  /// slide that settles within 3 s; the rest are as designed.
  static const double _padImpulseShare = .2;
  static const double _padLinearDrag = 1.6;
  static const double _padQuadraticDrag = .06;
  static const double _sectionWallK = 2.5;
  static const double _sectionWallC = 1.5;
  static const double _sectionWallMargin = 3.0;
  static const double _padSeparationK = 6.0;
  static const double _currentScale = 90;
  static const double _currentTimeScale = 25;
  static const double _landingHoming = 6.0;

  /// Every pad roams a small area: ambient placement reserves at least this
  /// much drift room (the final section can only shrink near the far shore).
  static const double _minSection = 4.0;

  /// Passing waves carry floating leaves a little way (Stokes drift), and koi
  /// wakes push pads along their heading: both feed the slow slide.
  static const double _rippleDriftK = 10.0;
  static const double _koiDriftK = 4.0;

  /// A pad sliding faster than this sheds a faint wake ripple, so one landing
  /// can nudge its neighbours in turn.
  static const double _wakeSpeed = 2.5;
  static const double _wakeInterval = .45;

  /// In-plane pad rotation (design D6). Angular drag pulls the spin toward the
  /// water's own rotation (the current's vorticity plus a seeded bias); pushes
  /// act through the slit's area asymmetry with lever `_slitLever × R`.
  static const double _yawDrag = .6;
  static const double _yawCap = 1.2;
  static const double _slitLever = .12;
  static const double _landingSpinShare = .3;
  static const double _impactSpinCap = .6;
  static const double _waterSpinCap = .25;

  /// Ambient size tiers: about one placed leaf in ten is large (21–28 px,
  /// close to hero size), and about one world in four grows a single super
  /// pad (Victoria-style, 42–54 px). Only basins at least 88 px tall have
  /// room for one behind both heroes; the roll is made in every world so the
  /// seeded stream stays aligned.
  static const double _largePadChance = .3;
  static const double _superPadChance = .42;
  static const double _superPadBasinHeight = 88;
  late final bool _wantsSuperPad;

  /// Shared perspective law for pads, frogs and stems: `0.56` at the far shore
  /// and `1.04` at the near rim of the water basin.
  double perspectiveAt(double yPx) => basin.perspectiveAt(yPx);

  /// Sprite scale for a frog: the continuous perspective at its ground point
  /// (not its airborne y), so the frog shrinks smoothly through an away arc
  /// (design D7). The painter snaps the drawn size to whole pixels.
  double frogScale(FrogState frog) => basin.perspectiveAt(frog.groundY * 359);

  /// Recomputes a pad's on-screen radii from its current depth. `radiusY` is
  /// quantised to half pixels so scanline ovals do not flicker while drifting.
  void projectPad(PadState pad) {
    final yPx = pad.y * 359;
    final d = basin.depthAt(yPx);
    pad.radiusX = pad.baseRx * basin.perspectiveAt(yPx);
    pad.radiusY = (pad.radiusX * (.28 + .07 * d) * 2).roundToDouble() / 2;
  }

  /// Positive when the boxes swept by two pads inside their sections cannot
  /// meet on at least one axis (with a small growth margin for depth changes).
  static double _sweptGap(PadState a, PadState b) {
    final dx = (a.x - b.x).abs() * 641;
    final dy = (a.y - b.y).abs() * 359;
    final gapX =
        dx - (a.radiusX + a.sectionRadius) - (b.radiusX + b.sectionRadius) - 2;
    final gapY =
        dy - (a.radiusY + a.sectionRadius) - (b.radiusY + b.sectionRadius) - 2;
    return max(gapX, gapY);
  }

  /// Basin-limited room for a pad to drift in any direction from its home.
  double _basinRoom(PadState pad) {
    final px = pad.x * 641;
    final py = pad.y * 359;
    var room =
        min(
          min(
            px - pad.radiusX - basin.leftX(py),
            basin.rightX(py) - pad.radiusX - px,
          ),
          min(py - pad.radiusY - basin.topY, basin.bottomY - pad.radiusY - py),
        ) -
        4;
    // The basin narrows toward the far shore, so re-check the walls at the
    // highest point the pad could reach.
    final probeY = max(basin.topY, py - max(0.0, room));
    room = min(
      room,
      min(
            px - pad.radiusX - basin.leftX(probeY),
            basin.rightX(probeY) - pad.radiusX - px,
          ) -
          4,
    );
    return max(1.0, room);
  }

  PadState _heroCandidate(
    int index,
    double baseRx,
    double section,
    double py,
    double frac,
    double phase,
    double spinBias,
  ) {
    final s = basin.perspectiveAt(py);
    final rx = baseRx * s;
    // Narrowest walls the section can reach lie toward the far shore.
    final left = max(basin.leftX(py - section), basin.leftX(py + section));
    final right = min(basin.rightX(py - section), basin.rightX(py + section));
    var px = left + frac * (right - left);
    final lo = left + rx + section + 4;
    final hi = right - rx - section - 4;
    px = lo <= hi ? px.clamp(lo, hi) : (left + right) / 2;
    final pad = PadState(
      index: index,
      x: px / 641,
      y: py / 359,
      baseRx: baseRx,
      sectionRadius: section,
      phase: phase,
      spinBias: spinBias,
    );
    projectPad(pad);
    return pad;
  }

  /// Seeded slow spin bias, ±0.01–0.03 rad/s: a full turn in 3.5–10 minutes
  /// on top of whatever the current's shear does.
  double _drawSpinBias() =>
      (_fxRandom.nextBool() ? 1 : -1) * (.01 + _fxRandom.nextDouble() * .02);

  /// Hero pad 0 sits in the left 22–42 % of the basin width and hero 1 in the
  /// right 58–78 %, each at any depth whose section still fits the basin.
  List<PadState> _placeHeroPads({bool nearBand = false}) {
    for (var attempt = 0; attempt < 40; attempt++) {
      final candidates = <PadState>[];
      for (var i = 0; i < 2; i++) {
        final baseRx = 30 + _fxRandom.nextDouble() * 10;
        final section = 10 + _fxRandom.nextDouble() * 4;
        final ryMax = baseRx * 1.04 * .35;
        final minY = max(
          basin.topY + ryMax + section + 4,
          nearBand ? basin.topY + .62 * (basin.bottomY - basin.topY) : 0.0,
        );
        final maxY = basin.bottomY - ryMax - section - 4;
        final py = minY + _fxRandom.nextDouble() * max(1.0, maxY - minY);
        final frac = (i == 0 ? .22 : .58) + _fxRandom.nextDouble() * .20;
        final phase = _fxRandom.nextDouble() * pi * 2;
        final spin = _drawSpinBias();
        candidates.add(
          _heroCandidate(i, baseRx, section, py, frac, phase, spin),
        );
      }
      if (_sweptGap(candidates[0], candidates[1]) >= 0) return candidates;
    }
    // Deterministic fallback for the narrowest basins: a classic near-rim pair.
    final py = basin.topY + .72 * (basin.bottomY - basin.topY);
    return [
      _heroCandidate(0, 32, 10, py, .27, 2.6, .02),
      _heroCandidate(1, 34, 10, py, .73, .5, -.02),
    ];
  }

  /// Positive when [pad]'s swept box lies wholly behind the jump lane: above
  /// the hull of both hero sections, so every left↔right flight passes in
  /// front of it and it can never touch a hero.
  double _laneGap(PadState pad) {
    var t = double.infinity;
    for (final hero in pads) {
      t = min(t, hero.y * 359 - hero.radiusY - hero.sectionRadius);
    }
    final py = pad.y * 359;
    return t - (py + pad.radiusY + pad.sectionRadius + 4);
  }

  /// Four to nine ambient leaves placed clear of the hero sections. Each keeps
  /// the small drift section it was placed with (4–10 px, 2 px for the last
  /// tight fits), checked against every other section, so sections never
  /// overlap and pads inside their sections can never touch. Sizes come in
  /// tiers: most leaves 9.5–21 px, about one placed leaf in ten large
  /// (21–28 px), and in about a quarter of worlds one super pad (42–54 px)
  /// that takes the first slot, sits behind both heroes clear of the jump
  /// lane, and is decorative only.
  List<PadState> _generateAmbientPads({required bool allowLarge}) {
    final result = <PadState>[];
    final count = 5 + _fxRandom.nextInt(5);

    if (_wantsSuperPad) {
      for (var attempt = 0; attempt < 120; attempt++) {
        final allowance = max(_minSection, 8.0 - attempt * .05);
        final yn = .04 + _fxRandom.nextDouble() * .36;
        final py = basin.topY + yn * (basin.bottomY - basin.topY);
        final baseRx = 42 + _fxRandom.nextDouble() * 12;
        final rx = baseRx * basin.perspectiveAt(py);
        final left = basin.leftX(py) + rx + allowance + 4;
        final right = basin.rightX(py) - rx - allowance - 4;
        if (right <= left) continue;
        final px = left + _fxRandom.nextDouble() * (right - left);
        final candidate = PadState(
          index: 2,
          x: px / 641,
          y: py / 359,
          baseRx: baseRx,
          sectionRadius: allowance,
          isAmbient: true,
          isSuper: true,
          phase: _fxRandom.nextDouble() * pi * 2,
          spinBias: _drawSpinBias(),
        );
        projectPad(candidate);
        if (py - candidate.radiusY - allowance < basin.topY + 2 ||
            py + candidate.radiusY + allowance > basin.bottomY - 2 ||
            _basinRoom(candidate) < allowance) {
          continue;
        }
        if (pads.any((hero) => _sweptGap(candidate, hero) < 0)) continue;
        if (_laneGap(candidate) < 0) continue;
        result.add(candidate);
        break;
      }
    }

    for (var i = result.length; i < count; i++) {
      var placed = false;
      final large = _fxRandom.nextDouble() < _largePadChance && allowLarge;
      final phase = _fxRandom.nextDouble() * pi * 2;
      final spin = _drawSpinBias();
      for (var attempt = 0; attempt < 400 && !placed; attempt++) {
        // Ask for generous drift room first, then relax when the basin is
        // tight, and finally fall back to small leaves for the last slots.
        final allowance = attempt < 160
            ? max(_minSection, 10.0 - attempt * .1)
            : 2.0;
        final yn = .06 + _fxRandom.nextDouble() * .88;
        final py = basin.topY + yn * (basin.bottomY - basin.topY);
        final roll = _fxRandom.nextDouble();
        final baseRx = large && attempt < 120
            ? 21 + roll * 7
            : 9.5 + roll * (attempt < 100 ? 11.5 : 3.5);
        final rx = baseRx * basin.perspectiveAt(py);
        final left = basin.leftX(py) + rx + allowance + 4;
        final right = basin.rightX(py) - rx - allowance - 4;
        if (right <= left) continue;
        final px = left + _fxRandom.nextDouble() * (right - left);
        final candidate = PadState(
          index: 2 + i,
          x: px / 641,
          y: py / 359,
          baseRx: baseRx,
          sectionRadius: allowance,
          isAmbient: true,
          hasLotus: i % 3 == 0,
          phase: phase,
          spinBias: spin,
        );
        projectPad(candidate);
        if (py - candidate.radiusY - allowance < basin.topY + 2 ||
            py + candidate.radiusY + allowance > basin.bottomY - 2 ||
            _basinRoom(candidate) < allowance) {
          continue;
        }
        if (pads.any((hero) => _sweptGap(candidate, hero) < 0)) continue;
        if (result.any((other) => _sweptGap(candidate, other) < 0)) continue;
        result.add(candidate);
        placed = true;
      }
    }

    for (final pad in result) {
      // Only the narrowing far shore can still trim a section.
      pad.sectionRadius = max(1.0, min(pad.sectionRadius, _basinRoom(pad)));
    }
    result.sort((a, b) => a.y.compareTo(b.y));
    return result;
  }

  // -- Slow pad motion -------------------------------------------------------

  /// Smooth seeded lattice value in [0, 1]; a pure function of its arguments
  /// (no Random), so partitions of the update timeline agree exactly. Lattice
  /// indices are offset to stay non-negative, and every intermediate product
  /// stays below 2^53 for the web target.
  double _lattice(int ix, int iy, int it) {
    var h =
        ((ix + 64) * 73856093) ^
        ((iy + 64) * 19349663) ^
        ((it + 64) * 83492791) ^
        _noiseSeed;
    h &= 0x7fffffff;
    h = ((h ^ (h >> 15)) * 0x2c1b3) & 0x7fffffff;
    h = (h ^ (h >> 12)) & 0x7fffffff;
    return (h & 0xffff) / 65535.0;
  }

  static double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  double _valueNoise(double x, double y, double z) {
    final x0 = x.floor(), y0 = y.floor(), z0 = z.floor();
    final fx = _fade(x - x0), fy = _fade(y - y0), fz = _fade(z - z0);
    double lerp(double a, double b, double t) => a + (b - a) * t;
    final c00 = lerp(_lattice(x0, y0, z0), _lattice(x0 + 1, y0, z0), fx);
    final c10 = lerp(
      _lattice(x0, y0 + 1, z0),
      _lattice(x0 + 1, y0 + 1, z0),
      fx,
    );
    final c01 = lerp(
      _lattice(x0, y0, z0 + 1),
      _lattice(x0 + 1, y0, z0 + 1),
      fx,
    );
    final c11 = lerp(
      _lattice(x0, y0 + 1, z0 + 1),
      _lattice(x0 + 1, y0 + 1, z0 + 1),
      fx,
    );
    return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz);
  }

  /// Water current at a pad in px/s: the curl of seeded value noise (90 px,
  /// 25 s), 0.8–2.0 px/s (hero pads × 0.6), plus the wind.
  (double, double) currentAt(PadState pad) =>
      _currentAtPx(pad.x * 641, pad.y * 359, pad.isAmbient);

  /// Vorticity of the current across a pad (rad/s, positive clockwise on
  /// screen): the shear that turns a free-floating leaf. Sampled one pad
  /// radius out on each side so it reflects the flow over the leaf, not a
  /// point derivative; the wind term is uniform and cancels.
  double vorticityAt(PadState pad) {
    final x = pad.x * 641;
    final y = pad.y * 359;
    final e = max(6.0, pad.radiusX * .7);
    final (_, cyE) = _currentAtPx(x + e, y, pad.isAmbient);
    final (_, cyW) = _currentAtPx(x - e, y, pad.isAmbient);
    final (cxS, _) = _currentAtPx(x, y + e, pad.isAmbient);
    final (cxN, _) = _currentAtPx(x, y - e, pad.isAmbient);
    return ((cyE - cyW) - (cxS - cxN)) / (2 * e);
  }

  (double, double) _currentAtPx(double xPx, double yPx, bool ambient) {
    final px = xPx / _currentScale;
    final py = yPx / _currentScale;
    final pt = time / _currentTimeScale;
    const eps = 2 / _currentScale;
    final gx =
        (_valueNoise(px + eps, py, pt) - _valueNoise(px - eps, py, pt)) /
        (2 * eps);
    final gy =
        (_valueNoise(px, py + eps, pt) - _valueNoise(px, py - eps, pt)) /
        (2 * eps);
    // Curl of the scalar potential: perpendicular to its gradient.
    var cx = gy;
    var cy = -gx;
    final mag = sqrt(cx * cx + cy * cy);
    if (mag < 1e-9) {
      cx = 1;
      cy = 0;
    } else {
      cx /= mag;
      cy /= mag;
    }
    final speed =
        (.8 + 1.2 * (mag / 1.1).clamp(0.0, 1.0)) * (ambient ? 1.0 : .6);
    return (cx * speed * ambientMotion + wind * 3, cy * speed * ambientMotion);
  }

  /// Spins a pad from a push through the water. The slit removes leaf area on
  /// one side, so the centre of pressure sits `_slitLever × R` opposite the
  /// slit and a push has a lever: `α = (e × F) / (R² / 2)`. [ax]/[ay] is the
  /// screen-plane acceleration (or velocity change when [dt] is 1) given to
  /// the slide; its y part is unforeshortened into the pad plane.
  void _spinFromPush(PadState pad, double ax, double ay, double dt) {
    final theta = pad.slitAngle;
    final planeY = ay * pad.radiusX / max(1.0, pad.radiusY);
    final cross = ax * sin(theta) - planeY * cos(theta);
    pad.yawVelocity += 2 * _slitLever * cross / max(1.0, pad.radiusX) * dt;
  }

  /// Transfers a share of a frog's screen-plane momentum to a pad: 70 % to the
  /// slow slide, 30 % to the fast drift/float springs.
  void _padImpulse(PadState pad, double vxPx, double vyPx, double share) {
    final mass = 1.6 + .02 * pad.radiusX;
    final jx = share * _padImpulseShare * vxPx / mass;
    final jy = share * _padImpulseShare * vyPx / mass;
    pad.vx += .7 * jx;
    pad.vy += .7 * jy;
    pad.driftVelocity += .3 * jx;
    pad.floatVelocity += .3 * jy;
  }

  /// Angular impulse from a frog leaving or arriving at a perch offset
  /// ([offsetX], [offsetY] normalised by the pad radii) with screen-plane
  /// velocity [vxPx]/[vyPx]: `Δω = share · (r × J) / (R² / 2)` plus the slit
  /// lever on the same impulse. [share] is negative for a takeoff.
  void _spinFromLever(
    PadState pad,
    double offsetX,
    double offsetY,
    double vxPx,
    double vyPx,
    double share,
  ) {
    final mass = 1.6 + .02 * pad.radiusX;
    final jx = _padImpulseShare * vxPx / mass;
    final jy = _padImpulseShare * vyPx / mass;
    final r = max(1.0, pad.radiusX);
    final planeJy = jy * r / max(1.0, pad.radiusY);
    final torque = offsetX * r * planeJy - offsetY * r * jx;
    final before = pad.yawVelocity;
    pad.yawVelocity += share * torque / (r * r / 2);
    _spinFromPush(pad, share * jx, share * jy, 1);
    // One hop turns a pad by a gentle amount, never a spin.
    final kick = (pad.yawVelocity - before).clamp(
      -_impactSpinCap,
      _impactSpinCap,
    );
    pad.yawVelocity = before + kick;
  }

  /// A sliding pad pushes a faint bow wave ahead of it; the ripple then
  /// carries its neighbours a little (see the ripple drift above).
  void _padWake(PadState pad, double dt) {
    pad.wakeClock = max(0.0, pad.wakeClock - dt);
    final speed = sqrt(pad.vx * pad.vx + pad.vy * pad.vy);
    if (speed < _wakeSpeed || pad.wakeClock > 0) return;
    pad.wakeClock = _wakeInterval;
    final ux = pad.vx / speed;
    final uy = pad.vy / speed;
    _emitRipple(
      x: pad.x * 641 + pad.driftX + ux * pad.radiusX * .8,
      y: pad.y * 359 + 2 + uy * pad.radiusY * .8,
      initialRadius: pad.radiusX * .5,
      maxRadius: pad.radiusX * 1.9,
      duration: 1.1,
      intensity: min(.35, .05 * speed),
      biasX: ux * 4,
    );
  }

  void _slidePad(PadState pad, double dt, List<PadState> allPads) {
    // `vx, vy` is the slide relative to the water, which itself moves with the
    // current, so a settled pad drifts with the current at zero slide speed.
    final (cx, cy) = currentAt(pad);
    final speed = sqrt(pad.vx * pad.vx + pad.vy * pad.vy);
    final damp = 1 / (1 + dt * (_padLinearDrag + _padQuadraticDrag * speed));
    pad.vx *= damp;
    pad.vy *= damp;

    // Soft section wall: a 3 px over-damped band just inside the section
    // radius, so ordinary slides finish on free water and only the current can
    // lean a pad against its wall.
    var px = pad.x * 641;
    var py = pad.y * 359;
    final hx = pad.homeX * 641;
    final hy = pad.homeY * 359;
    var dx = px - hx;
    var dy = py - hy;
    var dist = sqrt(dx * dx + dy * dy);
    final inner = max(
      pad.sectionRadius * .6,
      pad.sectionRadius - _sectionWallMargin,
    );
    if (dist > inner && dist > 1e-9) {
      final nx = dx / dist;
      final ny = dy / dist;
      final outward = max(0.0, (pad.vx + cx) * nx + (pad.vy + cy) * ny);
      final a = -_sectionWallK * (dist - inner) - _sectionWallC * outward;
      pad.vx += a * nx * dt;
      pad.vy += a * ny * dt;
    }

    // Mass-weighted separation penalty when two bodies would touch.
    final mass = 1.6 + .02 * pad.radiusX;
    for (final other in allPads) {
      if (identical(other, pad)) continue;
      final ox = (px - other.x * 641);
      final oy = (py - other.y * 359);
      final sumX = pad.radiusX + other.radiusX + 2;
      final sumY = pad.radiusY + other.radiusY + 2;
      if (ox.abs() >= sumX || oy.abs() >= sumY) continue;
      final pen = min(sumX - ox.abs(), sumY - oy.abs());
      final len = max(1e-6, sqrt(ox * ox + oy * oy));
      final otherMass = 1.6 + .02 * other.radiusX;
      final weight = otherMass / (mass + otherMass);
      pad.vx += _padSeparationK * pen * weight * (ox / len) * dt;
      pad.vy += _padSeparationK * pen * weight * (oy / len) * dt;
    }

    px += (pad.vx + cx) * dt;
    py += (pad.vy + cy) * dt;

    // Basin clamp keeps every pad on open water.
    final minY = basin.topY + pad.radiusY + 2;
    final maxY = basin.bottomY - pad.radiusY - 2;
    if (py < minY) {
      py = minY;
      pad.vy = max(-cy, pad.vy);
    } else if (py > maxY) {
      py = maxY;
      pad.vy = min(-cy, pad.vy);
    }
    final minX = basin.leftX(py) + pad.radiusX + 4;
    final maxX = basin.rightX(py) - pad.radiusX - 4;
    if (px < minX) {
      px = minX;
      pad.vx = max(-cx, pad.vx);
    } else if (px > maxX) {
      px = maxX;
      pad.vx = min(-cx, pad.vx);
    }

    // Hard section clamp as a last resort. It runs after the basin clamp: the
    // home is basin-valid by construction, so pulling toward it stays valid.
    dx = px - hx;
    dy = py - hy;
    dist = sqrt(dx * dx + dy * dy);
    if (dist > pad.sectionRadius) {
      final nx = dx / dist;
      final ny = dy / dist;
      px = hx + nx * pad.sectionRadius;
      py = hy + ny * pad.sectionRadius;
      final outward = (pad.vx + cx) * nx + (pad.vy + cy) * ny;
      if (outward > 0) {
        pad.vx -= outward * nx;
        pad.vy -= outward * ny;
      }
    }

    pad.x = px / 641;
    pad.y = py / 359;
    projectPad(pad);

    // In-plane rotation: skin friction drags the spin toward the water's own
    // rotation (current shear plus the seeded bias), so a pad keeps turning
    // slowly for as long as the pond does; impacts add on top and decay at
    // the same rate. The angle wraps so it stays bounded for ever.
    final waterSpin = (vorticityAt(pad) + pad.spinBias * ambientMotion).clamp(
      -_waterSpinCap,
      _waterSpinCap,
    );
    pad.yawVelocity +=
        (waterSpin - pad.yawVelocity) * (1 - exp(-_yawDrag * dt));
    pad.yawVelocity = pad.yawVelocity.clamp(-_yawCap, _yawCap);
    pad.yaw += pad.yawVelocity * dt;
    if (pad.yaw > pi) {
      pad.yaw -= 2 * pi;
    } else if (pad.yaw <= -pi) {
      pad.yaw += 2 * pi;
    }
  }

  /// Perched and sleeping frogs ride their pads; the perch is pad-relative.
  void _rideFrogs() {
    for (final frog in frogs) {
      if (frog.airborne || frog.swimming) continue;
      final pad = pads[frog.leafIndex];
      frog.x = pad.x + frog.perchDx;
      frog.y = pad.y + frog.perchDy;
    }
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
    rainIntensity = _rainAt(time);
    if (started && !sleeping && !_settling) {
      elapsed += dt;
      engagement *= exp(-dt / 18);
      if (_durationOverride == null) {
        duration += (240 + 60 * engagement - duration) * (1 - exp(-dt / 12));
        duration = duration.clamp(240.0, 300.0);
      }
      final fraction = (elapsed / duration).clamp(0.0, 1.0);
      progress = max(progress, fraction * fraction * (3 - 2 * fraction));
      if (elapsed + 1e-9 >= duration) {
        progress = 1;
        _settling = true;
        cancelPress();
      }
    }
    richness = Awakening.reveal(awakeningSeconds, 0, 180);
    ambientTime += dt * ambientMotion;
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
  double _leafY(int leaf) => pads[leaf].y;

  /// Pad-relative perch offset (normalised x). A frog visiting the other's
  /// leaf sits slightly toward its home side. Full foot support takes
  /// precedence over separating silhouettes when both frogs share a pad.
  double perchOffsetX(int frogIndex, int leaf) {
    if (leaf == frogIndex) return 0;
    final side = frogIndex == 0 ? -1.0 : 1.0;
    return side *
        min(
          3.0,
          max(
            0.0,
            pads[leaf].radiusX -
                17 * basin.perspectiveAt(pads[leaf].y * 359) -
                3,
          ),
        ) /
        641;
  }

  // Flights are serialized; the vertical lane additionally separates passing
  // silhouettes.
  double _perchX(FrogState frog, int leaf) =>
      pads[leaf].x + perchOffsetX(frog.index, leaf);

  void _launch(FrogState frog, String action, {bool returning = false}) {
    final sourcePad = pads[frog.leafIndex];
    frog.action = action;
    frog._fromX = frog.x;
    frog._fromY = frog.y;
    frog._targetLeaf = returning ? frog.index : 1 - frog.leafIndex;
    final targetPad = pads[frog._targetLeaf];
    // Choose the landing point before flight, including homeward flights.
    // Nearly vertical variation keeps both perches separated on the same pad.
    final radius = .0005 + random.nextDouble() * .0015;
    final angle = pi / 2 + (random.nextDouble() - .5) * .4;
    final sign = random.nextBool() ? 1 : -1;
    final ySign = frogs[1 - frog.index].leafIndex == frog._targetLeaf
        ? (frog.index == 0 ? -1 : 1)
        : sign;
    frog._perchTargetDx =
        perchOffsetX(frog.index, frog._targetLeaf) + cos(angle) * radius * sign;
    frog._perchTargetDy = sin(angle) * radius * ySign;
    // Fit the widest perched foot span inside the pad ellipse, with margin.
    final footHalf = 17 * basin.perspectiveAt(targetPad.y * 359);
    final dyPx = frog._perchTargetDy * 359;
    final span =
        targetPad.radiusX *
        sqrt(max(0.0, 1 - pow(dyPx / max(1.0, targetPad.radiusY - 2), 2)));
    final safeX = max(0.0, span - footHalf - 2);
    frog._perchTargetDx =
        (frog._perchTargetDx * 641).clamp(-safeX, safeX) / 641;
    frog._toX = targetPad.x + frog._perchTargetDx;
    frog._toY = targetPad.y + frog._perchTargetDy;
    frog._duration = _flightDuration(action);
    frog._returning = returning;
    frog.jumpPhase = 0;
    frog.airborne = true;
    frog.landingTimer = 0;
    frog.swallowTimer = 0;
    frog.caughtInFlight = 0;
    frog.facing = frog._toX >= frog._fromX ? 1.0 : -1.0;
    frog.view = FrogState.viewFor(
      (frog._toX - frog._fromX) * 641,
      (frog._toY - frog._fromY) * 359,
    );
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
    final launchVx = (frog._toX - frog._fromX) * 641 / frog._duration;
    final launchVy = (frog._toY - frog._fromY) * 359 / frog._duration;
    _padImpulse(sourcePad, launchVx, launchVy, -.8);
    _spinFromLever(
      sourcePad,
      ((frog._fromX - sourcePad.x) * 641 / sourcePad.radiusX).clamp(-1.0, 1.0),
      ((frog._fromY - sourcePad.y) * 359 / sourcePad.radiusY).clamp(-1.0, 1.0),
      launchVx,
      launchVy,
      -.8 * _landingSpinShare,
    );
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
    if (frog.airborne || frog.swimming) {
      // The landing point homes toward the moving target pad, which keeps the
      // parabola continuous instead of snapping at touchdown.
      final target = pads[frog._targetLeaf];
      final k = 1 - exp(-_landingHoming * dt);
      frog._toX += (target.x + frog._perchTargetDx - frog._toX) * k;
      frog._toY += (target.y + frog._perchTargetDy - frog._toY) * k;
    }
    if (frog.swimming) {
      frog._swimAge += dt;
      final p = (frog._swimAge / 1.6).clamp(0.0, 1.0);
      final s = p * p * (3 - 2 * p);
      frog.x = frog._splashX + (frog._toX - frog._splashX) * s;
      frog.y = frog._toY + .065 * (1 - s) + sin(p * pi * 4) * .006 * (1 - p);
      frog.facing = frog._toX >= frog._splashX ? 1.0 : -1.0;
      if (p >= 1) {
        frog.swimming = false;
        _land(frog, (frog._toX - frog._splashX) * 641 / 1.6, 0);
      }
      return;
    }
    if (!frog.airborne) return;
    // Pure, single-impulse ballistic parabola from liftoff (p=0) to landing
    // (p=1). The arc height follows the perspective of the ground point so a
    // far jump reads smaller without changing its duration.
    frog.jumpPhase = min(1, frog.jumpPhase + dt / frog._duration);
    final p = frog.jumpPhase;
    frog.x = frog._fromX + (frog._toX - frog._fromX) * p;
    final groundY = frog._fromY + (frog._toY - frog._fromY) * p;
    frog.y =
        groundY -
        sin(pi * p) *
            (_height(frog.action) + frog.index * .018) *
            basin.perspectiveAt(groundY * 359);
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
        _land(
          frog,
          (frog._toX - frog._fromX) * 641 / frog._duration,
          (frog._toY - frog._fromY) * 359 / frog._duration,
        );
      }
    }
  }

  /// Settles the frog onto its pad-relative perch. [vxPx]/[vyPx] is the
  /// screen-plane approach velocity whose momentum shoves the pad.
  void _land(FrogState frog, double vxPx, double vyPx) {
    frog.leafIndex = frog._targetLeaf;
    final pad = pads[frog.leafIndex];
    frog.perchDx = frog._perchTargetDx;
    frog.perchDy = frog._perchTargetDy;
    frog.x = pad.x + frog.perchDx;
    frog.y = pad.y + frog.perchDy;
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

    // Momentum slide plus a spin from the off-centre impact: the perch's lever
    // in the pad plane crossed with the transferred impulse, over the disc's
    // moment of inertia (R²/2 per unit mass), then the slit asymmetry.
    _padImpulse(pad, vxPx, vyPx, 1);
    _spinFromLever(pad, offsetX, offsetY, vxPx, vyPx, _landingSpinShare);

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
    final target = 1 - frog.leafIndex;
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
            targetX: _perchX(frog, target),
            targetY: _leafY(target),
            scaleFrom: basin.perspectiveAt(frog.y * 359),
            scaleTo: basin.perspectiveAt(_leafY(target) * 359),
          );
    var best = double.negativeInfinity;
    var bestReach = 0.0;
    var chosen = 'low';
    for (final action in ['tap', 'low', 'high']) {
      final flight = _flightDuration(action);
      var value = action == 'low' ? .025 : 0.0;
      for (final bug in bugs) {
        if (!bug.alive || bug.opacity < .25) continue;
        var closest = 1.0;
        for (var i = 1; i <= 10; i++) {
          final p = i / 12;
          final x = frog.x + (_perchX(frog, target) - frog.x) * p;
          final groundY = frog.y + (_leafY(target) - frog.y) * p;
          final y =
              groundY -
              sin(pi * p) *
                  (_height(action) + .018) *
                  basin.perspectiveAt(groundY * 359) -
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
      final reach = value - (action == 'low' ? .025 : 0.0);
      bestReach = max(bestReach, reach);
      value -= wind.abs() * _height(action) * .08;
      if (action == prior) value += .008;
      if (value > best) {
        best = value;
        chosen = action;
      }
    }
    // Patience: with no insect in reach of any arc, JEV waits for a better
    // chance instead of hopping blindly, but never longer than its patience.
    if (bestReach < _jevReachThreshold && _jevWaited < _jevPatience) {
      _jevWaited += .25;
      return;
    }
    _jevWaited = 0;
    _launch(frog, chosen);
  }

  /// JEV waits up to this long (s) for an insect to come within reach.
  static const double _jevPatience = 4.0;
  static const double _jevReachThreshold = .01;
  double _jevWaited = 0;

  static double _distance(double x, double y, double bx, double by) =>
      sqrt((x - bx) * (x - bx) + (y - by) * (y - by));

  void _updateWind(double dt) {
    if (!started) {
      wind = 0;
      windTell = 0;
      return;
    }
    final reveal = Awakening.breeze(awakeningSeconds);
    final baseline = sin(ambientTime * .13) * .06 * reveal;
    if (_gustAge < 0) {
      _gustClock -= dt;
      wind = baseline;
      windTell = 0;
      if (_gustClock <= 0) {
        _gustAge = 0;
        _gustDirection = random.nextBool() ? 1 : -1;
      }
      return;
    }
    _gustAge += dt;
    // A forecast and a broad gust overlap smoothly. Neither value jumps at
    // the handoff, and the ambient baseline continues between gusts/sleep.
    windTell =
        Awakening.reveal(_gustAge, 0, 2) *
        (1 - Awakening.reveal(_gustAge, 2, 5)) *
        reveal;
    final gust =
        Awakening.reveal(_gustAge, 1, 6) *
        (1 - Awakening.reveal(_gustAge, 8, 12));
    wind = baseline + _gustDirection * .24 * gust * reveal;
    if (_gustAge >= 12) {
      _gustAge = -1;
      _gustClock = (weather == 'storm' ? 10 : 16) + random.nextDouble() * 20;
      wind = baseline;
      windTell = 0;
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

  /// Compact presence of the voiced species for the ambience, for example
  /// `cricket:3,bee:1`. Only visible insects (opacity ≥ 0.25) count, so a
  /// voice fades out with the last singer rather than with its species rule.
  String get speciesPresence {
    final counts = <String, int>{};
    for (final bug in bugs) {
      if (!bug.alive || bug.opacity < .25) continue;
      final voice = InsectSpecies.byName[bug.species]?.voice;
      if (voice == null) continue;
      counts[voice] = (counts[voice] ?? 0) + 1;
    }
    return [
      for (final name in InsectSpecies.voicedNames)
        if (counts.containsKey(name)) '$name:${counts[name]}',
    ].join(',');
  }

  void _spawnBug() {
    final species = availableSpecies;
    // Every biome keeps a resident species in all weathers, so this is only a
    // guard; skipping the spawn draws nothing from the main stream.
    if (species.isEmpty) return;
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
          y: info.spawnInBand
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
          sin(bug._heading) * speed * info.vertical + sin(bug.phase) * info.bob;
      targetX += max(0, .14 - bug.x) * .8 - max(0, bug.x - .86) * .8;
      targetY += max(0, bandLow - bug.y) * .8 - max(0, bug.y - bandHigh) * .8;
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
          pad.tiltVelocity += (dx >= 0 ? 1.0 : -1.0) * 9.5 * waveStrength * dt;
          pad.driftVelocity += (dx / dist) * 14.0 * waveStrength * dt;
          if (pad.isAmbient) {
            pad.floatVelocity += (dy / dist) * 4.5 * waveStrength * dt;
          }
          // Stokes drift: the crest leaves the pad slightly further out. A
          // pad is not carried by waves it made itself (centre on its body).
          final ox = (r.x - padPxX) / pad.radiusX;
          final oy = (r.y - padPxY) / max(1.0, pad.radiusY);
          if (ox * ox + oy * oy > 1.2) {
            final ax = (dx / dist) * _rippleDriftK * waveStrength;
            final ay = (dy / dist) * .34 * _rippleDriftK * waveStrength;
            pad.vx += ax * dt;
            pad.vy += ay * dt;
            _spinFromPush(pad, ax, ay, dt);
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
              (pad.isAmbient ? 1.4 : .7) *
              wildlifeReveal;
          pad.driftVelocity += cos(k.heading) * 18.0 * wake * dt;
          if (pad.isAmbient) {
            pad.floatVelocity += sin(k.heading) * 6.5 * wake * dt;
          }
          pad.tiltVelocity += cos(k.heading) * 7.5 * wake * dt;
          pad.dipVelocity += 6.0 * wake * dt;
          final ax = cos(k.heading) * _koiDriftK * wake;
          final ay = sin(k.heading) * .5 * _koiDriftK * wake;
          pad.vx += ax * dt;
          pad.vy += ay * dt;
          _spinFromPush(pad, ax, ay, dt);
        }
      }

      // 3. Ambient Pond Current Drift for floating leaves
      if (pad.isAmbient) {
        pad.driftVelocity +=
            (sin(ambientTime * .18 + pad.phase) * 3.8 * ambientMotion +
                wind * 5.0) *
            dt;
        pad.floatVelocity +=
            cos(ambientTime * .15 + pad.phase) * 1.8 * ambientMotion * dt;
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

    // 5. Slow slide, current and section walls on top of the fast springs.
    //    Every pad keeps roaming its small section, during sleep too: the
    //    sleeping frogs ride their leaves while the pond lives on.
    for (final pad in allPads) {
      _slidePad(pad, dt, allPads);
      _padWake(pad, dt);
    }
    _rideFrogs();
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
    if (!raining || weatherReveal <= 0) {
      raindrops.clear();
      return;
    }
    // Everything scales on the envelope: ~17 drops at 0.3, 42 at a downpour.
    // Streaks beyond intensity 0.7 are drawn by the renderer only, so the
    // physical drop count and the 34-ripple cap stay bounded.
    final intensity = rainIntensity;
    final targetCount = ((6 + 36 * intensity) * weatherReveal).ceil();
    final spawnRate = (20.0 + 90.0 * intensity) * weatherReveal;
    final toSpawn =
        (spawnRate * dt + (_fxRandom.nextDouble() < .4 * weatherReveal ? 1 : 0))
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
    dt *= .005 + .995 * wildlifeReveal;
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

/// Per-biome trapezoidal open-water basin in logical `641 × 359` coordinates.
/// Hero pads are placed inside it from the scene seed.
class WaterBasin {
  const WaterBasin({
    required this.topY,
    required this.bottomY,
    required this.topLeftX,
    required this.topRightX,
    required this.bottomLeftX,
    required this.bottomRightX,
  });

  final double topY;
  final double bottomY;
  final double topLeftX;
  final double topRightX;
  final double bottomLeftX;
  final double bottomRightX;

  /// Normalised depth in the basin: 0 at the far shore, 1 at the near rim.
  double depthAt(double yPx) =>
      ((yPx - topY) / max(1.0, bottomY - topY)).clamp(0.0, 1.0);

  /// Perspective scale shared by pads, frogs and stems (design D6).
  double perspectiveAt(double yPx) => .56 + .48 * depthAt(yPx);

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
    ),
    'sanctuary' || 'jade_sanctuary' => const WaterBasin(
      topY: 244,
      bottomY: 328,
      topLeftX: 246,
      topRightX: 434,
      bottomLeftX: 192,
      bottomRightX: 456,
    ),
    'alpine' => const WaterBasin(
      topY: 238,
      bottomY: 330,
      topLeftX: 224,
      topRightX: 428,
      bottomLeftX: 176,
      bottomRightX: 462,
    ),
    'maple' || 'autumn_mist' => const WaterBasin(
      topY: 228,
      bottomY: 326,
      topLeftX: 206,
      topRightX: 436,
      bottomLeftX: 184,
      bottomRightX: 454,
    ),
    'cypress' => const WaterBasin(
      topY: 242,
      bottomY: 328,
      topLeftX: 218,
      topRightX: 420,
      bottomLeftX: 182,
      bottomRightX: 450,
    ),
    'blossom' || 'lotus' => const WaterBasin(
      topY: 236,
      bottomY: 328,
      topLeftX: 206,
      topRightX: 440,
      bottomLeftX: 174,
      bottomRightX: 466,
    ),
    _ => const WaterBasin(
      topY: 228,
      bottomY: 328,
      topLeftX: 210,
      topRightX: 432,
      bottomLeftX: 186,
      bottomRightX: 452,
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

  /// Pad-relative perch (normalised offsets from the pad centre). The frog
  /// rides its pad through these while perched or sleeping.
  double perchDx = 0, perchDy = 0;

  /// Camera-relative view of the current or last flight: `side`, `away`
  /// (back view, moving up-screen) or `toward` (front view, moving down-screen).
  String view = 'side';
  double _fromX = 0, _fromY = 0, _toX = 0, _toY = 0;
  double _perchTargetDx = 0, _perchTargetDy = 0;
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
  double get groundY => airborne ? (_fromY + (_toY - _fromY) * jumpPhase) : y;

  /// Vertical height above the pond/pad surface (`0.0` when perched or swimming).
  double get altitude => airborne ? max(0.0, groundY - y) : 0.0;

  /// View bucket for a screen-plane flight vector in pixels (design D7). Depth
  /// is weighted 2.5× so modest up/down-screen hops already turn the frog.
  static String viewFor(double dxPx, double dyPx) {
    final theta = atan2(dyPx * 2.5, dxPx).abs() * 180 / pi;
    if (theta < 35 || theta > 145) return 'side';
    return dyPx < 0 ? 'away' : 'toward';
  }

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

  /// Maps a side pose to its away/toward variant for the flight's [view]. Side
  /// flights and every perched state except the back-view touchdown return
  /// [pose] unchanged, so the existing 10 states keep working.
  String viewPose(String pose) {
    if (view == 'away') {
      return switch (pose) {
        'launching' => 'away_launch',
        'ascending' => 'away_ascend',
        'falling' || 'chomping' => 'away_fall',
        'landing' => 'back_idle',
        _ => pose,
      };
    }
    if (view == 'toward') {
      return switch (pose) {
        'launching' => 'toward_launch',
        'ascending' => 'toward_ascend',
        'falling' => 'toward_fall',
        'chomping' => 'toward_chomp',
        _ => pose,
      };
    }
    return pose;
  }
}

class PadState {
  PadState({
    required this.index,
    required this.x,
    required this.y,
    required this.baseRx,
    required this.sectionRadius,
    this.isAmbient = false,
    this.isSuper = false,
    this.hasLotus = false,
    this.phase = 0,
    this.spinBias = 0,
  }) : homeX = x,
       homeY = y,
       radiusX = baseRx,
       radiusY = baseRx * .3;
  final int index;

  /// Slow state: the pad's centre (normalised), its seeded home and the
  /// radius of the circular section (px) it may drift inside.
  double x, y;
  final double homeX, homeY;
  double sectionRadius;

  /// Slide velocity in px/s relative to the water (the current is added on
  /// top) and in-plane rotation: [yaw] in (−π, π] turns the slit, veins and
  /// lotus anchor around the projected ellipse; [yawVelocity] in rad/s.
  double vx = 0, vy = 0;
  double yaw = 0, yawVelocity = 0;

  /// Seeded slow rotation of the water under this pad (rad/s).
  final double spinBias;

  /// A Victoria-style super pad: decorative, upturned rim, never a perch.
  final bool isSuper;

  /// Pad-plane angle of the radial slit (seeded [phase] plus [yaw]). Screen
  /// direction is `(cos θ · radiusX, sin θ · radiusY)`.
  double get slitAngle => phase + yaw;

  /// Seconds until this pad may shed another wake ripple.
  double wakeClock = 0;

  /// Unprojected radius; [radiusX]/[radiusY] follow the perspective each tick.
  final double baseRx;
  double radiusX, radiusY;
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
