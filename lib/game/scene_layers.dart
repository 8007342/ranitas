import 'dart:math' as math;
import 'dart:ui' as ui;

import 'foliage.dart';
import 'pond_model.dart';
import 'scene_grade.dart';

/// Where a layer sits in the renderer's tier order (design D5).
enum LayerSlot {
  /// After the backdrop and palette cycles, before the water tiers.
  farBank,

  /// After the water surface, before the lily pads.
  midBank,

  /// After frogs and insects, anchored to the top edge.
  canopy,

  /// The corner foreground, after weather.
  nearCorner,

  /// Petals, leaves, drips and spores shed by the canopy.
  particles,
}

enum CanopyKind {
  willow,
  moss,
  blossom,
  wisteria,
  momiji,
  bamboo,
  stalactite,
  crystal,
  pine,
}

enum EmitterKind { petals, leaves, drips, spores }

/// One layer of a biome's stack. [depth] runs 0 (far) to 1 (near) and scales
/// sway amplitude, wind shear and breathing parallax.
class SceneLayer {
  const SceneLayer({
    required this.slot,
    this.depth = .5,
    this.windResponse = 1,
    this.revealAt = .2,
    this.canopy,
    this.emitter,
    this.reeds = false,
    this.lantern = false,
  });

  final LayerSlot slot;
  final double depth;
  final double windResponse;

  /// Richness at which the layer starts to fade in.
  final double revealAt;
  final CanopyKind? canopy;
  final EmitterKind? emitter;

  /// Procedural mid-bank reeds at the far shore corners.
  final bool reeds;

  /// The bamboo canopy hangs a paper lantern on the right.
  final bool lantern;
}

/// The per-biome stack table and the clear-lane rule.
class SceneLayers {
  SceneLayers._();

  /// Central 50 % of the width must stay clear below 30 % of the height.
  static const double laneLeft = 641 * .25;
  static const double laneRight = 641 * .75;
  static const double laneTop = 359 * .30;

  static const _near = SceneLayer(
    slot: LayerSlot.nearCorner,
    depth: 1,
    revealAt: .12,
  );

  static List<SceneLayer> stackFor(String biome) => switch (biome) {
    'willow' => const [
      SceneLayer(slot: LayerSlot.midBank, depth: .35, reeds: true),
      SceneLayer(slot: LayerSlot.canopy, depth: .8, canopy: CanopyKind.willow),
      _near,
    ],
    'cypress' || 'firefly' => const [
      SceneLayer(slot: LayerSlot.midBank, depth: .35, reeds: true),
      SceneLayer(
        slot: LayerSlot.canopy,
        depth: .8,
        windResponse: .7,
        canopy: CanopyKind.moss,
      ),
      _near,
    ],
    'blossom' => const [
      SceneLayer(slot: LayerSlot.canopy, depth: .8, canopy: CanopyKind.blossom),
      SceneLayer(
        slot: LayerSlot.particles,
        depth: .7,
        emitter: EmitterKind.petals,
      ),
      _near,
    ],
    'lotus' => const [
      SceneLayer(
        slot: LayerSlot.canopy,
        depth: .8,
        canopy: CanopyKind.wisteria,
      ),
      SceneLayer(
        slot: LayerSlot.particles,
        depth: .7,
        emitter: EmitterKind.petals,
      ),
      _near,
    ],
    'maple' || 'autumn_mist' => const [
      SceneLayer(slot: LayerSlot.canopy, depth: .8, canopy: CanopyKind.momiji),
      SceneLayer(
        slot: LayerSlot.particles,
        depth: .7,
        emitter: EmitterKind.leaves,
      ),
      _near,
    ],
    'sanctuary' || 'jade_sanctuary' => const [
      SceneLayer(
        slot: LayerSlot.canopy,
        depth: .8,
        windResponse: .6,
        canopy: CanopyKind.bamboo,
        lantern: true,
      ),
      _near,
    ],
    'grotto' || 'crystal_grotto' => [
      SceneLayer(
        slot: LayerSlot.canopy,
        depth: .8,
        windResponse: .3,
        canopy: biome == 'grotto' ? CanopyKind.stalactite : CanopyKind.crystal,
      ),
      const SceneLayer(
        slot: LayerSlot.particles,
        depth: .8,
        emitter: EmitterKind.drips,
      ),
      const SceneLayer(
        slot: LayerSlot.particles,
        depth: .5,
        emitter: EmitterKind.spores,
      ),
      _near,
    ],
    'alpine' => const [
      SceneLayer(
        slot: LayerSlot.canopy,
        depth: .8,
        windResponse: .5,
        canopy: CanopyKind.pine,
      ),
      _near,
    ],
    _ => const [_near],
  };
}

/// A hanging strand. Points along it come from [CanopyGeometry.strandPoint].
class Strand {
  const Strand({
    required this.x,
    required this.y,
    required this.length,
    required this.curve,
    required this.amp,
    required this.phase,
    this.thickness = 1,
    this.variant = 0,
  });

  final double x, y, length, curve, amp, phase, thickness;
  final int variant;
}

/// A static branch, culm or stalactite spine.
class Bough {
  const Bough(this.points, {this.thickness = 1, this.variant = 0});
  final List<ui.Offset> points;
  final double thickness;
  final int variant;
}

/// A leaf or blossom cluster of radius [r] around a point.
class Cluster {
  const Cluster(this.x, this.y, this.r, this.variant);
  final double x, y, r;
  final int variant;
}

class CanopyModel {
  const CanopyModel({
    required this.kind,
    required this.strands,
    required this.boughs,
    required this.clusters,
    required this.tips,
    this.lantern,
  });

  final CanopyKind kind;
  final List<Strand> strands;
  final List<Bough> boughs;
  final List<Cluster> clusters;

  /// Points drips fall from.
  final List<ui.Offset> tips;
  final ui.Rect? lantern;
}

