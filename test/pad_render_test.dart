import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/pond_renderer.dart';

/// The pad's slit is a real gap: whatever lies beneath shows through it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> paintPadOver(int flat, PadState pad, double yaw) async {
    pad.yaw = yaw;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 200, 120),
      ui.Paint()..color = ui.Color(flat),
    );
    PondRenderer().drawPad(canvas, pad, 100, 60);
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 120);
    picture.dispose();
    return image;
  }

  int pixel(ByteData data, int x, int y) {
    final i = (y * 200 + x) * 4;
    return (data.getUint8(i) << 16) |
        (data.getUint8(i + 1) << 8) |
        data.getUint8(i + 2);
  }

  /// The pixel on the slit centreline at [fraction] of the radius: the row
  /// containing the point, then the centreline's column at that row's centre
  /// (rounding x and y separately would step off a thin diagonal wedge).
  (int, int) slitPixel(PadState pad, double cx, double cy, double fraction) {
    final (sx, sy) = PondRenderer.slitPoint(pad, cx, cy, fraction);
    final row = sy.floor();
    final dirY = sin(pad.slitAngle) * pad.radiusY;
    if (dirY.abs() < .5) return (sx.floor(), row);
    final t = (row + .5 - cy) / dirY;
    return ((cx + cos(pad.slitAngle) * pad.radiusX * t).floor(), row);
  }

  test('a pixel inside the slit shows the colour beneath, the body does not', () async {
    const flat = 0xff3366cc;
    final m = PondModel(seed: 7);
    final largest = m.ambientPads.reduce(
      (a, b) => a.radiusX >= b.radiusX ? a : b,
    );
    final smallest = m.ambientPads.reduce(
      (a, b) => a.radiusX <= b.radiusX ? a : b,
    );
    // The smallest leaf (a few rows tall) still shows the gap along its slit.
    for (final target in [1.5708, -1.5708]) {
      final image = await paintPadOver(flat, smallest, target - smallest.phase);
      final data = (await image.toByteData())!;
      final (sx, sy) = slitPixel(smallest, 100, 60, .6);
      expect(pixel(data, sx, sy), flat & 0xffffff,
          reason: 'small pad ${smallest.index} slit at $target');
      image.dispose();
    }
    for (final pad in [m.pads[0], m.pads[1], largest]) {
      // Slit pointing down-screen (widest), up-screen, and diagonally.
      for (final target in [1.5708, -1.5708, .9, 2.4]) {
        final image = await paintPadOver(flat, pad, target - pad.phase);
        final data = (await image.toByteData())!;
        final (sx, sy) = slitPixel(pad, 100, 60, .6);
        expect(pixel(data, sx, sy), flat & 0xffffff,
            reason: 'pad ${pad.index} slit at $target');
        // Opposite the slit the leaf is painted.
        final (ox, oy) = slitPixel(pad, 100, 60, -.6);
        expect(pixel(data, ox, oy), isNot(flat & 0xffffff),
            reason: 'pad ${pad.index} body at $target');
        // The stem disc at the centre stays whole.
        expect(pixel(data, 100, 60), isNot(flat & 0xffffff));
        image.dispose();
      }
    }
  });

  test('the super pad keeps its notch through the upturned rim', () async {
    const flat = 0xffcc3366;
    PadState? superPad;
    for (var seed = 0; seed < 300 && superPad == null; seed++) {
      final m = PondModel(seed: seed);
      for (final p in m.ambientPads) {
        if (p.isSuper) superPad = p;
      }
    }
    final pad = superPad!;
    for (final target in [1.5708, 2.2, .8]) {
      final image = await paintPadOver(flat, pad, target - pad.phase);
      final data = (await image.toByteData())!;
      for (final fraction in [.5, .8]) {
        final (sx, sy) = slitPixel(pad, 100, 60, fraction);
        expect(pixel(data, sx, sy), flat & 0xffffff,
            reason: 'super slit at $target × $fraction');
      }
      final (ox, oy) = slitPixel(pad, 100, 60, -.6);
      expect(pixel(data, ox, oy), isNot(flat & 0xffffff));
      image.dispose();
    }
  });

  test('a koi under a hero pad shows through the slit (frame in build/scene-checks)', () async {
    final out = Directory('build/scene-checks')..createSync(recursive: true);
    final m = PondModel(seed: 7);
    m.press();
    m.release();
    m.update(2);
    final pad = m.pads[1];
    pad.yaw = 1.5708 - pad.phase;
    final px = pad.x * 641 + pad.driftX;
    final py = pad.y * 359 + 3 + pad.floatY + pad.dipY;
    final (sx, sy) = PondRenderer.slitPoint(pad, px, py, .55);
    m.koi[0]
      ..x = sx
      ..y = sy
      ..depth = .15
      ..heading = .3;
    final renderer = PondRenderer();

    Future<ByteData> frame(bool withKoi) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(8);
      canvas.translate(-(px - 50), -(py - 25));
      if (!withKoi) {
        m.koi[0].y = m.basin.topY - 100;
      } else {
        m.koi[0]
          ..x = sx
          ..y = sy;
      }
      renderer.render(canvas, const ui.Size(641, 359), m);
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 400);
      if (withKoi) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/pad-slit-koi.png').writeAsBytesSync(
          png!.buffer.asUint8List(),
        );
      }
      final data = (await image.toByteData())!;
      image.dispose();
      picture.dispose();
      return data;
    }

    final with_ = await frame(true);
    final without = await frame(false);
    // Along the slit the frame changes with the fish; the leaf body hides it.
    var slitChanged = 0;
    var bodyChanged = 0;
    for (var i = 0; i < 20; i++) {
      final f = .3 + i * .025;
      final (ax, ay) = PondRenderer.slitPoint(pad, px, py, f);
      final (bx, by) = PondRenderer.slitPoint(pad, px, py, -f);
      int at(ByteData d, double x, double y) {
        final ix = ((x - (px - 50)) * 8).round().clamp(0, 799);
        final iy = ((y - (py - 25)) * 8).round().clamp(0, 399);
        final o = (iy * 800 + ix) * 4;
        return d.getUint32(o);
      }
      if (at(with_, ax, ay) != at(without, ax, ay)) slitChanged++;
      if (at(with_, bx, by) != at(without, bx, by)) bodyChanged++;
    }
    expect(slitChanged, greaterThan(4));
    expect(bodyChanged, 0);
    renderer.dispose();
  });
}
