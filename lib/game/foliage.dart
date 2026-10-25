import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'pond_model.dart';
import 'scene_grade.dart';
import 'scene_layers.dart';

/// Animated foliage (design D5, "Foliage"): a procedural leaf-sprite atlas
/// drawn with `drawRawAtlas`, branch chains entering from the top corners
/// that bend under a wind trace with gust lag, and bushes on the shores and
/// in the near corners that sway from the ground. Painted overrides:
/// `foliage-<biome>.webp` (atlas) and `branches-<biome>.webp` (segment
/// strip), see `art/ASSET_REQUESTS.md` §2b.
///
/// Everything here is render state: nothing touches the model.

/// Leaf shapes the atlas can bake. Each biome picks one for its branches and
/// one for its bushes.
enum LeafKind {
  willow,
  blossom,
  momiji,
  bamboo,
  needle,
  moss,
  fern,
  wisteria,
  broad,
}

/// What a biome grows. Palettes are 4 tones: shadow, base, light, highlight.
class FoliageSpec {
  const FoliageSpec({
    required this.branchLeaf,
    required this.branchPalette,
    required this.bushLeaf,
    required this.bushPalette,
    this.bark = 0xff4a3a2e,
    this.bushBody = 0xff173e40,
    this.branchesPerSide = 3,
    this.branchDepth = .8,
    this.midBushes = true,
    this.nearBushes = true,
    this.glowFlecks = false,
    this.windResponse = 1,
  });

  final LeafKind branchLeaf;
  final List<int> branchPalette;
  final LeafKind bushLeaf;
  final List<int> bushPalette;
  final int bark;
  final int bushBody;
  final int branchesPerSide;
  final double branchDepth;
  final bool midBushes;
  final bool nearBushes;

  /// Grotto bushes carry a few glow-moss flecks that stay lit at night.
  final bool glowFlecks;
  final double windResponse;

  static const _willowLeaf = [0xff2f5a3e, 0xff4f8a4e, 0xff8fb866, 0xffc8dc8a];
  static const _cherry = [0xffd47a9c, 0xfff2a9c4, 0xffffd3e3, 0xfffff1f6];
  static const _peach = [0xffd98a8a, 0xfff5b3a8, 0xffffd8cc, 0xfffff3ec];
  static const _momiji = [0xff9e2f22, 0xffe2523a, 0xfff08c3b, 0xffffc85a];
  static const _bamboo = [0xff2f5e2a, 0xff4f8a3e, 0xff8ec45a, 0xffd3ef9a];
  static const _needle = [0xff1f3f2a, 0xff2f5a3a, 0xff4e7f4a, 0xff9fc48a];
  static const _moss = [0xff3f5a52, 0xff5a7a6e, 0xff8ea394, 0xffc8d4bc];
  static const _fern = [0xff1e4a3c, 0xff2f6d4f, 0xff4fa06a, 0xff9fd58a];
  static const _crystalFern = [0xff2a3a58, 0xff3f5a86, 0xff6f8fc4, 0xffbfd4ff];
  static const _wisteria = [0xff8a74b4, 0xffc9b8df, 0xffe6d8f2, 0xfffaf4ff];
  static const _bushGreen = [0xff1f4a3a, 0xff2f6a4a, 0xff5f9a5a, 0xffa4c47a];
  static const _bushTeal = [0xff173e40, 0xff2a5e5a, 0xff4f8a78, 0xff9fc4a8];
  static const _bushAutumn = [0xff5a3a1e, 0xff8a5a2a, 0xffc48a3a, 0xffe6c25a];
  static const _bushAlpine = [0xff1f4a2a, 0xff2f6e3a, 0xff5fa050, 0xffb8d88a];

  static FoliageSpec forBiome(String biome) => switch (biome) {
    'willow' => const FoliageSpec(
      branchLeaf: LeafKind.willow,
      branchPalette: _willowLeaf,
      bushLeaf: LeafKind.broad,
      bushPalette: _bushGreen,
      bark: 0xff4a4a3a,
    ),
    'blossom' => const FoliageSpec(
      branchLeaf: LeafKind.blossom,
      branchPalette: _cherry,
      bushLeaf: LeafKind.broad,
      bushPalette: _bushGreen,
      bark: 0xff3a2a2e,
    ),
    'lotus' => const FoliageSpec(
      branchLeaf: LeafKind.blossom,
      branchPalette: _peach,
      bushLeaf: LeafKind.wisteria,
      bushPalette: _wisteria,
      bark: 0xff3a2a2e,
    ),
    'cypress' || 'firefly' => const FoliageSpec(
      branchLeaf: LeafKind.moss,
      branchPalette: _moss,
      bushLeaf: LeafKind.broad,
      bushPalette: _bushTeal,
      bark: 0xff3f4a44,
      bushBody: 0xff12302f,
      windResponse: .7,
    ),
    'maple' || 'autumn_mist' => const FoliageSpec(
      branchLeaf: LeafKind.momiji,
      branchPalette: _momiji,
      bushLeaf: LeafKind.broad,
      bushPalette: _bushAutumn,
      bark: 0xff4a2a22,
      bushBody: 0xff2a2418,
    ),
    'sanctuary' || 'jade_sanctuary' => const FoliageSpec(
      branchLeaf: LeafKind.bamboo,
      branchPalette: _bamboo,
      bushLeaf: LeafKind.bamboo,
      bushPalette: _bushGreen,
      bark: 0xff6c9a4a,
      windResponse: .8,
    ),
    'grotto' => const FoliageSpec(
      branchLeaf: LeafKind.fern,
      branchPalette: _fern,
      bushLeaf: LeafKind.fern,
      bushPalette: _fern,
      bark: 0xff3f6a3e,
      bushBody: 0xff12302a,
      branchesPerSide: 2,
      glowFlecks: true,
      windResponse: .4,
    ),
    'crystal_grotto' => const FoliageSpec(
      branchLeaf: LeafKind.fern,
      branchPalette: _crystalFern,
      bushLeaf: LeafKind.fern,
      bushPalette: _crystalFern,
      bark: 0xff3a3a60,
      bushBody: 0xff1a1a38,
      branchesPerSide: 2,
      glowFlecks: true,
      windResponse: .4,
    ),
    'alpine' => const FoliageSpec(
      branchLeaf: LeafKind.needle,
      branchPalette: _needle,
      bushLeaf: LeafKind.broad,
      bushPalette: _bushAlpine,
      bark: 0xff3a2e26,
      windResponse: .7,
    ),
    _ => const FoliageSpec(
      branchLeaf: LeafKind.broad,
      branchPalette: _bushGreen,
      bushLeaf: LeafKind.broad,
      bushPalette: _bushGreen,
    ),
  };
}

