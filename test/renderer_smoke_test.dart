import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/pond_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all world layers render before play and after permanent sleep',
    () async {
      final out = Directory('build/scene-checks')..createSync(recursive: true);
      for (final seed in [7, 18, 42]) {
        final model = PondModel(seed: seed, durationOverride: 10);
        final asset = model.biome == 'cypress'
            ? 'pond-mist'
            : model.biome == 'blossom'
            ? 'pond-blossom'
            : 'pond-dusk';
        final bytes = await rootBundle.load('assets/images/$asset.webp');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        final renderer = PondRenderer()..backdrop = frame.image;
        for (final stage in ['still', 'alive', 'sleep']) {
          if (stage == 'alive') {
            model.press();
            model.release();
            model.update(5);
          }
          if (stage == 'sleep') {
            model.update(20);
            expect(model.sleeping, isTrue);
          }
          final recorder = ui.PictureRecorder();
          renderer.render(ui.Canvas(recorder), const ui.Size(514, 914), model);
          final picture = recorder.endRecording();
          final image = await picture.toImage(514, 914);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(png, isNotNull);
          expect(png!.lengthInBytes, greaterThan(10000));
          File('${out.path}/$seed-$stage.png')
              .writeAsBytesSync(png.buffer.asUint8List());
          image.dispose();
          picture.dispose();
        }
        renderer.dispose();
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
