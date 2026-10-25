import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/palette_cycle.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/pond_renderer.dart';

Future<ui.Image> _loadAssetImage(String relativePath) async {
  final bytes = await rootBundle.load(relativePath);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all widescreen world biomes and frog sprite sheets render across lifecycle and poses',
    () async {
      final out = Directory('build/scene-checks')..createSync(recursive: true);
      final meadowSheet = await _loadAssetImage(
        'assets/images/frog-meadow-sheet.webp',
      );
      final tealSheet = await _loadAssetImage(
        'assets/images/frog-teal-sheet.webp',
      );
      expect(meadowSheet.width, 1031);
      expect(meadowSheet.height, 521);
      expect(tealSheet.width, 1031);
      expect(tealSheet.height, 521);

      final seenBiomes = <String>{};
      for (var seed = 0; seenBiomes.length < PondModel.biomes.length && seed < 100; seed++) {
        final probe = PondModel(seed: seed, durationOverride: 10);
        if (!seenBiomes.add(probe.biome)) continue;

        final backdrop = await _loadAssetImage(
          'assets/images/${probe.backdropAsset}',
        );
        expect(backdrop.width, 2752);
        expect(backdrop.height, 1536);

        final cycles = <PaletteCycle>[];
        for (final spec in PaletteCycles.specsFor(probe.backdropAsset)) {
          cycles.add(await PaletteCycle.bake(spec));
        }
        final foreground = await _loadAssetImage(
          'assets/images/${probe.foregroundAsset}',
        );
        final renderer = PondRenderer()
          ..backdrop = backdrop
          ..frogSheets = [meadowSheet, tealSheet]
          ..cycles = cycles;
        renderer.layers.foregroundImage = foreground;

        for (final stage in ['still', 'alive', 'sleep']) {
          if (stage == 'alive') {
            probe.press();
            probe.release();
            probe.update(5);
          }
          if (stage == 'sleep') {
            probe.update(20);
            expect(probe.sleeping, isTrue);
          }
          final recorder = ui.PictureRecorder();
          renderer.render(
            ui.Canvas(recorder),
            const ui.Size(1282, 718),
            probe,
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(1282, 718);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(png, isNotNull);
          expect(png!.lengthInBytes, greaterThan(20000));
          File('${out.path}/${probe.biome}-$stage.png').writeAsBytesSync(
            png.buffer.asUint8List(),
          );
          image.dispose();
          picture.dispose();
        }
        renderer.dispose();
        for (final cycle in cycles) {
          cycle.dispose();
        }
        foreground.dispose();
        backdrop.dispose();
      }
      expect(seenBiomes, PondModel.biomes.toSet());
      meadowSheet.dispose();
      tealSheet.dispose();
    },
  );

  test('away and toward flights render with and without sheets', () async {
    final meadowSheet = await _loadAssetImage(
      'assets/images/frog-meadow-sheet.webp',
    );
    final tealSheet = await _loadAssetImage('assets/images/frog-teal-sheet.webp');
    final seenViews = <String>{};
    for (var seed = 0; seed < 400 && seenViews.length < 2; seed++) {
      final probe = PondModel(seed: seed);
      probe.press();
      probe.release();
      final frog = probe.frogs[0];
      if (frog.view == 'side' || !seenViews.add(frog.view)) continue;
      // Render launch, ascent and descent with the procedural fallback, the
      // side sheets (depth poses still procedural) and a stand-in depth sheet.
      for (final phase in [.05, .3, .7]) {
        while (frog.airborne && frog.jumpPhase < phase) {
          probe.update(1 / 60);
        }
        expect(frog.viewPose(frog.currentPose()), startsWith(frog.view));
        for (final sheets in [
          (<ui.Image?>[null, null], <ui.Image?>[null, null]),
          ([meadowSheet, tealSheet], <ui.Image?>[null, null]),
          ([meadowSheet, tealSheet], [meadowSheet, tealSheet]),
        ]) {
          final renderer = PondRenderer()
            ..frogSheets = sheets.$1
            ..frogDepthSheets = sheets.$2;
          final recorder = ui.PictureRecorder();
          renderer.render(ui.Canvas(recorder), const ui.Size(641, 359), probe);
          final picture = recorder.endRecording();
          final image = await picture.toImage(641, 359);
          expect(image.width, 641);
          image.dispose();
          picture.dispose();
          renderer.dispose();
        }
      }
    }
    expect(seenViews, {'away', 'toward'});
    meadowSheet.dispose();
    tealSheet.dispose();
  });
}