/// The leaf atlas: 8 columns × 4 rows of [cell] px cells. Row 0 holds large
/// leaves, row 1 small ones, rows 2–3 their lit "flip" frames. Columns are
/// shape and tone variants. Painted atlases (`foliage-<biome>.webp`, 2× the
/// logical grid) use the same layout.
class LeafAtlas {
  LeafAtlas._(this.image, this.scale);

  static const int cell = 16;
  static const int columns = 8;
  static const int rows = 4;
  static const int width = cell * columns;
  static const int height = cell * rows;

  final ui.Image image;

  /// Image pixels per logical pixel (1 procedural, 2 painted).
  final double scale;

  /// Source rect of a cell in image pixels.
  ui.Rect rect(int row, int column) => ui.Rect.fromLTWH(
    column * cell * scale,
    row * cell * scale,
    cell * scale,
    cell * scale,
  );

  /// Wraps a painted atlas; returns null when its size is not a whole
  /// multiple of the logical grid.
  static LeafAtlas? fromPainted(ui.Image image) {
    if (image.width % width != 0 || image.height != image.width ~/ 2) {
      return null;
    }
    return LeafAtlas._(image, image.width / width);
  }

  /// Bakes the procedural atlas for a branch and a bush leaf kind.
  static Future<LeafAtlas> bake(FoliageSpec spec) async {
    final pixels = pixelsFor(spec);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return LeafAtlas._(await completer.future, 1);
  }

  /// The atlas pixels (RGBA, straight alpha of 0 or 255). Deterministic for
  /// a spec: the same bytes every bake. Columns 0–3 are the branch leaf and
  /// 4–7 the bush leaf, each in four tone variants.
  static Uint8List pixelsFor(FoliageSpec spec) {
    final p = _Raster(width, height);
    for (var column = 0; column < columns; column++) {
      final branch = column < 4;
      final kind = branch ? spec.branchLeaf : spec.bushLeaf;
      final palette = branch ? spec.branchPalette : spec.bushPalette;
      final variant = column % 4;
      for (var row = 0; row < rows; row++) {
        final small = row.isOdd;
        final lit = row >= 2;
        _paintLeaf(
          p,
          column * cell,
          row * cell,
          kind,
          palette,
          variant,
          small: small,
          lit: lit,
        );
      }
    }
    return p.pixels;
  }

