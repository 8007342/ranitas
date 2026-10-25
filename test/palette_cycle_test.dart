import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/palette_cycle.dart';
import 'package:ranitas/game/pond_model.dart';

Future<ui.Image> _grayImage(
  int width,
  int height,
  int Function(int x, int y) gray,
) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final g = gray(x, y);
      pixels[i] = g;
      pixels[i + 1] = g;
      pixels[i + 2] = g;
      pixels[i + 3] = 255;
    }
  }
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

Future<Uint8List> _rasterise(void Function(ui.Canvas c) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(641, 359);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a partly revealed cycle keeps constant opacity across its wrap', () async {
    final cycle = await PaletteCycle.bake(CycleSpec(
      id: 'fade-regression', rect: const ui.Rect.fromLTWH(0, 0, 4, 4),
      ramp: const [0xff204080, 0xff80a0c0], fps: 1,
      generator: (w, h, slots, seed) => Uint8List.fromList(List.filled(w * h, 1)),
    ));
    final alphas = <int>[];
    for (final t in [0.0, .5, .9999, 1.0, 1.9999, 2.0]) {
      final recorder = ui.PictureRecorder();
      cycle.draw(ui.Canvas(recorder), t, strength: .3);
      final picture = recorder.endRecording(), image = await picture.toImage(4, 4);
      final pixels = (await image.toByteData())!.buffer.asUint8List();
      alphas.add(pixels[3]);
      image.dispose(); picture.dispose();
    }
    for (final alpha in alphas) { expect(alpha, inInclusiveRange(75, 77)); }
    cycle.dispose();
  });

  const spec = CycleSpec(
    id: 'test',
    rect: ui.Rect.fromLTWH(100, 50, 8, 12),
    ramp: [0xff102030, 0xff405060, 0xff708090, 0xffa0b0c0, 0xffd0e0f0],
    generator: _solid,
    fps: 6,
  );

  test(
    'frame index walks every shift once and returns after N frames',
    () async {
      final cycle = await PaletteCycle.bake(spec);
      expect(cycle.frameCount, 5);
      expect(cycle.period, closeTo(5 / 6, 1e-9));
      final seen = <int>{};
      for (var k = 0; k < cycle.frameCount; k++) {
        seen.add(cycle.frameIndex((k + .5) / spec.fps));
      }
      expect(seen, {0, 1, 2, 3, 4});
      for (final t in [0.0, .3, 1.7, 12.25, 100.01]) {
        expect(cycle.frameIndex(t + cycle.period), cycle.frameIndex(t));
        expect(cycle.frameIndex(t + cycle.period * 3), cycle.frameIndex(t));
        expect(cycle.frameFraction(t), inInclusiveRange(0, 1));
      }
      expect(cycle.frameIndex(0), 0);
      expect(cycle.frameIndex(cycle.period - 1e-6), cycle.frameCount - 1);
      cycle.dispose();
    },
  );

  test('reduced motion freezes on the first frame with no blending', () async {
    final cycle = await PaletteCycle.bake(spec);
    for (final t in [0.0, .4, 3.0, 77.7]) {
      expect(cycle.frameIndex(t, reducedMotion: true), 0);
      expect(cycle.frameFraction(t, reducedMotion: true), 0);
    }
    cycle.dispose();
  });

  test('stepping regions never blend', () async {
    final stepped = CycleSpec(
      id: 'step',
      rect: spec.rect,
      ramp: spec.ramp,
      generator: _solid,
      fps: 4,
      blend: false,
    );
    final cycle = await PaletteCycle.bake(stepped);
    expect(cycle.frameFraction(.37), 0);
    cycle.dispose();
  });

  test('procedural generators stay inside the slot range', () {
    for (final generator in [
      IndexMaps.fallingWater(),
      IndexMaps.fallingWater(density: .4, stretch: 2.2),
      IndexMaps.rippleBands(),
      IndexMaps.radialPulse(),
      IndexMaps.glints(),
      IndexMaps.glints(density: .03, maxLength: 6),
    ]) {
      final map = generator(40, 30, 6, 9);
      expect(map.length, 40 * 30);
      expect(map.every((s) => s >= 0 && s <= 6), isTrue);
      expect(map.any((s) => s > 0), isTrue);
    }
    final halo = IndexMaps.radialPulse()(40, 40, 8, 1);
    expect(halo[0], 0, reason: 'halo corners stay transparent');
    expect(halo[20 * 40 + 20], greaterThan(0), reason: 'halo centre is lit');
    // Glints are sparse: most of the water shows through.
    final glints = IndexMaps.glints(density: .04)(200, 40, 8, 3);
    final lit = glints.where((s) => s > 0).length;
    expect(lit, inInclusiveRange(200 * 40 ~/ 40, 200 * 40 ~/ 4));
    expect(glints, equals(IndexMaps.glints(density: .04)(200, 40, 8, 3)));
  });

  test('every region of every backdrop is in frame and periodic', () async {
    final seen = <String>{};
    for (final biome in PondModel.biomes) {
      final probe = PondModel(seed: 0)..biome = biome;
      if (!seen.add(probe.backdropAsset)) continue;
      final specs = PaletteCycles.specsFor(probe.backdropAsset);
      expect(specs, isNotEmpty, reason: probe.backdropAsset);
      final ids = specs.map((s) => s.id).toSet();
      expect(ids.length, specs.length, reason: 'duplicate ids in $biome');
      for (final spec in specs) {
        expect(spec.rect.left, greaterThanOrEqualTo(0), reason: spec.id);
        expect(spec.rect.top, greaterThanOrEqualTo(0), reason: spec.id);
        expect(spec.rect.right, lessThanOrEqualTo(641), reason: spec.id);
        expect(spec.rect.bottom, lessThanOrEqualTo(359), reason: spec.id);
        expect(spec.ramp.length, inInclusiveRange(2, 15));
        expect(spec.fps, greaterThan(0));
        if (spec.additive) {
          expect(
            spec.ramp.any((c) => (c >> 24) & 0xff > 0),
            isTrue,
            reason: '${spec.id} additive ramp carries alpha',
          );
        }
        final cycle = await PaletteCycle.bake(spec);
        expect(cycle.frameCount, spec.slots);
        for (final t in [0.0, .7, 5.3, 61.1]) {
          expect(
            cycle.frameIndex(t + cycle.period),
            cycle.frameIndex(t),
            reason: '${spec.id} period',
          );
          expect(cycle.frameIndex(t, reducedMotion: true), 0);
        }
        cycle.dispose();
      }
    }
    expect(seen, hasLength(12));
  });

  test('painted index maps decode slot = round(gray / 16)', () async {
    final image = await _grayImage(641, 359, (x, y) {
      if (x < 100 || x >= 108 || y < 50 || y >= 62) return 0;
      return (x - 100 + 1) * 16;
    });
    final map = await IndexMaps.fromPainted(image, spec.rect, 5);
    expect(map, isNotNull);
    expect(map![0], 1);
    expect(map[3], 4);
    expect(map[7], 5, reason: 'gray above the ramp clamps to the last slot');
    final cycle = await PaletteCycle.bake(spec, painted: image);
    image.dispose();
    expect(cycle.frameCount, 5);
    cycle.dispose();
  });

  test('pixels outside the region are unchanged by the cycle', () async {
    final cycles = <PaletteCycle>[];
    for (final s in PaletteCycles.specsFor('pond-blossom.webp')) {
      cycles.add(await PaletteCycle.bake(s));
    }
    expect(cycles, isNotEmpty);
    final union = cycles
        .map((c) => c.spec.rect)
        .reduce((a, b) => a.expandToInclude(b));
    final before = await _rasterise((c) {
      c.drawRect(
        const ui.Rect.fromLTWH(0, 0, 641, 359),
        ui.Paint()..color = const ui.Color(0xff336699),
      );
    });
    final after = await _rasterise((c) {
      c.drawRect(
        const ui.Rect.fromLTWH(0, 0, 641, 359),
        ui.Paint()..color = const ui.Color(0xff336699),
      );
      for (final cycle in cycles) {
        cycle.draw(c, .37);
      }
    });
    var changedInside = 0;
    for (var y = 0; y < 359; y++) {
      for (var x = 0; x < 641; x++) {
        final i = (y * 641 + x) * 4;
        final same =
            before[i] == after[i] &&
            before[i + 1] == after[i + 1] &&
            before[i + 2] == after[i + 2];
        if (union.contains(ui.Offset(x + .5, y + .5))) {
          if (!same) changedInside++;
        } else {
          expect(
            same,
            isTrue,
            reason: 'pixel ($x,$y) outside the regions changed',
          );
        }
      }
    }
    expect(changedInside, greaterThan(50));
    for (final cycle in cycles) {
      cycle.dispose();
    }
  });

  test('every backdrop with a water feature or glow has regions', () {
    final withRegions = <String>{};
    for (final biome in PondModel.biomes) {
      final probe = PondModel(seed: 0)..biome = biome;
      if (PaletteCycles.specsFor(probe.backdropAsset).isNotEmpty) {
        withRegions.add(biome);
      }
    }
    expect(
      withRegions,
      containsAll([
        'blossom',
        'lotus',
        'alpine',
        'grotto',
        'crystal_grotto',
        'sanctuary',
        'jade_sanctuary',
      ]),
    );
    // Every backdrop now glints, twinkles or glows somewhere.
    expect(withRegions, PondModel.biomes.toSet());
    final grotto = PaletteCycles.specsFor('pond-grotto.webp');
    expect(
      grotto.where((s) => s.id.startsWith('cap-') || s.id.startsWith('fungi')),
      hasLength(12),
      reason: 'twelve painted fungus clusters glow',
    );
    expect(grotto.map((s) => s.id), containsAll(['shimmer', 'moon']));
    for (final spec in grotto) {
      expect(spec.rect.left, greaterThanOrEqualTo(0));
      expect(spec.rect.right, lessThanOrEqualTo(641));
      expect(spec.rect.bottom, lessThanOrEqualTo(359));
      expect(spec.ramp.length, inInclusiveRange(2, 15));
    }
    // Stars and glows are emissive (ungraded); water glitter is graded.
    final blossom = PaletteCycles.specsFor('pond-blossom.webp');
    expect(blossom.firstWhere((s) => s.id == 'star').emissive, isTrue);
    expect(blossom.firstWhere((s) => s.id == 'glitter').emissive, isFalse);
    expect(blossom.firstWhere((s) => s.id == 'glitter').additive, isTrue);
  });
}

Uint8List _solid(int width, int height, int slots, int seed) {
  final map = Uint8List(width * height);
  for (var i = 0; i < map.length; i++) {
    map[i] = 1 + (i % slots);
  }
  return map;
}
