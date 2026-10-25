import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/cache.dart';

import 'optional_assets.dart';

/// Builds an index map for a `width × height` region: 0 is transparent and
/// 1..[slots] select a ramp entry.
typedef IndexMapGenerator = Uint8List Function(
  int width,
  int height,
  int slots,
  int seed,
);

/// Procedural index-map generators for the 1990s palette-cycling regions
/// (design D4). Each returns a row-major `Uint8List` of slots.
class IndexMaps {
  IndexMaps._();

  static double _hash(int seed, int a, [int b = 0]) {
    var h = (seed * 374761393 + a * 668265263 + b * 2246822519) & 0x7fffffff;
    h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
    return ((h ^ (h >> 16)) & 0xffff) / 0xffff;
  }

  /// Water falling down the region: every column is a streak whose ramp phase
  /// is offset by per-column noise. Columns with noise above [density] stay
  /// transparent, which turns a solid sheet into sparse seep streaks. [stretch]
  /// is the number of rows one ramp pass spans.
  static IndexMapGenerator fallingWater({
    double density = 1,
    double stretch = 1.6,
  }) => (width, height, slots, seed) {
    final map = Uint8List(width * height);
    for (var x = 0; x < width; x++) {
      if (_hash(seed, x, 7) > density) continue;
      final phase = _hash(seed, x, 3) * slots;
      final speed = .85 + _hash(seed, x, 11) * .3;
      final top = (_hash(seed, x, 5) * height * .25).floor();
      for (var y = top; y < height; y++) {
        final slot = ((y / stretch) * speed + phase).floor() % slots;
        map[y * width + x] = 1 + slot;
      }
    }
    return map;
  };

  /// Ripple bands flowing along x, as on a shallow stream or a lapping shore.
  static IndexMapGenerator rippleBands({double wavelength = 7}) =>
      (width, height, slots, seed) {
        final map = Uint8List(width * height);
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            final wobble =
                math.sin(x * .21 + y * 1.3 + seed) * 1.2 +
                math.sin(x * .05 - y * .7) * .8;
            final slot =
                ((x / wavelength + y * .9 + wobble) % slots + slots).floor() %
                slots;
            map[y * width + x] = 1 + slot;
          }
        }
        return map;
      };

  /// A dithered radial halo whose ramp slot grows with radius, so cycling the
  /// ramp sends rings outward. Pixels drop out toward the rim so the halo fades.
  static IndexMapGenerator radialPulse({
    double cx = .5,
    double cy = .5,
    double rings = 1.5,
  }) => (width, height, slots, seed) {
    final map = Uint8List(width * height);
    final rx = width * .5;
    final ry = height * .5;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = (x + .5 - width * cx) / rx;
        final dy = (y + .5 - height * cy) / ry;
        final r = math.sqrt(dx * dx + dy * dy);
        if (r >= 1) continue;
        final keep = (1 - r) * (1 - r);
        if (_hash(seed, x, y) > keep) continue;
        final slot = (r * rings * slots).floor() % slots;
        map[y * width + x] = 1 + slot;
      }
    }
    return map;
  };

  /// Decodes a painted grayscale map (`cycle-<backdrop>-<region>.webp`, full
  /// logical frame) into slots for [rect]: `slot = round(gray / 16)`.
  static Future<Uint8List?> fromPainted(
    ui.Image image,
    ui.Rect rect,
    int slots,
  ) async {
    ByteData? data;
    try {
      data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } catch (_) {
      return null;
    }
    if (data == null) return null;
    final width = rect.width.round();
    final height = rect.height.round();
    final sx = image.width / 641;
    final sy = image.height / 359;
    final map = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final py = ((rect.top + y) * sy).floor().clamp(0, image.height - 1);
      for (var x = 0; x < width; x++) {
        final px = ((rect.left + x) * sx).floor().clamp(0, image.width - 1);
        final gray = data.getUint8((py * image.width + px) * 4);
        map[y * width + x] = (gray / 16).round().clamp(0, slots);
      }
    }
    return map;
  }
}

/// A cycle region: a logical-space rectangle, a colour ramp and how it moves.
class CycleSpec {
  const CycleSpec({
    required this.id,
    required this.rect,
    required this.ramp,
    required this.generator,
    this.fps = 8,
    this.blend = true,
    this.emissive = false,
    this.additive = false,
    this.seed = 1,
  });

  /// Region name, also the suffix of its painted index map.
  final String id;

  /// Logical 641 × 359 rectangle the index map covers.
  final ui.Rect rect;

  /// ARGB ramp; its length is the number of slots and frames.
  final List<int> ramp;
  final IndexMapGenerator generator;

  /// Ramp shifts per second.
  final double fps;

  /// Cross-fade to the next shift (Ferrari) instead of stepping hard (8-bit).
  /// By material: water and bioluminescence flow smoothly (true); fire
  /// flickers in hard steps (false).
  final bool blend;

  /// The region is a light source; the grade pass may keep it lit at night.
  final bool emissive;

  /// Draw with `BlendMode.plus` (halos) instead of replacing pixels.
  final bool additive;
  final int seed;

