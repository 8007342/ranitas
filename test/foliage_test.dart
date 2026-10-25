import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/foliage.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/scene_layers.dart';

PondModel _modelFor(String biome, {int seed = 3}) {
  for (var s = seed; s < seed + 400; s++) {
    final probe = PondModel(seed: s, durationOverride: 10);
    if (probe.biome == biome) return probe;
  }
  fail('no seed for $biome');
}

bool _inLane(double x, double y) =>
    x > SceneLayers.laneLeft &&
    x < SceneLayers.laneRight &&
    y > SceneLayers.laneTop;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every biome has a foliage spec with branches and bushes', () {
    for (final biome in PondModel.biomes) {
      final spec = FoliageSpec.forBiome(biome);
      expect(spec.branchPalette, hasLength(4), reason: biome);
      expect(spec.bushPalette, hasLength(4), reason: biome);
      expect(spec.branchesPerSide, inInclusiveRange(1, 3));
      final model = FoliageGeometry.build(spec, 7, WaterBasin.forBiome(biome));
      expect(model.branches.length, spec.branchesPerSide * 2, reason: biome);
      expect(model.nearBushes, isNotEmpty, reason: biome);
      expect(model.midBushes, isNotEmpty, reason: biome);
      for (final b in model.branches) {
        expect(b.clusters, isNotEmpty);
        for (final k in b.clusters) {
          expect(k.segment, inInclusiveRange(0, b.segments - 1));
        }
      }
    }
  });

  test('branches keep the central lane clear at every lean, by reach bound and by pose', () {
    const breath = SceneLayerPainter.breathAmplitude + .5;
    const m = FoliageGeometry.maxLean;
    final poses = <List<double> Function(int)>[
      (n) => List.filled(n, m),
      (n) => List.filled(n, -m),
      (n) => List.generate(n, (k) => k.isEven ? m : -m),
      (n) => List.generate(n, (k) => k.isEven ? -m : m),
      (n) => List.generate(n, (k) => m * (k + 1) / n),
      (n) => List.generate(n, (k) => -m * (k + 1) / n),
      (n) => List.filled(n, 0),
    ];
    for (final biome in PondModel.biomes) {
      final spec = FoliageSpec.forBiome(biome);
      for (final seed in [0, 1, 42, 1234, 99991]) {
        final model = FoliageGeometry.build(
          spec,
          seed,
          WaterBasin.forBiome(biome),
        );
        for (final b in model.branches) {
          // The reach bound alone keeps the root's side quarter.
          final limit =
              SceneLayers.laneLeft - FoliageGeometry.sideMargin - breath;
          final inward = b.right ? 641 - b.rootX : b.rootX;
          expect(
            inward + b.reach,
            lessThanOrEqualTo(limit + breath),
            reason: '$biome seed $seed: reach ${b.reach} from $inward',
          );
          for (final pose in poses) {
            final leans = pose(b.segments);
            final joints = b.joints(leans);
            for (final p in joints) {
              for (final dx in [-breath, breath]) {
                expect(
                  _inLane(p.dx + dx, p.dy + b.thickness + 1),
                  isFalse,
                  reason: '$biome seed $seed: joint $p enters the lane',
                );
              }
            }
            for (final k in b.clusters) {
              final a = joints[k.segment];
              final z = joints[k.segment + 1];
              final x = a.dx + (z.dx - a.dx) * k.t;
              final y = a.dy + (z.dy - a.dy) * k.t;
              for (final dx in [-k.radius - breath, k.radius + breath]) {
                expect(
                  _inLane(x + dx, y + k.radius + 1),
                  isFalse,
                  reason: '$biome seed $seed: leaf pack enters the lane',
                );
              }
            }
          }
        }
      }
    }
  });

  test('bushes stay out of the central water lane and the basin', () {
    for (final biome in PondModel.biomes) {
      final basin = WaterBasin.forBiome(biome);
      for (final seed in [0, 5, 77, 4242]) {
        final model = FoliageGeometry.build(
          FoliageSpec.forBiome(biome),
          seed,
          basin,
        );
        for (final b in model.nearBushes) {
          final inner = b.x < 320 ? b.x + b.rx : b.x - b.rx;
          expect(
            inner < 200 || inner > 441,
            isTrue,
            reason: '$biome seed $seed: near bush reaches the centre lane',
          );
          expect(b.y, greaterThan(340));
        }
        for (final b in model.midBushes) {
          final inner = b.x < 320 ? b.x + b.rx * b.scale : b.x - b.rx * b.scale;
          final edge = b.x < 320 ? basin.leftX(b.y) : basin.rightX(b.y);
          expect(
            b.x < 320 ? inner <= edge : inner >= edge,
            isTrue,
            reason: '$biome seed $seed: mid bush enters the basin',
          );
          expect(basin.contains(b.x, b.y), isFalse);
        }
      }
    }
  });

  test('the procedural atlas bakes the same bytes every time', () async {
    for (final biome in ['willow', 'blossom', 'maple', 'grotto', 'alpine']) {
      final spec = FoliageSpec.forBiome(biome);
      final a = LeafAtlas.pixelsFor(spec);
      final b = LeafAtlas.pixelsFor(spec);
      expect(a.length, LeafAtlas.width * LeafAtlas.height * 4);
      expect(a, equals(b), reason: biome);
      // Every cell has some opaque pixels and alpha is crisp (0 or 255).
      for (var row = 0; row < LeafAtlas.rows; row++) {
        for (var column = 0; column < LeafAtlas.columns; column++) {
          var lit = 0;
          for (var y = 0; y < LeafAtlas.cell; y++) {
            for (var x = 0; x < LeafAtlas.cell; x++) {
              final px = column * LeafAtlas.cell + x;
              final py = row * LeafAtlas.cell + y;
              final alpha = a[(py * LeafAtlas.width + px) * 4 + 3];
              expect(alpha == 0 || alpha == 255, isTrue);
              if (alpha == 255) lit++;
            }
          }
          expect(lit, greaterThan(3), reason: '$biome cell $row,$column');
        }
      }
      final atlas = await LeafAtlas.bake(spec);
      expect(atlas.image.width, LeafAtlas.width);
      expect(atlas.image.height, LeafAtlas.height);
      expect(atlas.scale, 1);
      atlas.image.dispose();
    }
    expect(
      LeafAtlas.pixelsFor(FoliageSpec.forBiome('maple')),
      isNot(equals(LeafAtlas.pixelsFor(FoliageSpec.forBiome('willow')))),
    );
  });

  test(
    'painted atlases must be a whole multiple of the 128 × 64 grid',
    () async {
      Future<ui.Image> image(int w, int h) async {
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          Uint8List(w * h * 4),
          w,
          h,
          ui.PixelFormat.rgba8888,
          c.complete,
        );
        return c.future;
      }

      final good = await image(256, 128);
      final atlas = LeafAtlas.fromPainted(good);
      expect(atlas, isNotNull);
      expect(atlas!.scale, 2);
      expect(atlas.rect(1, 2), const ui.Rect.fromLTWH(64, 32, 32, 32));
      final bad = await image(200, 100);
      expect(LeafAtlas.fromPainted(bad), isNull);
      good.dispose();
      bad.dispose();
    },
  );

  test(
    'leans follow the wind trace, stay bounded and freeze under reduced motion',
    () {
      final painter = FoliagePainter();
      final model = _modelFor('maple')..progress = 1;
      final spec = FoliageSpec.forBiome('maple');
      final foliage = painter.modelFor(model);
      final branch = foliage.branches.first;
      // Calm: only ambient sway, small.
      painter.observe(model);
      final calm = painter.leans(branch, model, spec);
      expect(calm.length, branch.segments);
      for (final l in calm) {
        expect(l.abs(), lessThan(.08));
      }
      // A gust: push a ramp of wind through the trace over a second.
      for (var i = 0; i <= 60; i++) {
        model.time += 1 / 60;
        model.wind = .8 * i / 60;
        painter.observe(model);
      }
      model.time += 1.5;
      painter.observe(model);
      final gust = painter.leans(branch, model, spec);
      expect(gust.last.abs(), greaterThan(calm.last.abs() + .1));
      for (final l in gust) {
        expect(l.abs(), lessThanOrEqualTo(FoliageGeometry.maxLean));
      }
      // The tip leans more than the root.
      expect(gust.last.abs(), greaterThan(gust.first.abs()));
      // Wind to the right shrinks the angle; to the left grows it.
      expect(gust.last, lessThan(0));
      for (var i = 0; i <= 60; i++) {
        model.time += 1 / 60;
        model.wind = -.8;
        painter.observe(model);
      }
      model.time += 1.5;
      painter.observe(model);
      expect(painter.leans(branch, model, spec).last, greaterThan(0));

      painter.reducedMotion = true;
      final frozenA = painter.leans(branch, model, spec);
      model.time += 7.3;
      model.wind = .8;
      painter.observe(model);
      final frozenB = painter.leans(branch, model, spec);
      expect(frozenA, everyElement(0));
      expect(frozenB, everyElement(0));
      expect(painter.bushShear(foliage.nearBushes.first, model), 0);
      painter.dispose();
    },
  );

  test('the wind trace interpolates and clips to its ends', () {
    final trace = WindTrace();
    expect(trace.at(1), 0);
    trace.push(0, 0);
    trace.push(1, 1);
    trace.push(2, 0);
    expect(trace.at(-1), 0);
    expect(trace.at(.5), closeTo(.5, 1e-9));
    expect(trace.at(1.25), closeTo(.75, 1e-9));
    expect(trace.at(9), 0);
    // Going back in time (a new model) resets the trace.
    trace.push(.5, 3);
    expect(trace.at(.5), 3);
    for (var i = 0; i < WindTrace.capacity * 2; i++) {
      trace.push(1.0 + i, i.toDouble());
    }
    expect(trace.at(1e9), WindTrace.capacity * 2 - 1);
  });

  test(
    'the painter renders every biome with and without a painted atlas',
    () async {
      for (final biome in PondModel.biomes) {
        final painter = SceneLayerPainter();
        final model = _modelFor(biome);
        model.press();
        model.release();
        model.update(6);
        model.wind = .5;
        expect(painter.foliage.ready, isFalse);
        // Not ready: draws nothing and does not throw.
        final before = ui.PictureRecorder();
        painter.drawSlot(ui.Canvas(before), LayerSlot.canopy, model, 1);
        before.endRecording().dispose();
        await painter.foliage.prepare(biome);
        expect(painter.foliage.ready, isTrue);
        for (final slot in LayerSlot.values) {
          final recorder = ui.PictureRecorder();
          painter.drawSlot(ui.Canvas(recorder), slot, model, 1);
          final picture = recorder.endRecording();
          final image = await picture.toImage(641, 359);
          expect(image.width, 641);
          image.dispose();
          picture.dispose();
        }
        painter.dispose();
      }
      // Painted overrides: a stand-in atlas and branch strip.
      Future<ui.Image> image(int w, int h) async {
        final c = Completer<ui.Image>();
        final px = Uint8List(w * h * 4);
        for (var i = 0; i < px.length; i += 4) {
          px[i] = 90;
          px[i + 1] = 160;
          px[i + 2] = 70;
          px[i + 3] = 255;
        }
        ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
        return c.future;
      }

      final atlas = await image(256, 128);
      final strip = await image(576, 32);
      final painter = SceneLayerPainter();
      painter.foliage.paintedAtlas = atlas;
      painter.foliage.branchStrip = strip;
      await painter.foliage.prepare('willow');
      expect(painter.foliage.atlas!.scale, 2);
      final model = _modelFor('willow')..progress = 1;
      model.press();
      model.release();
      model.update(6);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      painter.drawSlot(canvas, LayerSlot.canopy, model, 1);
      painter.drawSlot(canvas, LayerSlot.nearCorner, model, 1);
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(641, 359);
      expect(rendered.width, 641);
      rendered.dispose();
      picture.dispose();
      painter.dispose();
      atlas.dispose();
      strip.dispose();
    },
  );

  test('bush shear saturates and flips with the wind', () {
    final painter = FoliagePainter();
    final model = _modelFor('willow')..progress = 1;
    final bush = painter.modelFor(model).nearBushes.first;
    for (var i = 0; i <= 60; i++) {
      model.time += 1 / 60;
      model.wind = 5;
      painter.observe(model);
    }
    model.time += 1;
    painter.observe(model);
    expect(painter.bushShear(bush, model), closeTo(.3, 1e-9));
    for (var i = 0; i <= 60; i++) {
      model.time += 1 / 60;
      model.wind = -5;
      painter.observe(model);
    }
    model.time += 1;
    painter.observe(model);
    expect(painter.bushShear(bush, model), closeTo(-.3, 1e-9));
    painter.dispose();
  });
}