  static void _paintLeaf(
    _Raster p,
    int ox,
    int oy,
    LeafKind kind,
    List<int> palette,
    int variant, {
    required bool small,
    required bool lit,
  }) {
    // Tone indices into the palette: a lit frame shifts every tone up one.
    int tone(int i) => palette[(i + (lit ? 1 : 0)).clamp(0, 3)];
    final shadow = tone(0);
    final base = tone(variant.isEven ? 1 : 2);
    final light = tone(2);
    final hi = tone(3);
    final cx = ox + 8;
    final cy = oy + 8;
    final s = small ? .6 : 1.0;
    final tilt = (variant - 1.5) * .35;
    switch (kind) {
      case LeafKind.willow:
        // A thin curved blade hanging from the top of the cell.
        final len = (12 * s).round();
        for (var i = 0; i < len; i++) {
          final f = i / len;
          final x = cx - 3 + (tilt * 4 * f + f * f * 2).round();
          p.set(x, oy + 2 + i, i < len * .3 ? shadow : base);
          if (i % 3 == 1) p.set(x + 1, oy + 2 + i, light);
        }
        if (lit) p.set(cx - 2, oy + 4, hi);
      case LeafKind.blossom:
        // A five-petal cluster: four petals around a darker heart.
        final r = small ? 2 : 3;
        for (final (dx, dy) in [(-r, 0), (r, 0), (0, -r), (0, r)]) {
          p.disc(cx + dx, cy + dy, small ? 1.2 : 1.8, base);
        }
        p.disc(cx + (tilt * 2).round(), cy, small ? 1.4 : 2.1, light);
        p.set(cx, cy, shadow);
        if (lit) {
          p.set(cx - 1, cy - r, hi);
          p.set(cx + r, cy - 1, hi);
        }
      case LeafKind.momiji:
        // A five-lobed star around a 3×3 heart.
        final r = small ? 4 : 6;
        for (var k = 0; k < 5; k++) {
          final a = -math.pi / 2 + k * math.pi * 2 / 5 + tilt * .3;
          p.line(
            cx,
            cy,
            cx + (math.cos(a) * r).round(),
            cy + (math.sin(a) * r).round(),
            k.isEven ? base : light,
          );
        }
        p.disc(cx, cy, 1.4, base);
        p.set(cx, cy, shadow);
        if (lit) p.set(cx + 1, cy - 2, hi);
      case LeafKind.bamboo:
        // A lanceolate blade with a lighter midrib.
        final len = small ? 8 : 13;
        final dir = variant.isEven ? 1 : -1;
        for (var i = 0; i < len; i++) {
          final f = i / len;
          final w = (math.sin(f * math.pi) * (small ? 1.6 : 2.4)).round();
          final x = cx - len ~/ 2 + i;
          final y = cy + (dir * (f - .5) * 4).round();
          for (var k = -w; k <= w; k++) {
            p.set(x, y + k, k == 0 ? light : base);
          }
          if (i == 0) p.set(x, y, shadow);
        }
        if (lit) p.set(cx + 2, cy - 1, hi);
      case LeafKind.needle:
        // A tuft of needles fanning down from one point.
        final n = small ? 4 : 6;
        final len = small ? 5 : 8;
        for (var k = 0; k < n; k++) {
          final a = math.pi * .5 + (k - (n - 1) / 2) * .32 + tilt * .2;
          p.line(
            cx,
            oy + 3,
            cx + (math.cos(a) * len).round(),
            oy + 3 + (math.sin(a) * len).round(),
            k.isEven ? base : shadow,
          );
        }
        p.set(cx, oy + 3, light);
        if (lit) p.set(cx - 1, oy + 4, hi);
      case LeafKind.moss:
        // A soft sprig: a short stem with one-pixel side hairs.
        final len = small ? 7 : 11;
        for (var i = 0; i < len; i++) {
          final x = cx + (tilt * i * .4).round();
          final y = oy + 2 + i;
          p.set(x, y, i < 2 ? shadow : base);
          if (i % 2 == 0) {
            p.set(x - 1, y, light);
            p.set(x + 2, y + 1, base);
          }
        }
        if (lit) p.set(cx + 1, oy + 5, hi);
      case LeafKind.fern:
        // A frond: midrib with paired leaflets shrinking toward the tip.
        final len = small ? 8 : 13;
        for (var i = 0; i < len; i++) {
          final f = i / len;
          final x = ox + 1 + i;
          final y = cy + (tilt * 2 * f).round();
          p.set(x, y, shadow);
          if (i % 2 == 0) {
            final leaflet = (3 * (1 - f)).round();
            for (var k = 1; k <= leaflet; k++) {
              p.set(x, y - k, base);
              p.set(x + 1, y + k, k == 1 ? light : base);
            }
          }
        }
        if (lit) p.set(ox + 4, cy - 2, hi);
      case LeafKind.wisteria:
        // A raceme bit: three stacked ovals, lighter toward the top.
        final r = small ? 1.3 : 1.9;
        for (var k = 0; k < 3; k++) {
          p.disc(
            cx + (tilt * 2).round() + (k.isOdd ? 1 : -1),
            cy - 4 + k * 4,
            r,
            k == 0 ? light : (k == 1 ? base : shadow),
          );
        }
        if (lit) p.set(cx, cy - 5, hi);
      case LeafKind.broad:
        // An oval leaf with a dark rim and a lit top-left.
        final rx = small ? 3.0 : 4.6;
        final ry = small ? 2.0 : 3.0;
        p.ellipse(cx, cy, rx + .6, ry + .6, shadow);
        p.ellipse(cx, cy, rx, ry, base);
        p.ellipse(cx - 1, cy - 1, rx * .55, ry * .55, light);
        p.set(cx - 1 + (tilt).round(), cy - 1, lit ? hi : light);
        if (lit) p.set(cx + 1, cy, hi);
    }
  }
}

/// Tiny pixel painter for the atlas bake.
class _Raster {
  _Raster(this.width, this.height) : pixels = Uint8List(width * height * 4);
  final int width, height;
  final Uint8List pixels;

  void set(int x, int y, int argb) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final i = (y * width + x) * 4;
    pixels[i] = (argb >> 16) & 0xff;
    pixels[i + 1] = (argb >> 8) & 0xff;
    pixels[i + 2] = argb & 0xff;
    pixels[i + 3] = 0xff;
  }

  void line(int x0, int y0, int x1, int y1, int argb) {
    final steps = math.max((x1 - x0).abs(), (y1 - y0).abs());
    for (var i = 0; i <= steps; i++) {
      final f = steps == 0 ? 0.0 : i / steps;
      set((x0 + (x1 - x0) * f).round(), (y0 + (y1 - y0) * f).round(), argb);
    }
  }

  void disc(int cx, int cy, double r, int argb) => ellipse(cx, cy, r, r, argb);

  void ellipse(int cx, int cy, double rx, double ry, int argb) {
    for (var y = -ry.ceil(); y <= ry.ceil(); y++) {
      for (var x = -rx.ceil(); x <= rx.ceil(); x++) {
        if (x * x / (rx * rx) + y * y / (ry * ry) <= 1) {
          set(cx + x, cy + y, argb);
        }
      }
    }
  }
}

/// One leaf of a cluster: an offset from the cluster anchor, a cell column,
/// a base rotation and a phase.
class LeafInstance {
  const LeafInstance(this.dx, this.dy, this.column, this.rotation, this.phase);
  final double dx, dy, rotation, phase;
  final int column;
}

/// A pack of leaves hanging at fraction [t] of segment [segment].
class LeafCluster {
  const LeafCluster({
    required this.segment,
    required this.t,
    required this.leaves,
    required this.small,
    required this.radius,
  });
  final int segment;
  final double t;
  final List<LeafInstance> leaves;
  final bool small;

  /// Largest leaf offset plus half a cell: the cluster's reach from its anchor.
  final double radius;
}