  int get slots => ramp.length;
}

/// Frames baked from a [CycleSpec]: frame `k` is the index map painted with
/// the ramp rotated by `k`. Drawing picks `floor(t·fps) mod N`.
class PaletteCycle {
  PaletteCycle._(this.spec, this.frames);

  final CycleSpec spec;
  final List<ui.Image> frames;
  final ui.Paint _paint = ui.Paint()
    ..isAntiAlias = false
    ..filterQuality = ui.FilterQuality.none;

  int get frameCount => frames.length;

  /// Period in seconds after which the frame index repeats.
  double get period => frameCount / spec.fps;

  int frameIndex(double t, {bool reducedMotion = false}) {
    if (reducedMotion || frameCount == 0) return 0;
    final index = (t * spec.fps).floor() % frameCount;
    return index < 0 ? index + frameCount : index;
  }

  /// Fraction of the way from the current frame to the next, for blending.
  double frameFraction(double t, {bool reducedMotion = false}) {
    if (reducedMotion || !spec.blend) return 0;
    final phase = t * spec.fps;
    return phase - phase.floorToDouble();
  }

  void draw(
    ui.Canvas canvas,
    double t, {
    bool reducedMotion = false,
    double strength = 1,
    ui.ColorFilter? grade,
  }) {
    if (frames.isEmpty || strength <= 0) return;
    // Painted water darkens with the scene; emissive glows keep their light.
    _paint.colorFilter = spec.emissive ? null : grade;
    final k = frameIndex(t, reducedMotion: reducedMotion);
    final f = frameFraction(t, reducedMotion: reducedMotion);
    _paint.blendMode = spec.additive ? ui.BlendMode.plus : ui.BlendMode.srcOver;
    final firstAlpha = spec.additive ? (1 - f) * strength : strength;
    _drawFrame(canvas, frames[k], firstAlpha);
    if (f > 0) {
      _drawFrame(canvas, frames[(k + 1) % frameCount], f * strength);
    }
  }