/// Procedural canopy geometry. Everything is placed either in the side
/// quarters, at least [sideMargin] from the central lane, or above
/// [SceneLayers.laneTop] minus the largest sway, so the lane stays clear at
/// any phase and wind.
class CanopyGeometry {
  CanopyGeometry._();

  static const double sideMargin = 34;
  static const double centreDepth = 96;
  static const double sideDepth = 176;

  /// Point at fraction [f] (0 root, 1 tip) of [strand] for a sway phase in
  /// turns and a wind shear applied about the top edge. Sway grows toward the
  /// tip with `f²`, the way a hanging strand bends.
  static ui.Offset strandPoint(
    Strand s,
    double f,
    double phaseTurns,
    double shear,
  ) {
    final sway = s.amp * f * f * math.sin(phaseTurns * math.pi * 2 + s.phase);
    final y = s.y + s.length * f;
    final x = s.x + s.curve * f * f + sway + y * shear;
    return ui.Offset(x, y);
  }

  static CanopyModel build(CanopyKind kind, int seed, {bool lantern = false}) {
    final random = math.Random(seed ^ (kind.index + 1) * 0x9e3779b1);
    final strands = <Strand>[];
    final boughs = <Bough>[];
    final clusters = <Cluster>[];
    final tips = <ui.Offset>[];
    ui.Rect? lanternRect;

    double sideX(bool right, double t) => right
        ? SceneLayers.laneRight +
              sideMargin +
              t * (641 - SceneLayers.laneRight - sideMargin)
        : t * (SceneLayers.laneLeft - sideMargin);
    double centreX(double t) =>
        SceneLayers.laneLeft -
        8 +
        t * (SceneLayers.laneRight - SceneLayers.laneLeft + 16);

    void hang({
      required int perSide,
      required int centre,
      required double minLen,
      required double maxLen,
      required double amp,
      double curve = 6,
      double thickness = 1,
      int variants = 2,
    }) {
      for (var side = 0; side < 2; side++) {
        for (var i = 0; i < perSide; i++) {
          final x = sideX(side == 1, (i + random.nextDouble()) / perSide);
          final len = (minLen + random.nextDouble() * (maxLen - minLen)).clamp(
            4.0,
            sideDepth - 6,
          );
          strands.add(
            Strand(
              x: x,
              y: random.nextDouble() * 4,
              length: len,
              curve: (random.nextDouble() * 2 - 1) * curve,
              amp: amp * (.6 + random.nextDouble() * .4),
              phase: random.nextDouble() * math.pi * 2,
              thickness: thickness,
              variant: random.nextInt(variants),
            ),
          );
        }
      }
      for (var i = 0; i < centre; i++) {
        final len = math.min(
          centreDepth - 10,
          minLen * .5 + random.nextDouble() * (maxLen - minLen) * .5,
        );
        strands.add(
          Strand(
            x: centreX((i + random.nextDouble()) / centre),
            y: random.nextDouble() * 3,
            length: len,
            curve: (random.nextDouble() * 2 - 1) * curve,
            amp: amp * (.6 + random.nextDouble() * .4),
            phase: random.nextDouble() * math.pi * 2,
            thickness: thickness,
            variant: random.nextInt(variants),
          ),
        );
      }
    }

    // A wavy branch just above the top edge of the centre zone: only the
    // clusters hanging from it show, so it never reads as a garland.
    void topBough(int variant, {double thickness = 2}) {
      final points = <ui.Offset>[];
      for (var i = 0; i <= 8; i++) {
        final f = i / 8;
        points.add(
          ui.Offset(
            SceneLayers.laneLeft -
                12 +
                f * (SceneLayers.laneRight - SceneLayers.laneLeft + 24),
            -12 +
                4 * (1 - math.cos(f * math.pi * 2 + random.nextDouble() * .4)),
          ),
        );
      }
      boughs.add(Bough(points, thickness: thickness, variant: variant));
    }

    // A branch from a top corner curving inward and down, kept inside its
    // quarter, with [twigs] shorter side branches and clusters along it.
    void bough({
      required bool right,
      required double reach,
      required double drop,
      required double startY,
      int twigs = 3,
      double clusterR = 4,
      int clusterVariants = 3,
      double thickness = 2,
      int variant = 0,
      double perCluster = .8,
    }) {
      final x0 = right ? 641.0 : 0.0;
      final dir = right ? -1.0 : 1.0;
      final maxReach = SceneLayers.laneLeft - sideMargin - 4;
      final r = math.min(reach, maxReach);
      final points = <ui.Offset>[];
      for (var i = 0; i <= 6; i++) {
        final f = i / 6;
        points.add(ui.Offset(x0 + dir * r * f, startY + drop * f * f));
      }
      boughs.add(Bough(points, thickness: thickness, variant: variant));
      for (var i = 0; i < twigs; i++) {
        final f = .25 + .6 * (i / math.max(1, twigs - 1));
        final base = points[(f * 6).round()];
        final len = 10 + random.nextDouble() * 16;
        final down = random.nextBool();
        final end = ui.Offset(
          (base.dx + dir * len * .7).clamp(
            right ? SceneLayers.laneRight + sideMargin : 0,
            right ? 641 : SceneLayers.laneLeft - sideMargin,
          ),
          base.dy + (down ? len * .6 : -len * .3),
        );
        boughs.add(Bough([base, end], thickness: 1, variant: variant));
        tips.add(end);
        if (random.nextDouble() < perCluster) {
          clusters.add(
            Cluster(end.dx, end.dy, clusterR, random.nextInt(clusterVariants)),
          );
        }
      }
      for (var i = 1; i <= 6; i++) {
        if (random.nextDouble() < perCluster) {
          final p = points[i];
          clusters.add(
            Cluster(
              p.dx + (random.nextDouble() * 2 - 1) * 3,
              p.dy + (random.nextDouble() * 2 - 1) * 3,
              clusterR * (.7 + random.nextDouble() * .6),
              random.nextInt(clusterVariants),
            ),
          );
        }
      }
      tips.add(points.last);
    }

    switch (kind) {
      case CanopyKind.willow:
        hang(perSide: 11, centre: 9, minLen: 70, maxLen: 170, amp: 5, curve: 7);
      case CanopyKind.moss:
        bough(
          right: false,
          reach: 120,
          drop: 22,
          startY: 6,
          twigs: 2,
          perCluster: 0,
          thickness: 3,
          variant: 1,
        );
        bough(
          right: true,
          reach: 110,
          drop: 26,
          startY: 10,
          twigs: 2,
          perCluster: 0,
          thickness: 3,
          variant: 1,
        );
        hang(
          perSide: 9,
          centre: 6,
          minLen: 40,
          maxLen: 150,
          amp: 3.5,
          curve: 4,
          thickness: 2,
        );
      case CanopyKind.blossom:
      case CanopyKind.wisteria:
        bough(
          right: false,
          reach: 130,
          drop: 40,
          startY: 8,
          twigs: 4,
          clusterR: 5,
        );
        bough(
          right: true,
          reach: 125,
          drop: 46,
          startY: 14,
          twigs: 4,
          clusterR: 5,
        );
        bough(
          right: false,
          reach: 90,
          drop: 70,
          startY: 60,
          twigs: 3,
          clusterR: 4,
        );
        bough(
          right: true,
          reach: 80,
          drop: 60,
          startY: 72,
          twigs: 3,
          clusterR: 4,
        );
        // A short centre bough across the top keeps well above the lane.
        topBough(0);
        for (var i = 0; i < 7; i++) {
          clusters.add(
            Cluster(
              centreX((i + .5) / 7),
              4 + random.nextDouble() * 10,
              3 + random.nextDouble() * 2,
              random.nextInt(3),
            ),
          );
        }
        if (kind == CanopyKind.wisteria) {
          hang(
            perSide: 6,
            centre: 5,
            minLen: 18,
            maxLen: 48,
            amp: 2.5,
            curve: 2,
            variants: 3,
          );
        }
      case CanopyKind.momiji:
        bough(
          right: false,
          reach: 128,
          drop: 50,
          startY: 4,
          twigs: 5,
          clusterR: 6,
          perCluster: .95,
          variant: 2,
        );
        bough(
          right: true,
          reach: 128,
          drop: 44,
          startY: 8,
          twigs: 5,
          clusterR: 6,
          perCluster: .95,
          variant: 2,
        );
        bough(
          right: false,
          reach: 100,
          drop: 60,
          startY: 70,
          twigs: 3,
          clusterR: 5,
          variant: 2,
        );
        bough(
          right: true,
          reach: 96,
          drop: 58,
          startY: 78,
          twigs: 3,
          clusterR: 5,
          variant: 2,
        );
        topBough(2);
        for (var i = 0; i < 8; i++) {
          clusters.add(
            Cluster(
              centreX((i + .5) / 8),
              3 + random.nextDouble() * 14,
              3.5 + random.nextDouble() * 2.5,
              random.nextInt(3),
            ),
          );
        }
      case CanopyKind.bamboo:
        for (var side = 0; side < 2; side++) {
          final right = side == 1;
          for (var i = 0; i < 3; i++) {
            bough(
              right: right,
              reach: 60 + i * 30,
              drop: 90 + i * 30,
              startY: -4,
              twigs: 4,
              clusterR: 4,
              clusterVariants: 2,
              thickness: 2,
              variant: 3,
            );
          }
        }
        topBough(3, thickness: 1);
        for (var i = 0; i < 10; i++) {
          clusters.add(
            Cluster(
              centreX((i + .5) / 10),
              2 + random.nextDouble() * 12,
              3 + random.nextDouble() * 2,
              random.nextInt(2),
            ),
          );
        }
        if (lantern) {
          const lx = 592.0;
          lanternRect = const ui.Rect.fromLTWH(lx - 7, 36, 14, 22);
          boughs.add(
            const Bough([ui.Offset(lx, 0), ui.Offset(lx, 36)], variant: 4),
          );
        }
      case CanopyKind.stalactite:
      case CanopyKind.crystal:
        for (var side = 0; side < 2; side++) {
          final right = side == 1;
          for (var i = 0; i < 4; i++) {
            final x = sideX(right, (i + .5) / 4);
            final h = 30 + random.nextDouble() * 70;
            final w = 6 + random.nextDouble() * 8;
            boughs.add(
              Bough(
                [
                  ui.Offset(x - w / 2, 0),
                  ui.Offset(x + w / 2, 0),
                  ui.Offset(x, h),
                ],
                thickness: w,
                variant: 5,
              ),
            );
            tips.add(ui.Offset(x, h));
            clusters.add(Cluster(x + w * .3, h * .55, 2.5, random.nextInt(3)));
          }
        }
        for (var i = 0; i < 6; i++) {
          final x = centreX((i + .5) / 6);
          final h = 14 + random.nextDouble() * 40;
          final w = 4 + random.nextDouble() * 6;
          boughs.add(
            Bough(
              [
                ui.Offset(x - w / 2, 0),
                ui.Offset(x + w / 2, 0),
                ui.Offset(x, h),
              ],
              thickness: w,
              variant: 5,
            ),
          );
          tips.add(ui.Offset(x, h));
        }
        hang(
          perSide: 5,
          centre: 3,
          minLen: 30,
          maxLen: 130,
          amp: 2,
          curve: 3,
          variants: 1,
        );
      case CanopyKind.pine:
        bough(
          right: false,
          reach: 128,
          drop: 36,
          startY: 10,
          twigs: 5,
          clusterR: 7,
          perCluster: 1,
          variant: 6,
        );
        bough(
          right: true,
          reach: 128,
          drop: 30,
          startY: 6,
          twigs: 5,
          clusterR: 7,
          perCluster: 1,
          variant: 6,
        );
        bough(
          right: false,
          reach: 96,
          drop: 50,
          startY: 84,
          twigs: 3,
          clusterR: 6,
          perCluster: 1,
          variant: 7,
        );
        bough(
          right: true,
          reach: 90,
          drop: 56,
          startY: 92,
          twigs: 3,
          clusterR: 6,
          perCluster: 1,
          variant: 7,
        );
      // Alpine keeps the top centre open sky: pine tufts only at the sides.
    }
    return CanopyModel(
      kind: kind,
      strands: strands,
      boughs: boughs,
      clusters: clusters,
      tips: tips,
      lantern: lanternRect,
    );
  }
}