/// A chain of segments from a root at the frame's edge. Every segment's
/// angle is its rest angle plus a bounded lean, so the tip can never move
/// farther than the total length from the root.
class BranchChain {
  const BranchChain({
    required this.rootX,
    required this.rootY,
    required this.lengths,
    required this.restAngles,
    required this.thickness,
    required this.clusters,
    required this.phase,
    required this.right,
  });

  final double rootX, rootY;
  final List<double> lengths;

  /// Absolute angles in radians, +x to the right and +y down.
  final List<double> restAngles;
  final double thickness;
  final List<LeafCluster> clusters;
  final double phase;
  final bool right;

  int get segments => lengths.length;
  double get totalLength => lengths.fold(0.0, (a, b) => a + b);

  /// Reach bound: no point of the chain or its leaves lies farther than this
  /// from the root, at any lean.
  double get reach {
    var r = 0.0;
    for (final k in clusters) {
      r = math.max(r, k.radius);
    }
    return totalLength + r;
  }

  /// Joint positions for the given per-segment lean angles.
  List<ui.Offset> joints(List<double> leans) {
    final out = <ui.Offset>[ui.Offset(rootX, rootY)];
    var x = rootX;
    var y = rootY;
    for (var k = 0; k < segments; k++) {
      final a = restAngles[k] + leans[k];
      x += math.cos(a) * lengths[k];
      y += math.sin(a) * lengths[k];
      out.add(ui.Offset(x, y));
    }
    return out;
  }
}

/// A bush: layered body blobs anchored at a ground point, with leaves on top.
class Bush {
  const Bush({
    required this.x,
    required this.y,
    required this.rx,
    required this.ry,
    required this.scale,
    required this.leaves,
    required this.phase,
    required this.near,
  });

  /// Ground anchor; the bush rises above it.
  final double x, y;
  final double rx, ry;
  final double scale;
  final List<LeafInstance> leaves;
  final double phase;
  final bool near;
}

class FoliageModel {
  const FoliageModel({
    required this.spec,
    required this.branches,
    required this.midBushes,
    required this.nearBushes,
  });
  final FoliageSpec spec;
  final List<BranchChain> branches;
  final List<Bush> midBushes;
  final List<Bush> nearBushes;
}

/// Seeded placement. Branches are built so that `rootX ± reach` stays
/// inside the side quarters (`SceneLayers.laneLeft − sideMargin`), which
/// keeps the central lane clear at any lean without checking poses.
class FoliageGeometry {
  FoliageGeometry._();

  /// Largest lean of any segment, radians.
  static const double maxLean = .36;

  /// Side margin from the lane, like the canopy's.
  static const double sideMargin = CanopyGeometry.sideMargin;

  static FoliageModel build(FoliageSpec spec, int seed, WaterBasin basin) {
    final random = math.Random(seed ^ 0x6f1d3a5b);
    final branches = <BranchChain>[];
    final limit = SceneLayers.laneLeft - sideMargin - 2;

    for (var side = 0; side < 2; side++) {
      final right = side == 1;
      for (var i = 0; i < spec.branchesPerSide; i++) {
        // Branch 0 comes in from the corner, 1 hangs from the top edge,
        // 2 enters lower down the side edge.
        final double rootX;
        final double rootY;
        final double length;
        final double baseAngle;
        switch (i) {
          case 0:
            rootX = 0;
            rootY = 2 + random.nextDouble() * 10;
            length = 96 + random.nextDouble() * 18;
            baseAngle = .12 + random.nextDouble() * .12;
          case 1:
            rootX = 30 + random.nextDouble() * 24;
            rootY = 0;
            length = 44 + random.nextDouble() * 10;
            baseAngle = .9 + random.nextDouble() * .3;
          default:
            rootX = 0;
            rootY = 52 + random.nextDouble() * 40;
            length = 70 + random.nextDouble() * 20;
            baseAngle = .28 + random.nextDouble() * .18;
        }
        final segments = 4 + random.nextInt(2);
        final lengths = <double>[];
        final rest = <double>[];
        // Segments shorten toward the tip (weights 1.2 → 0.8).
        var weightSum = 0.0;
        for (var k = 0; k < segments; k++) {
          weightSum += 1.2 - .4 * k / (segments - 1);
        }
        for (var k = 0; k < segments; k++) {
          lengths.add(length * (1.2 - .4 * k / (segments - 1)) / weightSum);
          // Drooping toward the tip, with a little wobble.
          rest.add(baseAngle + k * .09 + (random.nextDouble() - .5) * .12);
        }
        final clusters = <LeafCluster>[];
        var radius = 0.0;
        final clusterCount = 5 + random.nextInt(3);
        for (var c = 0; c < clusterCount; c++) {
          // Packs spread from the second segment to the tip; the last pack
          // always sits at the tip.
          final last = c == clusterCount - 1;
          final segment = last
              ? segments - 1
              : math.min(segments - 1, 1 + (c * segments ~/ clusterCount));
          final t = last ? 1.0 : .3 + random.nextDouble() * .7;
          final small = !last && random.nextDouble() < .4;
          final spread = small ? 5.0 : 7.0;
          final leaves = <LeafInstance>[];
          final n = 4 + random.nextInt(3);
          for (var l = 0; l < n; l++) {
            final a = random.nextDouble() * math.pi * 2;
            final d = random.nextDouble() * spread;
            leaves.add(
              LeafInstance(
                math.cos(a) * d,
                math.sin(a) * d + 2,
                random.nextInt(4),
                (random.nextDouble() - .5) * .9,
                random.nextDouble() * math.pi * 2,
              ),
            );
          }
          final r = spread + LeafAtlas.cell * .5 + 1;
          radius = math.max(radius, r);
          clusters.add(
            LeafCluster(
              segment: segment,
              t: t,
              leaves: leaves,
              small: small,
              radius: r,
            ),
          );
        }
        // Enforce the reach bound by shrinking the chain if needed.
        final total = lengths.fold(0.0, (a, b) => a + b);
        final allowed = limit - rootX - radius;
        if (total > allowed) {
          final k = allowed / total;
          for (var s = 0; s < lengths.length; s++) {
            lengths[s] *= k;
          }
        }
        branches.add(
          BranchChain(
            rootX: right ? 641 - rootX : rootX,
            rootY: rootY,
            lengths: lengths,
            restAngles: right ? rest.map((a) => math.pi - a).toList() : rest,
            thickness: 3.4 - i * .6,
            clusters: clusters,
            phase: random.nextDouble() * math.pi * 2,
            right: right,
          ),
        );
      }
    }

    List<LeafInstance> leavesFor(double rx, double ry, int count, double top) {
      final out = <LeafInstance>[];
      for (var l = 0; l < count; l++) {
        final a = random.nextDouble() * math.pi * 2;
        final d = math.sqrt(random.nextDouble());
        out.add(
          LeafInstance(
            math.cos(a) * d * rx,
            -top - math.sin(a).abs() * d * ry,
            4 + random.nextInt(4),
            (random.nextDouble() - .5) * 1.2,
            random.nextDouble() * math.pi * 2,
          ),
        );
      }
      return out;
    }

    final mid = <Bush>[];
    if (spec.midBushes) {
      for (var side = 0; side < 2; side++) {
        final right = side == 1;
        for (var i = 0; i < 2; i++) {
          final y = basin.topY + (i == 0 ? 1 : 24 + random.nextDouble() * 10);
          final edge = right ? basin.rightX(y) : basin.leftX(y);
          final rx = 14 + random.nextDouble() * 8;
          final ry = 7 + random.nextDouble() * 3;
          final x = right ? edge + rx + 6 : edge - rx - 6;
          mid.add(
            Bush(
              x: x,
              y: y,
              rx: rx,
              ry: ry,
              scale: .7,
              leaves: leavesFor(rx * .9, ry * 1.4, 14, 2),
              phase: random.nextDouble() * math.pi * 2,
              near: false,
            ),
          );
        }
      }
    }
    final near = <Bush>[];
    if (spec.nearBushes) {
      for (var side = 0; side < 2; side++) {
        final right = side == 1;
        for (var i = 0; i < 2; i++) {
          final rx = i == 0
              ? 42 + random.nextDouble() * 14
              : 24 + random.nextDouble() * 8;
          final ry = i == 0
              ? 16 + random.nextDouble() * 5
              : 11 + random.nextDouble() * 3;
          final inset = i == 0
              ? 30 + random.nextDouble() * 20
              : 90 + random.nextDouble() * 30;
          final x = right ? 641 - inset : inset;
          near.add(
            Bush(
              x: x,
              y: 356 - i * 4,
              rx: rx,
              ry: ry,
              scale: 1,
              leaves: leavesFor(rx * .9, ry * 1.5, i == 0 ? 44 : 22, 3),
              phase: random.nextDouble() * math.pi * 2,
              near: true,
            ),
          );
        }
      }
    }
    return FoliageModel(
      spec: spec,
      branches: branches,
      midBushes: mid,
      nearBushes: near,
    );
  }
}