  void _drawFrame(ui.Canvas canvas, ui.Image image, double alpha) {
    if (alpha <= 0) return;
    _paint.color = ui.Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      spec.rect,
      _paint,
    );
  }

  void dispose() {
    for (final frame in frames) {
      frame.dispose();
    }
    frames.clear();
  }

  /// Bakes the frames for [spec] from a procedural index map, or from a
  /// painted map [painted] when it decodes.
  static Future<PaletteCycle> bake(CycleSpec spec, {ui.Image? painted}) async {
    final width = spec.rect.width.round();
    final height = spec.rect.height.round();
    final slots = spec.slots;
    Uint8List? map;
    if (painted != null) {
      map = await IndexMaps.fromPainted(painted, spec.rect, slots);
    }
    map ??= spec.generator(width, height, slots, spec.seed);
    final frames = <ui.Image>[];
    for (var shift = 0; shift < slots; shift++) {
      final pixels = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        final slot = map[i];
        if (slot == 0) continue;
        final color = spec.ramp[(slot - 1 + shift) % slots];
        final a = (color >> 24) & 0xff;
        final r = (color >> 16) & 0xff;
        final g = (color >> 8) & 0xff;
        final b = color & 0xff;
        // Premultiplied RGBA as the pixel decoder expects.
        pixels[i * 4] = r * a ~/ 255;
        pixels[i * 4 + 1] = g * a ~/ 255;
        pixels[i * 4 + 2] = b * a ~/ 255;
        pixels[i * 4 + 3] = a;
      }
      frames.add(await _imageFromPixels(pixels, width, height));
    }
    return PaletteCycle._(spec, frames);
  }

  static Future<ui.Image> _imageFromPixels(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

/// The region table per backdrop, with ramps sampled from the painted art.
/// Coordinates are logical (641 × 359); the sources are 1376 × 768.
class PaletteCycles {
  PaletteCycles._();

  // Blossom cliffside waterfall: main sheet x 381–387, y 150–168; a thin
  // strand at x 377–379; its reflection x 382–389, y 169–184.
  static const _blossomFall = [
    0xffa6d1e8,
    0xff8fc5df,
    0xff66abc9,
    0xff5997b7,
    0xff7fbbd6,
    0xffe8f6fb,
  ];
  static const _blossomReflection = [
    0xff326c97,
    0xff5390b4,
    0xff81acd4,
    0xff5390b4,
    0xff3f7aa4,
  ];
  static const _lotusFall = [
    0xffb4d7aa,
    0xff9ccba2,
    0xff7dc39c,
    0xff6fae90,
    0xff92c7a4,
    0xffdff3e6,
  ];
  static const _lotusReflection = [
    0xff3c4c54,
    0xff67877c,
    0xff8aa89a,
    0xff67877c,
    0xff4b5f62,
  ];
  // Alpine tarn edge x 200–440, y 186–190 (dark teal under the far shore).
  static const _alpineStream = [
    0xff096a70,
    0xff0b7a80,
    0xff1a9aa0,
    0xff3fc4c4,
    0xff1a9aa0,
    0xff0b7a80,
  ];
  // Grotto seep down the right wall x 572–594, y 98–162.
  static const _grottoSeep = [
    0xff4f778c,
    0xff568aa1,
    0xff6cbdd7,
    0xffbfffff,
    0xff6cbdd7,
    0xff568aa1,
    0xff4f778c,
    0xff374f50,
  ];
  static const _crystalSeep = [
    0xff6468a3,
    0xff9a7cc4,
    0xffda63b9,
    0xffffe0f6,
    0xffda63b9,
    0xff9a7cc4,
    0xff6468a3,
    0xff454159,
  ];

  /// Additive glow ramps carry alpha; one bright ring per pass.
  static List<int> _glow(int rgb, double peak) => List.generate(8, (k) {
    final a = ((.5 - .5 * math.cos(k / 8 * math.pi * 2)) * peak * 255).round();
    return (a << 24) | (rgb & 0xffffff);
  });

  static List<CycleSpec> specsFor(String backdropAsset) {
    final stem = OptionalAssets.backdropStem(backdropAsset);
    switch (stem) {
      case 'pond-blossom':
      case 'pond-lotus':
        final lotus = stem == 'pond-lotus';
        return [
          CycleSpec(
            id: 'waterfall',
            rect: const ui.Rect.fromLTWH(381, 150, 6, 18),
            ramp: lotus ? _lotusFall : _blossomFall,
            generator: IndexMaps.fallingWater(stretch: 1.4),
            fps: 9,
            seed: 11,
          ),
          CycleSpec(
            id: 'waterfall-strand',
            rect: const ui.Rect.fromLTWH(377, 153, 2, 14),
            ramp: lotus ? _lotusFall : _blossomFall,
            generator: IndexMaps.fallingWater(stretch: 1.4),
            fps: 9,
            seed: 12,
          ),
          CycleSpec(
            id: 'reflection',
            rect: const ui.Rect.fromLTWH(382, 169, 7, 15),
            ramp: lotus ? _lotusReflection : _blossomReflection,
            generator: IndexMaps.rippleBands(wavelength: 4),
            fps: 3,
            seed: 13,
          ),
        ];
      case 'pond-alpine':
        return [
          CycleSpec(
            id: 'stream',
            rect: const ui.Rect.fromLTWH(200, 186, 240, 4),
            ramp: _alpineStream,
            generator: IndexMaps.rippleBands(wavelength: 9),
            fps: 4,
            seed: 21,
          ),
        ];
      case 'pond-grotto':
      case 'pond-crystal-grotto':
        final crystal = stem == 'pond-crystal-grotto';
        return [
          CycleSpec(
            id: 'seep',
            rect: const ui.Rect.fromLTWH(572, 98, 22, 64),
            ramp: crystal ? _crystalSeep : _grottoSeep,
            generator: IndexMaps.fallingWater(density: .4, stretch: 2.2),
            fps: 6,
            seed: 31,
          ),
          // Left fungi cluster centred near (37, 230); right near (597, 213).
          CycleSpec(
            id: 'fungi',
            rect: const ui.Rect.fromLTWH(6, 206, 62, 50),
            ramp: _glow(crystal ? 0xf624eb : 0x1de5e7, .34),
            generator: IndexMaps.radialPulse(cy: .48),
            fps: 2.5,
            emissive: true,
            additive: true,
            seed: 32,
          ),
          CycleSpec(
            id: 'fungi-right',
            rect: const ui.Rect.fromLTWH(564, 190, 66, 46),
            ramp: _glow(crystal ? 0xfd8f74 : 0xe2b66a, .3),
            generator: IndexMaps.radialPulse(),
            fps: 2.2,
            emissive: true,
            additive: true,
            seed: 33,
          ),
        ];
      case 'pond-sanctuary':
      case 'pond-jade-sanctuary':
        final jade = stem == 'pond-jade-sanctuary';
        // Stone lantern windows x 92–131, y 158–177, glow centred (112, 168).
        return [
          CycleSpec(
            id: 'lantern',
            rect: const ui.Rect.fromLTWH(88, 152, 48, 32),
            ramp: _glow(jade ? 0xffe15c : 0xf0bb59, .36),
            generator: IndexMaps.radialPulse(rings: 1),
            // Candle flame: hard-stepped flicker, unlike the flowing water.
            fps: 7,
            blend: false,
            emissive: true,
            additive: true,
            seed: 41,
          ),
        ];
      default:
        return const [];
    }
  }

  /// Bakes every region of [backdropAsset], preferring painted index maps
  /// from [images] when they exist.
  static Future<List<PaletteCycle>> load(
    String backdropAsset,
    Images images,
  ) async {
    final cycles = <PaletteCycle>[];
    for (final spec in specsFor(backdropAsset)) {
      final painted = await OptionalAssets.load(
        images,
        OptionalAssets.cycleIndex(backdropAsset, spec.id),
      );
      cycles.add(await PaletteCycle.bake(spec, painted: painted));
    }
    return cycles;
  }
}
