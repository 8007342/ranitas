import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ranitas/game/awakening.dart';
import 'package:ranitas/game/frog_sprites.dart';
import 'package:ranitas/game/pond_model.dart';
import 'package:ranitas/game/scene_layers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gusts have no forecast handoff jump and keep living after sleep', () {
    final m = PondModel(seed: 5, durationOverride: 10);
    m.press();
    m.release();
    m.update(30);
    expect(m.sleeping, isTrue);
    var before = m.wind, beforeTell = m.windTell, maxWind = 0.0;
    for (var i = 0; i < 4200; i++) {
      m.update(1 / 60);
      expect((m.wind - before).abs(), lessThan(.004));
      expect((m.windTell - beforeTell).abs(), lessThan(.02));
      maxWind = math.max(maxWind, m.wind.abs());
      before = m.wind;
      beforeTell = m.windTell;
    }
    expect(maxWind, greaterThan(.1));
  });

  test(
    'painted rock-bearing layers stay anchored while wind and time change',
    () async {
      final m = List.generate(
        100,
        (s) => PondModel(seed: s, durationOverride: 10),
      ).firstWhere((m) => m.biome == 'grotto')..progress = 1;
      final painter = SceneLayerPainter();
      final images = <ui.Image>[];
      for (final kind in ['foreground', 'midbank', 'canopy']) {
        final bytes = await rootBundle.load('assets/images/$kind-grotto.webp');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        images.add((await codec.getNextFrame()).image);
        codec.dispose();
      }
      painter.foregroundImage = images[0];
      painter.midBankImage = images[1];
      painter.canopyImage = images[2];
      for (final slot in [
        LayerSlot.nearCorner,
        LayerSlot.midBank,
        LayerSlot.canopy,
      ]) {
        final pixels = <List<int>>[];
        for (final phase in [0.0, 13.0]) {
          m.time = phase;
          m.ambientTime = phase;
          m.wind = phase / 20;
          final rec = ui.PictureRecorder();
          painter.drawSlot(ui.Canvas(rec), slot, m, 1);
          final pic = rec.endRecording(), image = await pic.toImage(641, 359);
          pixels.add((await image.toByteData())!.buffer.asUint8List());
          image.dispose();
          pic.dispose();
        }
        expect(pixels[0], pixels[1], reason: '$slot moved its stones');
      }
      painter.dispose();
      for (final image in images) {
        image.dispose();
      }
    },
  );

  test(
    'cached foliage lighting has no jump across the final night bucket',
    () async {
      final m = PondModel(seed: 1, durationOverride: 10);
      final painter = SceneLayerPainter();
      await painter.foliage.prepare(m.biome);
      final light = <double>[];
      for (final progress in [.84, .9165, .9168]) {
        m.progress = progress;
        final rec = ui.PictureRecorder();
        painter.drawSlot(ui.Canvas(rec), LayerSlot.nearCorner, m, 1);
        final pic = rec.endRecording(), image = await pic.toImage(641, 359);
        final bytes = (await image.toByteData())!.buffer.asUint8List();
        var sum = 0.0;
        for (var i = 0; i < bytes.length; i += 4) {
          sum += bytes[i] + bytes[i + 1] + bytes[i + 2];
        }
        light.add(sum);
        image.dispose();
        pic.dispose();
      }
      expect(light[1], greaterThan(0));
      expect((light[2] - light[1]).abs() / light[1], lessThan(.01));
      painter.dispose();
    },
  );

  test('unstarted pond remains still, reveal finishes at three minutes with a minute left', () {
    final m = PondModel(seed: 3);
    final positions = [
      ...m.pads,
      ...m.ambientPads,
    ].map((p) => (p.x, p.y, p.yaw)).toList();
    m.update(20);
    expect(m.ambientTime, 0);
    expect(m.richness, 0);
    expect(m.raindrops, isEmpty);
    for (var i = 0; i < positions.length; i++) {
      final p = [...m.pads, ...m.ambientPads][i];
      expect((p.x, p.y, p.yaw), positions[i]);
    }
    m.press();
    m.release();
    m.update(10);
    expect(m.foliageMotion, 0);
    expect(m.weatherReveal, 0);
    expect(m.ambientMotion, lessThan(.01));
    m.update(140);
    expect(m.sleeping, isFalse);
    expect(m.distantReveal, lessThan(1));
    expect(m.glowReveal, lessThan(1));
    m.update(30.1);
    expect(m.richness, 1);
    expect(m.distantReveal, 1);
    expect(m.glowReveal, 1);
    expect(m.duration - m.elapsed, greaterThan(59));
    m.update(180);
    expect(m.sleeping, isTrue);
    final time = m.ambientTime;
    m.update(30);
    expect(m.ambientTime, greaterThan(time + 29));
    expect(m.foliageMotion, 1);
  });

  test('each reveal has a gentle start, no steps and a zero-speed finish', () {
    for (final stage in [
      Awakening.water,
      Awakening.breeze,
      Awakening.foliage,
      Awakening.weather,
      Awakening.wildlife,
      Awakening.distant,
      Awakening.glow,
    ]) {
      var before = stage(0);
      for (var t = .1; t <= 240; t += .1) {
        final value = stage(t);
        expect(value, inInclusiveRange(before, 1));
        expect(value - before, lessThan(.0025));
        before = value;
      }
      expect(stage(180), 1);
    }
    expect(Awakening.reveal(.1, 0, 10), lessThan(.00002));
    expect(1 - Awakening.reveal(9.9, 0, 10), lessThan(.00002));
  });

  test('both foot endpoints fit on shared pads over 250 seeded landings', () {
    for (var seed = 0; seed < 250; seed++) {
      final m = PondModel(seed: seed);
      m.press();
      m.release();
      while (m.frogs[0].airborne) {
        m.update(1 / 60);
      }
      for (final f in m.frogs.where((f) => !f.airborne && !f.swimming)) {
        final pad = m.pads[f.leafIndex];
        final half = 17 * m.frogScale(f);
        final dy = f.perchDy * 359;
        for (final sign in [-1, 1]) {
          final dx = f.perchDx * 641 + sign * half;
          final ellipse =
              math.pow(dx / pad.radiusX, 2) + math.pow(dy / pad.radiusY, 2);
          expect(ellipse, lessThan(.95), reason: 'seed=$seed frog=${f.index}');
        }
      }
    }
  });

  test(
    'sprite blinks only alter opaque eye pixels, with no floating overlays',
    () async {
      final out = Directory('build/blink-checks')..createSync(recursive: true);
      for (final name in ['meadow', 'teal']) {
        final bytes = await rootBundle.load(
          'assets/images/frog-$name-sheet.webp',
        );
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final sheet = (await codec.getNextFrame()).image;
        codec.dispose();
        final poses = name == 'meadow'
            ? ['idle', 'charging', 'landing', 'swallowing']
            : ['idle', 'landing', 'swallowing'];
        for (final pose in poses) {
          final model = PondModel(seed: 1);
          final frog = model.frogs[name == 'meadow' ? 0 : 1];
          if (pose == 'charging') model.press();
          if (pose == 'landing') frog.landingTimer = .28;
          if (pose == 'swallowing') frog.swallowTimer = .5;
          final subject = frog;
          final frames = <ui.Image>[];
          for (final closed in [false, true]) {
            model.time = (closed ? 6.56 : 6.4) - subject.index * 2.13;
            final rec = ui.PictureRecorder();
            final c = ui.Canvas(rec)
              ..translate(80 - subject.x * 641, 90 - subject.y * 359);
            FrogSprites.renderFrog(
              canvas: c,
              paint: ui.Paint(),
              frog: subject,
              model: model,
              motion: 0,
              reducedMotion: false,
              sheet: sheet,
            );
            final pic = rec.endRecording();
            final image = await pic.toImage(160, 120);
            pic.dispose();
            frames.add(image);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            File('${out.path}/$name-$pose-${closed ? 'closed' : 'open'}.png')
                .writeAsBytesSync(png!.buffer.asUint8List());
          }
          final a = (await frames[0].toByteData())!.buffer.asUint8List();
          final b = (await frames[1].toByteData())!.buffer.asUint8List();
          var changes = 0;
          for (var i = 0; i < a.length; i += 4) {
            if (a[i] == b[i] && a[i + 1] == b[i + 1] && a[i + 2] == b[i + 2]) {
              continue;
            }
            changes++;
            expect(
              a[i + 3],
              greaterThan(0),
              reason: '$name $pose paints outside sprite',
            );
            expect(
              b[i + 3],
              a[i + 3],
              reason: '$name $pose changes silhouette',
            );
            final x = (i ~/ 4) % 160, y = (i ~/ 4) ~/ 160;
            expect(x, inInclusiveRange(64, 99));
            expect(y, inInclusiveRange(65, 92));
          }
          expect(changes, greaterThan(0), reason: '$name $pose blink absent');
          expect(
            changes,
            lessThan(45),
            reason: '$name $pose eye patch too large',
          );
          for (final image in frames) {
            image.dispose();
          }
        }
        sheet.dispose();
      }
    },
  );
}