/// Draws the layer stack. The renderer calls [drawSlot] at each tier; painted
/// images replace the procedural generators when they loaded.
class SceneLayerPainter {
  ui.Image? canopyImage;
  ui.Image? midBankImage;
  ui.Image? foregroundImage;
  bool reducedMotion = false;

  /// Animated branches and bushes (`foliage.dart`), drawn after the canopy,
  /// after the mid bank and after the near corner. Call `foliage.prepare`
  /// once per biome so its atlas exists.
  final FoliagePainter foliage = FoliagePainter();

  /// Richness at which the foliage starts to fade in, like a canopy layer.
  static const double foliageRevealAt = .2;

  static const double _width = 641;
  static const double _height = 359;
  static const int phaseBuckets = 16;

  /// Largest wind shear (x per y) any layer receives, at depth 1.
  static const double maxShear = .08;

  /// Breathing parallax amplitude at depth 1 and its period.
  static const double breathAmplitude = 1.5;
  static const double breathPeriod = 40;
  static const double swayPeriod = 5.5;

  final ui.Paint _paint = ui.Paint()..isAntiAlias = false;
  List<SceneLayer> _stack = const [];
  String? _stackBiome;
  CanopyModel? _canopy;
  String? _canopyKey;
  final List<ui.Picture?> _frames = List.filled(phaseBuckets, null);
  int _frameNight = -1;
  int _frameAlpha = -1;
  List<_Spark> _sparks = const [];
  int? _sparkSeed;