/// A short trace of the model's wind so gust fronts reach branches with a
/// lag: those nearer the windward edge lean first, and the tip of a chain
/// follows its root.
class WindTrace {
  final List<double> _t = [];
  final List<double> _w = [];
  static const int capacity = 180;

  void push(double t, double wind) {
    if (_t.isNotEmpty && t <= _t.last) {
      if (t < _t.last) {
        _t.clear();
        _w.clear();
      } else {
        return;
      }
    }
    _t.add(t);
    _w.add(wind);
    if (_t.length > capacity) {
      _t.removeAt(0);
      _w.removeAt(0);
    }
  }

  /// Wind at time [t] by linear interpolation; the oldest sample before the
  /// trace, the newest after it.
  double at(double t) {
    if (_t.isEmpty) return 0;
    if (t <= _t.first) return _w.first;
    if (t >= _t.last) return _w.last;
    var lo = 0;
    var hi = _t.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_t[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _t[hi] - _t[lo];
    final f = span <= 0 ? 0.0 : (t - _t[lo]) / span;
    return _w[lo] + (_w[hi] - _w[lo]) * f;
  }
}

/// Draws the foliage. Owned by [SceneLayerPainter]; call [prepare] once per
/// biome so the atlas exists, then the slot methods each frame.
class FoliagePainter {
  bool reducedMotion = false;

  /// Painted overrides (null → procedural).
  ui.Image? paintedAtlas;
  ui.Image? branchStrip;

  LeafAtlas? _atlas;
  String? _atlasBiome;
  FoliageModel? _model;
  String? _modelKey;
  final WindTrace _trace = WindTrace();
  final ui.Paint _paint = ui.Paint()
    ..isAntiAlias = false
    ..filterQuality = ui.FilterQuality.none;
  final ui.Paint _bark = ui.Paint()
    ..isAntiAlias = false
    ..strokeCap = ui.StrokeCap.square;
  final List<ui.Picture?> _bodies = List.filled(14, null);

  /// Seconds for a gust front to cross the frame.
  static const double frontCrossing = .5;

  /// Lean per unit wind at the tip of a chain, before the clamp.
  static const double leanPerWind = .55;

  /// Flutter rates, Hz: large leaves sway slowly, small ones flicker.
  static const double largeFlutterHz = 1.7;
  static const double smallFlutterHz = 3.6;

  LeafAtlas? get atlas => _atlas;
  bool get ready => _atlas != null;

