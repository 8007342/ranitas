import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/palette_cycle.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/pond_renderer.dart';
import 'package:ranitas/game/scene_layers.dart';

/// A model forced into [biome] without hunting for a seed.
PondModel _modelFor(String biome, {int seed = 7}) {
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

  test('every biome declares a stack with a near corner', () {
    for (final biome in PondModel.biomes) {
      final stack = SceneLayers.stackFor(biome);
      expect(stack.where((l) => l.slot == LayerSlot.nearCorner), hasLength(1));
      expect(
        stack.where((l) => l.slot == LayerSlot.canopy).length,
        lessThanOrEqualTo(1),
      );
      for (final layer in stack) {
        expect(layer.depth, inInclusiveRange(0, 1));
        if (layer.slot == LayerSlot.particles) expect(layer.emitter, isNotNull);
      }
    }
    expect(
      SceneLayers.stackFor('willow').any((l) => l.canopy == CanopyKind.willow),
      isTrue,
    );
  });

  test(
    'procedural canopies keep the central lane clear at every phase and wind',
    () {
      const breath = SceneLayerPainter.breathAmplitude + .5;
      const shears = [
        -SceneLayerPainter.maxShear,
        0.0,
        SceneLayerPainter.maxShear,
      ];
      for (final biome in PondModel.biomes) {
        final layer = SceneLayers.stackFor(biome)
            .where((l) => l.canopy != null);
        if (layer.isEmpty) continue;
        final kind = layer.first.canopy!;
        for (final seed in [0, 1, 42, 1234, 99991]) {
          final canopy = CanopyGeometry.build(
            kind,
            seed,
            lantern: layer.first.lantern,
          );
          expect(
            canopy.strands.length + canopy.boughs.length,
            greaterThan(4),
            reason: biome,
          );
          void check(double x, double y, double pad, String what) {
            for (final dx in [-pad - breath, pad + breath]) {
              expect(
                _inLane(x + dx, y + pad),
                isFalse,
                reason: '$biome seed $seed: $what at ($x,$y) enters the lane',
              );
            }
          }

          for (final shear in shears) {
            for (var step = 0; step <= 32; step++) {
              final phase = step / 32;
              for (final s in canopy.strands) {
                for (var i = 0; i <= 20; i++) {
                  final p = CanopyGeometry.strandPoint(s, i / 20, phase, shear);
                  check(p.dx, p.dy, 4, 'strand');
                }
              }
            }
            for (final b in canopy.boughs) {
              for (final p in b.points) {
                check(p.dx + p.dy * shear, p.dy, b.thickness + 8, 'bough');
              }
            }
            for (final k in canopy.clusters) {
              check(k.x + k.y * shear, k.y, k.r + 2, 'cluster');
            }
            final lantern = canopy.lantern;
            if (lantern != null) {
              check(
                lantern.center.dx + lantern.bottom * shear,
                lantern.bottom,
                lantern.width,
                'lantern',
              );
            }
          }
        }
      }
    },
  );

  test('strands sway more toward the tip and lean with wind shear', () {
    const s = Strand(x: 50, y: 0, length: 100, curve: 0, amp: 5, phase: 0);
    final rootA = CanopyGeometry.strandPoint(s, 0, .25, 0);
    final midA = CanopyGeometry.strandPoint(s, .5, .25, 0);
    final tipA = CanopyGeometry.strandPoint(s, 1, .25, 0);
    expect(rootA.dx, 50);
    expect((midA.dx - 50).abs(), lessThan((tipA.dx - 50).abs()));
    expect(tipA.dx, closeTo(55, 1e-9));
    final tipWind = CanopyGeometry.strandPoint(s, 1, .25, .05);
    expect(tipWind.dx, closeTo(60, 1e-9));
    expect(tipWind.dy, 100);
  });

  test(
    'wind shear follows the model wind and freezes under reduced motion',
    () {
      final painter = SceneLayerPainter();
      final model = _modelFor('willow');
      final layer = SceneLayers.stackFor('willow')
          .firstWhere((l) => l.canopy != null);
      expect(painter.shearFor(model, layer), 0);
      model.progress = 1; // Fully revealed test session.
      model.wind = .08;
      model.windTell = 1;
      final gust = painter.shearFor(model, layer);
      expect(gust, greaterThan(0));
      expect(gust, lessThanOrEqualTo(SceneLayerPainter.maxShear));
      model.wind = -.08;
      expect(painter.shearFor(model, layer), closeTo(-gust, 1e-9));
      painter.reducedMotion = true;
      expect(painter.shearFor(model, layer), 0);
    },
  );

  test(
    'renderer falls back to procedural art with every optional image null',
    () async {
      for (final biome in PondModel.biomes) {
        final model = _modelFor(biome);
        model.press();
        model.release();
        model.update(6);
        expect(model.richness, greaterThan(.3), reason: biome);
        model.progress = 1; // Fully revealed test session.
      model.wind = .08;
        model.windTell = 1;
        final cycles = <PaletteCycle>[];
        for (final spec in PaletteCycles.specsFor(model.backdropAsset)) {
          cycles.add(await PaletteCycle.bake(spec));
        }
        final renderer = PondRenderer()..cycles = cycles;
        expect(renderer.layers.canopyImage, isNull);
        expect(renderer.layers.midBankImage, isNull);
        expect(renderer.layers.foregroundImage, isNull);
        expect(renderer.layers.foliage.paintedAtlas, isNull);
        await renderer.layers.foliage.prepare(biome);
        for (final reduced in [false, true]) {
          renderer.reducedMotion = reduced;
          for (var frame = 0; frame < 3; frame++) {
            model.update(.7);
            final recorder = ui.PictureRecorder();
            renderer.render(
              ui.Canvas(recorder),
              const ui.Size(641, 359),
              model,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(641, 359);
            expect(image.width, 641);
            image.dispose();
            picture.dispose();
          }
        }
        model.update(30);
        expect(model.sleeping, isTrue);
        final recorder = ui.PictureRecorder();
        renderer.render(ui.Canvas(recorder), const ui.Size(1282, 718), model);
        recorder.endRecording().dispose();
        renderer.dispose();
        for (final cycle in cycles) {
          cycle.dispose();
        }
      }
    },
  );
}