  List<SceneLayer> stackFor(PondModel m) {
    if (_stackBiome != m.biome) {
      _stackBiome = m.biome;
      _stack = SceneLayers.stackFor(m.biome);
    }
    return _stack;
  }

  CanopyModel? canopyFor(PondModel m) {
    SceneLayer? layer;
    for (final l in stackFor(m)) {
      if (l.canopy != null) {
        layer = l;
        break;
      }
    }
    if (layer == null) return null;
    final key = '${m.biome}:${m.sceneSeed}';
    if (_canopyKey != key) {
      _canopyKey = key;
      _canopy = CanopyGeometry.build(
        layer.canopy!,
        m.sceneSeed,
        lantern: layer.lantern,
      );
      _clearFrames();
    }
    return _canopy;
  }

  /// Night tint for painted layers. This is the one place the layer stack
  /// grades colour; a scene-wide grade (`SceneGrade.filterFor(model)`) can
  /// replace it.
  /// Painted layers share the backdrop's continuous time-of-day grade.
  ui.ColorFilter? tintFor(PondModel m) => SceneGrade.filterFor(m);

  List<double> _tintColor(PondModel m) => SceneGrade.matrixFor(
    daylight: m.daylight,
    biome: m.biome,
    cloud: m.cloudDarkening,
  );

  /// Wind shear for a layer: gusts lean hanging things about the top edge.
  double shearFor(PondModel m, SceneLayer layer) {
    if (reducedMotion) return 0;
    final tell = m.wind == 0 ? 0.0 : m.windTell * m.wind.sign;
    return ((m.wind * .6 + tell * .032) * layer.windResponse * layer.depth)
        .clamp(-maxShear, maxShear);
  }

  ui.Offset _breath(PondModel m, SceneLayer layer) {
    if (reducedMotion) return ui.Offset.zero;
    final a = m.time * math.pi * 2 / breathPeriod;
    return ui.Offset(
      math.sin(a) * breathAmplitude * layer.depth,
      math.cos(a) * breathAmplitude * .3 * layer.depth,
    );
  }

  double _reveal(PondModel m, SceneLayer layer) =>
      ((m.richness - layer.revealAt) / .25).clamp(0.0, 1.0);

  void drawSlot(ui.Canvas c, LayerSlot slot, PondModel m, double motion) {
    for (final layer in stackFor(m)) {
      if (layer.slot != slot) continue;
      switch (slot) {
        case LayerSlot.farBank:
          break;
        case LayerSlot.midBank:
          _midBank(c, m, layer, motion);
        case LayerSlot.canopy:
          _canopyLayer(c, m, layer, motion);
        case LayerSlot.nearCorner:
          _foreground(c, m, layer);
        case LayerSlot.particles:
          _particles(c, m, layer, motion);
      }
    }
    _foliage(c, m, slot);
  }

  /// Foliage per slot: it belongs to every biome, whether or not the stack
  /// declares a layer in that slot, so it runs after the declared layers.
  void _foliage(ui.Canvas c, PondModel m, LayerSlot slot) {
    foliage.reducedMotion = reducedMotion;
    final reveal = ((m.richness - foliageRevealAt) / .25).clamp(0.0, 1.0);
    if (reveal <= 0) return;
    final grade = tintFor(m);
    switch (slot) {
      case LayerSlot.midBank:
        foliage.observe(m);
        foliage.drawBushes(
          c,
          m,
          reveal,
          _breath(m, const SceneLayer(slot: LayerSlot.midBank, depth: .35)),
          grade,
          near: false,
        );
      case LayerSlot.canopy:
        foliage.observe(m);
        foliage.drawBranches(
          c,
          m,
          reveal,
          _breath(m, const SceneLayer(slot: LayerSlot.canopy, depth: .8)),
          grade,
        );
      case LayerSlot.nearCorner:
        foliage.observe(m);
        foliage.drawBushes(
          c,
          m,
          reveal,
          _breath(m, const SceneLayer(slot: LayerSlot.nearCorner, depth: 1)),
          grade,
          near: true,
        );
      case LayerSlot.farBank:
      case LayerSlot.particles:
        break;
    }
  }

  // --- pixel primitives (same conventions as PondRenderer) ---