  /// Bakes (or wraps) the atlas for [biome]. Idempotent per biome.
  Future<void> prepare(String biome) async {
    if (_atlasBiome == biome && _atlas != null) return;
    final painted = paintedAtlas;
    final wrapped = painted == null ? null : LeafAtlas.fromPainted(painted);
    final atlas = wrapped ?? await LeafAtlas.bake(FoliageSpec.forBiome(biome));
    if (_atlas != null && _atlas!.image != painted) _atlas!.image.dispose();
    _atlas = atlas;
    _atlasBiome = biome;
  }

  FoliageModel modelFor(PondModel m) {
    final key = '${m.biome}:${m.sceneSeed}';
    if (_modelKey != key) {
      _modelKey = key;
      _model = FoliageGeometry.build(
        FoliageSpec.forBiome(m.biome),
        m.sceneSeed,
        m.basin,
      );
      _clearBodies();
    }
    return _model!;
  }

  /// Records the wind of this frame. Call once per render before drawing.
  void observe(PondModel m) {
    _trace.push(m.time, reducedMotion ? 0 : m.wind);
  }

  /// Per-segment lean angles of [b] at the model time: a lagged, clamped wind
  /// lean growing toward the tip plus a slow ambient sway, zero under reduced
  /// motion. Every value is within ±[FoliageGeometry.maxLean].
  List<double> leans(BranchChain b, PondModel m, FoliageSpec spec) {
    final n = b.segments;
    if (reducedMotion) return List.filled(n, 0);
    final sign = m.wind >= 0 ? 1.0 : -1.0;
    // A front travelling with the wind reaches the windward edge first.
    final edgeLag = (sign > 0 ? b.rootX : 641 - b.rootX) / 641 * frontCrossing;
    final out = <double>[];
    for (var k = 0; k < n; k++) {
      final f = (k + 1) / n;
      final lag = edgeLag + k * .07;
      final w = _trace.at(m.time - lag);
      final tell = m.windTell * sign * .05;
      final windLean =
          (w * leanPerWind + tell) * spec.windResponse * (.35 + .65 * f);
      final ambient =
          math.sin(
            m.ambientTime * (2 * math.pi / (9 + k * .7)) + b.phase + k * .7,
          ) *
          (.025 + .03 * f);
      // Rotating a segment moves its tip perpendicular to it, so a wind
      // blowing right (+x) needs the angle to shrink on both sides: it lifts
      // a left branch (pointing with the wind) and pushes a right branch
      // (pointing into it) down, like a flag. −x wind does the reverse.
      final lean = (-windLean + ambient) * m.foliageMotion;
      out.add(lean.clamp(-FoliageGeometry.maxLean, FoliageGeometry.maxLean));
    }
    return out;
  }

  /// Horizontal shear of a bush at the model time, from the ground up.
  double bushShear(Bush bush, PondModel m) {
    if (reducedMotion) return 0;
    final lag = bush.x / 641 * frontCrossing * (m.wind >= 0 ? 1 : -1);
    final w = _trace.at(m.time - lag.abs());
    final ambient = math.sin(m.ambientTime * .32 + bush.phase) * .02;
    return ((w * .35 + m.windTell * .02 * (m.wind >= 0 ? 1 : -1) + ambient) *
            m.foliageMotion)
        .clamp(-.3, .3);
  }

  void _clearBodies() {
    for (var i = 0; i < _bodies.length; i++) {
      _bodies[i]?.dispose();
      _bodies[i] = null;
    }
  }

  int _bodyNight = -1;

  // --- drawing ---

  /// Branches with their leaf packs; the canopy slot.
  void drawBranches(
    ui.Canvas c,
    PondModel m,
    double reveal,
    ui.Offset breath,
    ui.ColorFilter? grade,
  ) {
    final atlas = _atlas;
    if (atlas == null || reveal <= 0) return;
    final model = modelFor(m);
    final spec = model.spec;
    final strip = branchStrip;
    _bark.color = ui.Color(spec.bark).withValues(alpha: reveal);
    final lit = _lighten(spec.bark);
    final n = model.branches.fold(
      0,
      (a, b) => a + b.clusters.fold(0, (x, k) => x + k.leaves.length),
    );
    final transforms = Float32List(n * 4);
    final rects = Float32List(n * 4);
    final colors = Int32List(n);
    var i = 0;
    final alpha = (reveal * 255).round().clamp(0, 255);
    final windy = m.wind.abs() + m.windTell * .5;
    for (final b in model.branches) {
      final leans = this.leans(b, m, spec);
      final joints = b.joints(leans);
      // Bark: one stroke per segment, tapering, with a lit upper edge.
      for (var k = 0; k < b.segments; k++) {
        final p = joints[k] + breath;
        final q = joints[k + 1] + breath;
        final w = math.max(1.0, b.thickness * (1 - k / (b.segments + 1)));
        if (strip != null) {
          _stripSegment(c, strip, p, q, k, b.segments, w, reveal, grade);
          continue;
        }
        _bark
          ..strokeWidth = w.roundToDouble()
          ..color = ui.Color(spec.bark).withValues(alpha: reveal)
          ..colorFilter = grade;
        c.drawLine(p, q, _bark);
        _bark
          ..strokeWidth = 1
          ..color = ui.Color(lit).withValues(alpha: reveal * .8);
        c.drawLine(p.translate(0, -w * .5), q.translate(0, -w * .5), _bark);
      }
      for (final k in b.clusters) {
        final a = joints[k.segment];
        final z = joints[k.segment + 1];
        final anchor = ui.Offset(
          a.dx + (z.dx - a.dx) * k.t,
          a.dy + (z.dy - a.dy) * k.t,
        );
        final swing = leans[k.segment];
        final hz = k.small ? smallFlutterHz : largeFlutterHz;
        for (final leaf in k.leaves) {
          final flutter = reducedMotion
              ? 0.0
              : math.sin(m.ambientTime * hz * math.pi * .5 + leaf.phase) *
                    (.06 + .15 * windy) *
                    m.foliageMotion;
          final rot = leaf.rotation + swing + flutter;
          final cos = math.cos(swing);
          final sin = math.sin(swing);
          final x = anchor.dx + leaf.dx * cos - leaf.dy * sin + breath.dx;
          final y = anchor.dy + leaf.dx * sin + leaf.dy * cos + breath.dy;
          _instance(
            transforms,
            rects,
            colors,
            i++,
            atlas,
            row: k.small ? 1 : 0,
            column: leaf.column,
            x: x,
            y: y,
            rotation: rot,
            scale: 1 / atlas.scale,
            alpha: alpha,
          );
        }
      }
    }
    _drawAtlas(c, atlas, transforms, rects, colors, i, grade);
  }

