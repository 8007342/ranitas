// Run: flutter test tool/export_cycle_maps.dart
// Cycle maps are numeric lookup data, exported losslessly from the canonical
// region table rather than asking an image model to approximate slot values.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/palette_cycle.dart';

void main() {
  test('export canonical cycle lookup textures', () async {
    for (final name in [
      'dusk',
      'blossom',
      'mist',
      'maple',
      'sanctuary',
      'grotto',
      'alpine',
      'lotus',
      'firefly',
      'autumn-mist',
      'jade-sanctuary',
      'crystal-grotto',
    ]) {
      for (final spec in PaletteCycles.specsFor('pond-$name.webp')) {
        final pixels = Uint8List(641 * 359 * 4);
        for (var i = 3; i < pixels.length; i += 4) {
          pixels[i] = 255;
        }
        final w = spec.rect.width.round(), h = spec.rect.height.round();
        final map = spec.generator(w, h, spec.slots, spec.seed);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final px = spec.rect.left.floor() + x;
            final py = spec.rect.top.floor() + y;
            if (px < 0 || px >= 641 || py < 0 || py >= 359) continue;
            final index = (py * 641 + px) * 4;
            final gray = map[y * w + x] * 16;
            pixels[index] = gray;
            pixels[index + 1] = gray;
            pixels[index + 2] = gray;
          }
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
        final descriptor = ui.ImageDescriptor.raw(
          buffer,
          width: 641,
          height: 359,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        final codec = await descriptor.instantiateCodec();
        final image = (await codec.getNextFrame()).image;
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('art/source/cycle-pond-$name-${spec.id}.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    }
  });
}