  void _rect(
    ui.Canvas c,
    double x,
    double y,
    double w,
    double h,
    int color, [
    double opacity = 1,
  ]) {
    if (w <= 0 || h <= 0 || opacity <= 0) return;
    _paint.color = ui.Color(color).withValues(alpha: opacity.clamp(0.0, 1.0));
    c.drawRect(
      ui.Rect.fromLTWH(
        x.roundToDouble(),
        y.roundToDouble(),
        w.ceilToDouble(),
        h.ceilToDouble(),
      ),
      _paint,
    );
  }

  void _line(
    ui.Canvas c,
    double x,
    double y,
    double tx,
    double ty,
    int color, [
    double opacity = 1,
    double thickness = 1,
  ]) {
    final steps = math.max((tx - x).abs(), (ty - y).abs()).ceil();
    for (var i = 0; i <= steps; i++) {
      final p = steps == 0 ? 0.0 : i / steps;
      _rect(
        c,
        x + (tx - x) * p,
        y + (ty - y) * p,
        thickness,
        thickness,
        color,
        opacity,
      );
    }
  }

  void _oval(
    ui.Canvas c,
    double x,
    double y,
    double rx,
    double ry,
    int color, [
    double opacity = 1,
  ]) {
    for (var row = -ry.floor(); row <= ry.floor(); row++) {
      final span = rx * math.sqrt(math.max(0, 1 - row * row / (ry * ry)));
      _rect(c, x - span, y + row, span * 2, 1, color, opacity);
    }
  }

  /// Multiplies a procedural colour by the night tint, like the painted
  /// layers' modulate filter.
  int _shade(int color, List<double> tint) {
    final (r, g, b) = SceneGrade.apply(tint, (
      ((color >> 16) & 0xff).toDouble(),
      ((color >> 8) & 0xff).toDouble(),
      (color & 0xff).toDouble(),
    ));
    return 0xff000000 | (r.round() << 16) | (g.round() << 8) | b.round();
  }

  // --- mid bank ---