  void _stripSegment(
    ui.Canvas c,
    ui.Image strip,
    ui.Offset p,
    ui.Offset q,
    int k,
    int segments,
    double w,
    double reveal,
    ui.ColorFilter? grade,
  ) {
    // Strip: 6 cells of 48 × 16 logical px, root to tip, drawn from the
    // segment start along its direction and stretched to its length.
    final cellW = strip.width / 6;
    final cellH = strip.height.toDouble();
    final cell = math.min(5, (k * 5 / math.max(1, segments - 1)).round());
    final d = q - p;
    final len = d.distance;
    if (len <= 0) return;
    c.save();
    c.translate(p.dx, p.dy);
    c.rotate(math.atan2(d.dy, d.dx));
    _paint
      ..color = ui.Color.fromRGBO(255, 255, 255, reveal)
      ..colorFilter = grade
      ..blendMode = ui.BlendMode.srcOver;
    c.drawImageRect(
      strip,
      ui.Rect.fromLTWH(cell * cellW, 0, cellW, cellH),
      ui.Rect.fromLTWH(0, -8, len + 1, 16),
      _paint,
    );
    _paint.colorFilter = null;
    c.restore();
  }

  /// Bushes of one slot. Bodies are baked `Picture`s per night bucket and
  /// sheared from the ground; leaves are one atlas call.
  void drawBushes(
    ui.Canvas c,
    PondModel m,
    double reveal,
    ui.Offset breath,
    ui.ColorFilter? grade, {
    required bool near,
  }) {
    final atlas = _atlas;
    if (atlas == null || reveal <= 0) return;
    final model = modelFor(m);
    final spec = model.spec;
    final bushes = near ? model.nearBushes : model.midBushes;
    if (bushes.isEmpty) return;
    final night = (1 - m.daylight).clamp(0.0, 1.0);
    // Cache only neutral geometry. All daylight/cloud tint is applied below
    // every frame, so the cache never introduces a lighting step.
    const nightBucket = 0;
    if (nightBucket != _bodyNight) {
      _clearBodies();
      _bodyNight = nightBucket;
    }
    final slot = (near ? 7 : 0) + nightBucket;
    const tint = SceneGrade.identity;
    final body = _bodies[slot] ??= _bakeBodies(bushes, spec, tint);
    final n = bushes.fold(0, (a, b) => a + b.leaves.length);
    final transforms = Float32List(n * 4);
    final rects = Float32List(n * 4);
    final colors = Int32List(n);
    final alpha = (reveal * 255).round().clamp(0, 255);
    final windy = m.wind.abs() + m.windTell * .5;
    var i = 0;
    // Bodies: all bushes of the slot share one picture; each bush's shear
    // is applied by drawing the picture clipped to that bush. Cheaper: the
    // picture holds every bush at rest and a single mean shear leans them
    // together, while the leaves carry the per-bush motion.
    var meanShear = 0.0;
    for (final b in bushes) {
      meanShear += bushShear(b, m);
    }
    meanShear /= bushes.length;
    c.save();
    c.translate(breath.dx, breath.dy + 356);
    c.skew(meanShear, 0);
    c.translate(0, -356);
    _paint
      ..color = ui.Color.fromRGBO(255, 255, 255, reveal)
      ..colorFilter = grade
      ..blendMode = ui.BlendMode.srcOver;
    c.saveLayer(null, _paint);
    c.drawPicture(body);
    c.restore();
    c.restore();
    for (final b in bushes) {
      final shear = bushShear(b, m);
      final hz = b.near ? largeFlutterHz : smallFlutterHz;
      for (final leaf in b.leaves) {
        final up = -leaf.dy * b.scale;
        final flutter = reducedMotion
            ? 0.0
            : math.sin(m.ambientTime * hz * math.pi * .5 + leaf.phase) *
                  (.04 + .12 * windy) *
                  m.foliageMotion;
        _instance(
          transforms,
          rects,
          colors,
          i++,
          atlas,
          row: b.near ? 0 : 1,
          column: leaf.column,
          x: b.x + leaf.dx * b.scale + up * shear + breath.dx,
          y: b.y - up + breath.dy,
          rotation: leaf.rotation + flutter + shear * .5,
          scale: b.scale / atlas.scale,
          alpha: alpha,
        );
      }
    }
    _drawAtlas(c, atlas, transforms, rects, colors, i, grade);
    if (spec.glowFlecks) _flecks(c, m, bushes, reveal, night, breath);
  }

  ui.Picture _bakeBodies(
    List<Bush> bushes,
    FoliageSpec spec,
    List<double> tint,
  ) {
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    final body = _shade(spec.bushBody, tint);
    final upper = _shade(spec.bushPalette[0], tint);
    final rim = _shade(spec.bushPalette[1], tint);
    final stem = _shade(spec.bark, tint);
    for (final b in bushes) {
      // Two stacked blobs and a lighter crown row, scanline ovals.
      _oval(c, b.x, b.y - b.ry * b.scale, b.rx * b.scale, b.ry * b.scale, body);
      _oval(
        c,
        b.x - b.rx * .15 * b.scale,
        b.y - b.ry * 1.5 * b.scale,
        b.rx * .7 * b.scale,
        b.ry * .8 * b.scale,
        upper,
      );
      _oval(
        c,
        b.x - b.rx * .2 * b.scale,
        b.y - b.ry * 1.9 * b.scale,
        b.rx * .4 * b.scale,
        1.5,
        rim,
      );
      if (b.near) {
        for (var s = -1; s <= 1; s++) {
          _rect(c, b.x + s * b.rx * .3, b.y - 3, 1, 3, stem);
        }
      }
    }
    return recorder.endRecording();
  }

  /// Glow-moss flecks on grotto bushes: additive, pulsing, lit by night.
  void _flecks(
    ui.Canvas c,
    PondModel m,
    List<Bush> bushes,
    double reveal,
    double night,
    ui.Offset breath,
  ) {
    final color = m.biome == 'crystal_grotto' ? 0xffc68cff : 0xff5ef2e8;
    _paint
      ..blendMode = ui.BlendMode.plus
      ..colorFilter = null;
    var i = 0;
    for (final b in bushes) {
      for (var k = 0; k < 3; k++) {
        final leaf = b.leaves[(k * 5) % b.leaves.length];
        final pulse = reducedMotion
            ? .7
            : .5 + .5 * math.sin(m.time * 1.3 + i * 1.9);
        final a = reveal * (.15 + night * .45) * pulse;
        final x = (b.x + leaf.dx * b.scale + breath.dx).roundToDouble();
        final y = (b.y + leaf.dy * b.scale + breath.dy).roundToDouble();
        _paint.color = ui.Color(color).withValues(alpha: a * .35);
        c.drawRect(ui.Rect.fromLTWH(x - 2, y - 1, 5, 3), _paint);
        _paint.color = const ui.Color(0xffffffff).withValues(alpha: a);
        c.drawRect(ui.Rect.fromLTWH(x, y, 1, 1), _paint);
        i++;
      }
    }
    _paint.blendMode = ui.BlendMode.srcOver;
  }

  void _instance(
    Float32List transforms,
    Float32List rects,
    Int32List colors,
    int i,
    LeafAtlas atlas, {
    required int row,
    required int column,
    required double x,
    required double y,
    required double rotation,
    required double scale,
    required int alpha,
  }) {
    final src = atlas.rect(row, column);
    final half = src.width * .5;
    // Continuous transforms let a small breeze move through subpixel steps.
    final q = rotation;
    final scos = math.cos(q) * scale;
    final ssin = math.sin(q) * scale;
    // Keep the cell centre continuous; texture filtering handles fractional
    // positions without a whole-pixel/15-degree pop.
    final tx = x - scos * half + ssin * half;
    final ty = y - ssin * half - scos * half;
    final t = i * 4;
    transforms[t] = scos;
    transforms[t + 1] = ssin;
    transforms[t + 2] = tx;
    transforms[t + 3] = ty;
    rects[t] = src.left;
    rects[t + 1] = src.top;
    rects[t + 2] = src.right;
    rects[t + 3] = src.bottom;
    colors[i] = (alpha << 24) | 0xffffff;
  }

  void _drawAtlas(
    ui.Canvas c,
    LeafAtlas atlas,
    Float32List transforms,
    Float32List rects,
    Int32List colors,
    int count,
    ui.ColorFilter? grade,
  ) {
    if (count == 0) return;
    _paint
      ..color = const ui.Color(0xffffffff)
      ..filterQuality = ui.FilterQuality.low
      ..colorFilter = grade
      ..blendMode = ui.BlendMode.srcOver;
    c.drawRawAtlas(
      atlas.image,
      count * 4 == transforms.length
          ? transforms
          : Float32List.sublistView(transforms, 0, count * 4),
      count * 4 == rects.length
          ? rects
          : Float32List.sublistView(rects, 0, count * 4),
      count == colors.length ? colors : Int32List.sublistView(colors, 0, count),
      ui.BlendMode.modulate,
      null,
      _paint,
    );
    _paint.colorFilter = null;
  }

  // --- helpers ---

  static int _lighten(int color) {
    int ch(int shift) => math.min(255, ((color >> shift) & 0xff) + 38) << shift;
    return 0xff000000 | ch(16) | ch(8) | ch(0);
  }

  static int _shade(int color, List<double> tint) {
    final (r, g, b) = SceneGrade.apply(tint, (
      ((color >> 16) & 0xff).toDouble(),
      ((color >> 8) & 0xff).toDouble(),
      (color & 0xff).toDouble(),
    ));
    return 0xff000000 | (r.round() << 16) | (g.round() << 8) | b.round();
  }

  void _rect(ui.Canvas c, double x, double y, double w, double h, int color) {
    if (w <= 0 || h <= 0) return;
    _paint
      ..color = ui.Color(color)
      ..colorFilter = null
      ..blendMode = ui.BlendMode.srcOver;
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

  void _oval(ui.Canvas c, double x, double y, double rx, double ry, int color) {
    for (var row = -ry.floor(); row <= ry.floor(); row++) {
      final span = rx * math.sqrt(math.max(0, 1 - row * row / (ry * ry)));
      _rect(c, x - span, y + row, span * 2, 1, color);
    }
  }

  void dispose() {
    _clearBodies();
    if (_atlas != null && _atlas!.image != paintedAtlas) {
      _atlas!.image.dispose();
    }
    _atlas = null;
    _atlasBiome = null;
    _model = null;
    _modelKey = null;
  }
}