  void _midBank(ui.Canvas c, PondModel m, SceneLayer layer, double motion) {
    final reveal = _reveal(m, layer);
    if (reveal <= 0) return;
    final image = midBankImage;
    final breath = _breath(m, layer);
    if (image != null) {
      _paint
        ..filterQuality = ui.FilterQuality.none
        ..color = ui.Color.fromRGBO(255, 255, 255, reveal)
        ..colorFilter = tintFor(m);
      c.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(breath.dx, breath.dy, _width, _height),
        _paint,
      );
      _paint.colorFilter = null;
      return;
    }
    if (!layer.reeds) return;
    final tint = _tintColor(m);
    final basin = m.basin;
    final sparks = _sparksFor(m);
    for (var i = 0; i < 12; i++) {
      final s = sparks[i];
      final right = i.isOdd;
      final x = right
          ? basin.topRightX + 6 + s.a * 26
          : basin.topLeftX - 6 - s.a * 26;
      final baseY = basin.topY + 2 + s.b * 3;
      final h = 10 + s.c * 14;
      final sway =
          (math.sin(m.time * .7 + s.d * 7) * 1.2 +
              m.wind * 18 +
              m.windTell * 2) *
          motion *
          layer.depth;
      _line(
        c,
        x,
        baseY,
        x + sway + breath.dx,
        baseY - h,
        _shade(0xff2f5a46, tint),
        reveal * .9,
      );
      if (i % 3 == 0) {
        _rect(
          c,
          x + sway - 1,
          baseY - h - 4,
          2,
          5,
          _shade(0xff6b4a35, tint),
          reveal,
        );
      } else {
        _rect(
          c,
          x + sway,
          baseY - h - 2,
          1,
          3,
          _shade(0xff9fb47a, tint),
          reveal * .7,
        );
      }
    }
  }

  // --- canopy ---

  void _canopyLayer(ui.Canvas c, PondModel m, SceneLayer layer, double motion) {
    final reveal = _reveal(m, layer);
    if (reveal <= 0) return;
    final shear = shearFor(m, layer);
    final breath = _breath(m, layer);
    final image = canopyImage;
    if (image != null) {
      final sway = reducedMotion
          ? 0.0
          : math.sin(m.time * math.pi * 2 / swayPeriod) * 1.5 * layer.depth;
      c.save();
      c.translate(breath.dx + sway, breath.dy);
      c.skew(shear, 0);
      _paint
        ..filterQuality = ui.FilterQuality.none
        ..color = ui.Color.fromRGBO(255, 255, 255, reveal)
        ..colorFilter = tintFor(m);
      c.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, _width, _width * image.height / image.width),
        _paint,
      );
      _paint.colorFilter = null;
      c.restore();
      return;
    }
    final canopy = canopyFor(m);
    if (canopy == null) return;
    final night = (1 - m.daylight).clamp(0.0, 1.0);
    final nightBucket = (night * 6).round();
    final alphaBucket = (reveal * 6).round();
    if (nightBucket != _frameNight || alphaBucket != _frameAlpha) {
      _clearFrames();
      _frameNight = nightBucket;
      _frameAlpha = alphaBucket;
    }
    final phase = reducedMotion ? 0.0 : (m.time / swayPeriod) % 1;
    final bucket = (phase * phaseBuckets).floor() % phaseBuckets;
    final picture = _frames[bucket] ??= _bakeCanopy(
      canopy,
      bucket / phaseBuckets,
      alphaBucket / 6,
      _tintColor(m),
      jade: m.biome == 'jade_sanctuary',
    );
    c.save();
    c.translate(breath.dx, breath.dy);
    c.skew(shear, 0);
    c.drawPicture(picture);
    c.restore();
    _canopyLive(c, m, canopy, layer, shear, breath, reveal, night);
  }

  void _clearFrames() {
    for (var i = 0; i < _frames.length; i++) {
      _frames[i]?.dispose();
      _frames[i] = null;
    }
  }

  static const _willow = [0xff3f6b4e, 0xff6f9a62, 0xffa4b977];
  static const _moss = [0xff5a7a6e, 0xff8ea394, 0xffb7c4a8];
  static const _cherry = [0xfff7bfd4, 0xffffdfe9, 0xffe58fae];
  static const _wisteria = [0xffc9b8df, 0xffe6d8f2, 0xff9c86c4];
  static const _momiji = [0xffe2523a, 0xfff08c3b, 0xffe6b84c];
  static const _bambooLeaf = [0xff4f8a3e, 0xff8ec45a];
  static const _needles = [0xff2f5a3a, 0xff4e7f4a, 0xffe6b84c];
  static const _glowMoss = [0xff5ef2e8, 0xffc68cff, 0xffffca7a];
  static const _crystals = [0xfff448f0, 0xffc68cff, 0xffbae5ff];

  ui.Picture _bakeCanopy(
    CanopyModel canopy,
    double phaseTurns,
    double alpha,
    List<double> tint, {
    bool jade = false,
  }) {
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    int col(int color) => _shade(color, tint);
    final kind = canopy.kind;

    for (final b in canopy.boughs) {
      switch (b.variant) {
        case 5:
          // Stalactite: a tapered spine of rows with a lit edge.
          final top = b.points[0];
          final tip = b.points[2];
          final w = b.thickness;
          final h = tip.dy - top.dy;
          final rock = col(
            kind == CanopyKind.crystal ? 0xff3a3550 : 0xff3b4455,
          );
          final lit = col(kind == CanopyKind.crystal ? 0xff6b5f8a : 0xff5a6478);
          final dark = col(0xff232a38);
          for (var y = 0.0; y < h; y += 1) {
            final f = y / h;
            final rw = math.max(1.0, w * (1 - f));
            final x = tip.dx - rw / 2;
            _rect(c, x, y, rw, 1, rock, alpha);
            _rect(c, x, y, 1, 1, lit, alpha);
            if (rw > 2) _rect(c, x + rw - 1, y, 1, 1, dark, alpha);
          }
        case 4:
          _line(
            c,
            b.points[0].dx,
            b.points[0].dy,
            b.points[1].dx,
            b.points[1].dy,
            col(0xff5a4a3a),
            alpha,
          );
        default:
          final branch = switch (b.variant) {
            1 => 0xff4a5a4c,
            2 => 0xff5a3a2e,
            3 => 0xff6c9a4a,
            6 || 7 => 0xff4a3a2e,
            _ => 0xff4a3a44,
          };
          for (var i = 0; i + 1 < b.points.length; i++) {
            final p = b.points[i];
            final q = b.points[i + 1];
            _line(c, p.dx, p.dy, q.dx, q.dy, col(branch), alpha, b.thickness);
            if (b.variant == 3) {
              // Bamboo nodes and paired leaf blades.
              _rect(
                c,
                q.dx - 1,
                q.dy - 1,
                b.thickness + 2,
                1,
                col(0xff4b6e34),
                alpha,
              );
              final dir = q.dx > p.dx ? 1.0 : -1.0;
              for (var k = 0; k < 2; k++) {
                final leaf = _bambooLeaf[(i + k) % 2];
                _line(
                  c,
                  q.dx,
                  q.dy,
                  q.dx + dir * 7 * (k == 0 ? 1 : -.6),
                  q.dy + 4 + k * 2,
                  col(leaf),
                  alpha,
                );
              }
            } else if (b.variant == 6 || b.variant == 7) {
              // Needle fans along pine and larch boughs.
              final gold = b.variant == 7;
              for (var k = 0; k < 4; k++) {
                final f = (k + .5) / 4;
                final nx = p.dx + (q.dx - p.dx) * f;
                final ny = p.dy + (q.dy - p.dy) * f;
                final needle = gold ? _needles[2] : _needles[k % 2];
                _line(c, nx, ny, nx - 3 + k % 2, ny + 5, col(needle), alpha);
                _line(c, nx, ny, nx + 3 - k % 2, ny + 4, col(needle), alpha);
                if (!gold) {
                  _rect(c, nx, ny - 1, 1, 1, col(0xffe8f2f8), alpha * .8);
                }
              }
            }
          }
      }
    }

    for (final s in canopy.strands) {
      const segments = 10;
      var prev = CanopyGeometry.strandPoint(s, 0, phaseTurns, 0);
      for (var i = 1; i <= segments; i++) {
        final f = i / segments;
        final p = CanopyGeometry.strandPoint(s, f, phaseTurns, 0);
        switch (kind) {
          case CanopyKind.willow:
            _line(c, prev.dx, prev.dy, p.dx, p.dy, col(_willow[0]), alpha);
            final side = i.isEven ? 1.0 : -3.0;
            _rect(
              c,
              p.dx + side,
              p.dy - 1,
              3,
              1,
              col(_willow[1 + (i + s.variant) % 2]),
              alpha * .95,
            );
          case CanopyKind.moss:
            final thick = i < segments - 2 ? s.thickness : 1.0;
            _line(
              c,
              prev.dx,
              prev.dy,
              p.dx,
              p.dy,
              col(_moss[s.variant]),
              alpha * .9,
              thick,
            );
            if (i % 3 == 0) {
              _rect(c, p.dx - 1, p.dy, 3, 2, col(_moss[2]), alpha * .55);
            }
          case CanopyKind.wisteria:
            _line(c, prev.dx, prev.dy, p.dx, p.dy, col(0xff6b5e7a), alpha * .8);
            final w = 4 - (f * 3).floor();
            _rect(
              c,
              p.dx - w / 2,
              p.dy,
              w.toDouble(),
              2,
              col(_wisteria[(i + s.variant) % 3]),
              alpha,
            );
          case CanopyKind.stalactite:
          case CanopyKind.crystal:
            _line(
              c,
              prev.dx,
              prev.dy,
              p.dx,
              p.dy,
              col(0xff3f7a3e),
              alpha * .85,
            );
            if (i % 2 == 0) {
              _rect(c, p.dx + 1, p.dy, 2, 1, col(0xff6aa84a), alpha * .8);
            }
          default:
            _line(c, prev.dx, prev.dy, p.dx, p.dy, col(0xff4a3a44), alpha);
        }
        prev = p;
      }
    }

    for (final k in canopy.clusters) {
      final palette = switch (kind) {
        CanopyKind.blossom => _cherry,
        CanopyKind.wisteria => _wisteria,
        CanopyKind.momiji => _momiji,
        CanopyKind.bamboo => _bambooLeaf,
        CanopyKind.pine => _needles,
        CanopyKind.crystal => _crystals,
        CanopyKind.stalactite => _glowMoss,
        _ => _willow,
      };
      final color = col(palette[k.variant % palette.length]);
      switch (kind) {
        case CanopyKind.momiji:
          // A momiji leaf cluster: a cross of two lobes with a lighter heart.
          _rect(c, k.x - k.r, k.y - 1, k.r * 2, 2, color, alpha);
          _rect(c, k.x - 1, k.y - k.r, 2, k.r * 2, color, alpha);
          _rect(
            c,
            k.x - k.r * .6,
            k.y - k.r * .6,
            k.r * 1.2,
            k.r * 1.2,
            color,
            alpha,
          );
          _rect(
            c,
            k.x,
            k.y - 1,
            1,
            1,
            col(_momiji[(k.variant + 1) % 3]),
            alpha,
          );
        case CanopyKind.bamboo:
          _line(c, k.x - k.r, k.y, k.x + k.r, k.y + 2, color, alpha);
          _line(
            c,
            k.x - k.r * .5,
            k.y - 1,
            k.x + k.r,
            k.y - 3,
            color,
            alpha * .9,
          );
        case CanopyKind.pine:
          for (var i = -2; i <= 2; i++) {
            _line(c, k.x, k.y, k.x + i * k.r * .4, k.y + k.r, color, alpha);
          }
          _rect(c, k.x - 1, k.y, 2, 1, col(0xffe8f2f8), alpha * .8);
        case CanopyKind.stalactite:
        case CanopyKind.crystal:
          // Glow moss and crystals are drawn live so they can pulse.
          break;
        default:
          _oval(c, k.x, k.y, k.r, k.r * .7, color, alpha);
          _rect(
            c,
            k.x - 1,
            k.y - 1,
            2,
            1,
            col(palette[(k.variant + 1) % palette.length]),
            alpha,
          );
      }
    }

    final lantern = canopy.lantern;
    if (lantern != null) {
      _rect(
        c,
        lantern.left,
        lantern.top,
        lantern.width,
        lantern.height,
        col(jade ? 0xff4ea69a : 0xffe86a45),
        alpha,
      );
      _rect(
        c,
        lantern.left + 1,
        lantern.top + 2,
        lantern.width - 2,
        lantern.height - 4,
        col(0xfff6d9a0),
        alpha,
      );
      for (var y = lantern.top + 4; y < lantern.bottom - 3; y += 4) {
        _rect(
          c,
          lantern.left + 1,
          y,
          lantern.width - 2,
          1,
          col(0xffb04a3a),
          alpha * .6,
        );
      }
      _rect(
        c,
        lantern.left + 2,
        lantern.top - 2,
        lantern.width - 4,
        2,
        col(0xff5a2a22),
        alpha,
      );
      _rect(
        c,
        lantern.left + 2,
        lantern.bottom,
        lantern.width - 4,
        2,
        col(0xff5a2a22),
        alpha,
      );
    }
    return recorder.endRecording();
  }

  /// Pulsing parts drawn every frame on top of the baked canopy.
  void _canopyLive(
    ui.Canvas c,
    PondModel m,
    CanopyModel canopy,
    SceneLayer layer,
    double shear,
    ui.Offset breath,
    double reveal,
    double night,
  ) {
    final lantern = canopy.lantern;
    if (lantern != null) {
      final jade = m.biome == 'jade_sanctuary';
      final flicker = reducedMotion
          ? .85
          : .75 + .25 * math.sin(m.time * 4.3) * math.cos(m.time * 2.7);
      final glow = (.12 + night * .5) * flicker * reveal;
      final x = lantern.center.dx + breath.dx + lantern.center.dy * shear;
      final y = lantern.center.dy + breath.dy;
      _oval(c, x, y, 16, 13, jade ? 0xff7ef5c4 : 0xffffb85c, glow * .35);
      _oval(c, x, y, 7, 10, jade ? 0xffdfffe8 : 0xffffefc2, glow * .6);
    }
    if (canopy.kind == CanopyKind.stalactite ||
        canopy.kind == CanopyKind.crystal) {
      final palette = canopy.kind == CanopyKind.crystal ? _crystals : _glowMoss;
      var i = 0;
      for (final k in canopy.clusters) {
        final pulse = reducedMotion
            ? .7
            : .5 + .5 * math.sin(m.time * 1.1 + i * 1.7);
        final color = palette[k.variant % palette.length];
        final x = k.x + breath.dx + k.y * shear;
        final y = k.y + breath.dy;
        final a = reveal * (.25 + night * .45) * pulse;
        if (canopy.kind == CanopyKind.crystal) {
          _rect(c, x - 1, y - 3, 2, 6, color, a);
          _rect(c, x - 2, y - 1, 4, 2, color, a * .8);
          _rect(c, x, y - 2, 1, 2, 0xffffffff, a * .9);
        } else {
          _oval(c, x, y, 3, 2, color, a * .5);
          _rect(c, x, y, 1, 1, 0xffffffff, a);
          _rect(c, x - 2, y + 1, 1, 1, color, a);
          _rect(c, x + 2, y - 1, 1, 1, color, a);
        }
        i++;
      }
    }
  }

  // --- near corner (the former RanitasGame foreground draw) ---

  void _foreground(ui.Canvas c, PondModel m, SceneLayer layer) {
    final image = foregroundImage;
    if (image == null) return;
    final opacity = (m.richness - layer.revealAt).clamp(0.0, 1.0) * .68;
    if (opacity <= 0) return;
    final sway = reducedMotion
        ? 0.0
        : math.sin(m.time * .18) * _width * .003 * m.richness;
    final breath = _breath(m, layer);
    _paint
      ..filterQuality = ui.FilterQuality.none
      ..color = ui.Color.fromRGBO(255, 255, 255, opacity)
      ..colorFilter = tintFor(m);
    c.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(
        -_width * .01 + sway + breath.dx,
        _height * .14 + breath.dy,
        _width * 1.02,
        _height * .86,
      ),
      _paint,
    );
    _paint.colorFilter = null;
  }

  // --- particles ---

  List<_Spark> _sparksFor(PondModel m) {
    if (_sparkSeed != m.sceneSeed || _sparks.isEmpty) {
      _sparkSeed = m.sceneSeed;
      final random = math.Random(m.sceneSeed ^ 0x2545f491);
      _sparks = List.generate(
        32,
        (_) => _Spark(
          random.nextDouble(),
          random.nextDouble(),
          random.nextDouble(),
          random.nextDouble(),
        ),
      );
    }
    return _sparks;
  }

  /// Particles are a pure function of time: each has a period, falls from the
  /// canopy bounds, drifts with wind and dissolves on the water with a small
  /// ripple-like fade. Nothing here touches the model.
  void _particles(ui.Canvas c, PondModel m, SceneLayer layer, double motion) {
    final emitter = layer.emitter;
    if (emitter == null || reducedMotion) return;
    final reveal = _reveal(m, layer);
    if (reveal <= 0) return;
    final sparks = _sparksFor(m);
    final tips = canopyFor(m)?.tips ?? const <ui.Offset>[];
    final count = switch (emitter) {
      EmitterKind.petals => 14,
      EmitterKind.leaves => 12,
      // Canopy drips thicken with the rain envelope.
      EmitterKind.drips => 6 + (m.rainIntensity * 6).round(),
      EmitterKind.spores => 10,
    };
    final basin = m.basin;
    for (var i = 0; i < count; i++) {
      final s = sparks[(i + emitter.index * 7) % sparks.length];
      final period = switch (emitter) {
        EmitterKind.petals => 9 + s.c * 6,
        EmitterKind.leaves => 8 + s.c * 5,
        EmitterKind.drips => 2.2 + s.c * 2.5,
        EmitterKind.spores => 12 + s.c * 8,
      };
      final local = (m.time + s.d * period) % period;
      final fall = period * .78;
      double x0;
      double y0;
      if (emitter == EmitterKind.drips && tips.isNotEmpty) {
        final tip = tips[i % tips.length];
        x0 = tip.dx;
        y0 = tip.dy;
      } else {
        x0 = s.a * _width;
        final inLane = x0 > SceneLayers.laneLeft && x0 < SceneLayers.laneRight;
        y0 = s.b * (inLane ? 80 : 150);
      }
      final yLand = basin.topY + 8 + s.c * (basin.bottomY - basin.topY - 16);
      if (local < fall) {
        final f = local / fall;
        final drift = switch (emitter) {
          EmitterKind.drips => 0.0,
          EmitterKind.spores => math.sin(m.time * .4 + i) * 12,
          _ => m.wind * 220 * f + math.sin(m.time * 1.8 + i) * 4 * (1 - f * .5),
        };
        final x = x0 + drift;
        final ease = emitter == EmitterKind.drips ? f * f : f;
        final y = emitter == EmitterKind.spores
            ? y0 + 70 * f
            : y0 + (yLand - y0) * ease;
        final fade = emitter == EmitterKind.spores
            ? math.sin(f * math.pi)
            : (basin.contains(x, yLand, margin: 3)
                  ? 1.0
                  : 1 - math.max(0.0, f - .7) / .3);
        final a = reveal * motion.clamp(0.0, 1.0) * fade;
        switch (emitter) {
          case EmitterKind.petals:
            final color = m.biome == 'lotus'
                ? _wisteria[i % 3]
                : _cherry[i % 3];
            _rect(c, x, y, 3, 2, color, a * .9);
            _rect(c, x + 1, y - 1, 2, 1, color, a * .5);
          case EmitterKind.leaves:
            final color = _momiji[i % 3];
            final flip = math.sin(m.time * 3 + i) > 0;
            _rect(c, x, y, flip ? 4 : 3, 2, color, a * .9);
            _rect(c, x + 1, y - 1, 2, 1, color, a * .5);
          case EmitterKind.drips:
            _rect(c, x, y, 1, 3, 0xffc6e4e8, a * .7);
            _rect(c, x, y + 2, 1, 1, 0xffe8fafc, a);
          case EmitterKind.spores:
            final color = m.biome == 'crystal_grotto' ? 0xffc68cff : 0xff5ef2e8;
            _oval(c, x, y, 3, 2, color, a * .18);
            _rect(c, x, y, 1, 1, 0xffffffff, a * .8);
        }
      } else if (emitter != EmitterKind.spores) {
        final u = (local - fall) / (period - fall);
        final x = x0 + (emitter == EmitterKind.drips ? 0 : m.wind * 220);
        if (!basin.contains(x, yLand, margin: 3)) continue;
        final r = 1 + u * 4;
        final a = reveal * motion.clamp(0.0, 1.0) * (1 - u) * .45;
        _rect(c, x - r, yLand, 1, 1, 0xffdff6f2, a);
        _rect(c, x + r, yLand, 1, 1, 0xffdff6f2, a);
        _rect(c, x - r * .6, yLand - r * .4, r * 1.2, 1, 0xffdff6f2, a * .6);
        _rect(c, x - r * .6, yLand + r * .4, r * 1.2, 1, 0xffdff6f2, a * .6);
      }
    }
  }

  void dispose() {
    _clearFrames();
    foliage.dispose();
    _canopy = null;
    _canopyKey = null;
    _sparks = const [];
    _sparkSeed = null;
  }
}

class _Spark {
  const _Spark(this.a, this.b, this.c, this.d);
  final double a, b, c, d;
}
