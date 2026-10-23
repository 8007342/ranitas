import 'dart:math' as math;
import 'dart:ui' as ui;

import 'pond_model.dart';

/// Pixel pond scenery. The caller retains ownership of [backdrop].
class PondRenderer {
  ui.Image? backdrop;
  bool reducedMotion = false;

  static const double _width = 257;
  static const double _height = 457;
  final ui.Paint _paint = ui.Paint()..isAntiAlias = false;
  ui.Picture? _scenery;
  int? _seed;
  String? _biome;
  List<_Mote> _details = const [];

  void _rect(
    ui.Canvas c,
    double x,
    double y,
    double w,
    double h,
    int color, [
    double opacity = 1,
  ]) {
    if (w <= 0 || h <= 0 || opacity <= 0) return;
    _paint.color = ui.Color(color).withValues(alpha: opacity.clamp(0.0, 1.0));
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

  void _oval(
    ui.Canvas c,
    double x,
    double y,
    double rx,
    double ry,
    int color, [
    double opacity = 1,
  ]) {
    for (var row = -ry.floor(); row <= ry.floor(); row++) {
      final span = rx * math.sqrt(math.max(0, 1 - row * row / (ry * ry)));
      _rect(c, x - span, y + row, span * 2, 1, color, opacity);
    }
  }

  void _line(
    ui.Canvas c,
    double x,
    double y,
    double tx,
    double ty,
    int color, [
    double opacity = 1,
    double thickness = 1,
  ]) {
    final steps = math.max((tx - x).abs(), (ty - y).abs()).ceil();
    for (var i = 0; i <= steps; i++) {
      final p = steps == 0 ? 0.0 : i / steps;
      _rect(
        c,
        x + (tx - x) * p,
        y + (ty - y) * p,
        thickness,
        thickness,
        color,
        opacity,
      );
    }
  }

  void _cache(PondModel model) {
    if (_scenery != null && _seed == model.sceneSeed && _biome == model.biome) {
      return;
    }
    _scenery?.dispose();
    _seed = model.sceneSeed;
    _biome = model.biome;
    var hash = 42;
    for (final code in model.biome.codeUnits) {
      hash = ((hash * 31) ^ code) & 0x7fffffff;
    }
    final random = math.Random(model.sceneSeed ^ hash);
    _details = List.generate(
      180,
      (_) => _Mote(
        random.nextDouble(),
        random.nextDouble(),
        random.nextDouble(),
        random.nextDouble(),
      ),
    );
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    for (var y = 0; y < 457; y += 2) {
      final sky = y < 185;
      final p = sky ? y / 185 : (y - 185) / 272;
      final color = ui.Color.lerp(
        ui.Color(sky ? 0xff39426c : 0xff45677b),
        ui.Color(sky ? 0xffd99991 : 0xff093f4a),
        p,
      )!;
      _rect(c, 0, y.toDouble(), 257, 2, color.toARGB32());
    }
    for (var layer = 0; layer < 3; layer++) {
      final top = 145 + layer * 16.0;
      final color = [0xff626787, 0xff3e5975, 0xff294e61][layer];
      for (var x = 0; x < 257; x += 2) {
        final y =
            top +
            math.sin(x * .025 + layer * 2) * 12 +
            math.sin(x * .071 + layer) * 5;
        _rect(c, x.toDouble(), y, 2, 205 - y, color);
      }
    }
    for (var i = 0; i < 95; i++) {
      final x = random.nextDouble() * 257;
      final y = 183 + random.nextDouble() * 18;
      final h = 4 + random.nextDouble() * 19;
      final color = i.isEven ? 0xff183e48 : 0xff245352;
      _rect(c, x, y - h, 1, h + 4, color);
      for (var j = 0; j < 5; j++) {
        _oval(c, x, y - h + j * h / 5, 1 + j * .8, 2, color);
      }
    }
    for (final d in _details) {
      final y = 210 + d.y * 240;
      _rect(
        c,
        d.x * 257,
        y,
        2 + d.z * 16,
        1,
        d.z > .5 ? 0xff7eaba1 : 0xff142f48,
        .18,
      );
    }
    _scenery = recorder.endRecording();
  }

  /// Draws directly into Flame's canvas; all actor positions are normalized.
  void render(ui.Canvas canvas, ui.Size size, PondModel model) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    _cache(model);
    final t = model.time;
    final motion = reducedMotion
        ? 0.0
        : .03 + .97 * model.richness.clamp(0.0, 1.0);
    final progress = model.progress.clamp(0.0, 1.0);
    final night = (1 - model.daylight).clamp(0.0, 1.0);
    canvas.save();
    canvas.clipRect(ui.Offset.zero & size);
    canvas.scale(size.width / _width, size.height / _height);
    final source = backdrop;
    if (source == null) {
      canvas.drawPicture(_scenery!);
    } else {
      final ratio = _width / _height;
      final sw = math.min(source.width.toDouble(), source.height * ratio);
      final sh = sw / ratio;
      _paint
        ..color = const ui.Color(0xffffffff)
        ..filterQuality = ui.FilterQuality.none;
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          (source.width - sw) / 2,
          (source.height - sh) / 2,
          sw,
          sh,
        ),
        const ui.Rect.fromLTWH(0, 0, _width, _height),
        _paint,
      );
    }
    // Preserve the supplied artwork; transparent color veils unify the actors.
    _rect(canvas, 0, 0, 257, 457, 0xff101f48, .08 + night * .65);
    if (model.cycle == 'dawn') {
      _rect(canvas, 0, 0, 257, 230, 0xffffc68e, progress * .12);
    }
    _sky(canvas, model, night);
    _water(canvas, model, motion);
    _foliage(canvas, model, motion, source != null);
    _pad(
      canvas,
      257 * .27,
      457 * .69 + 3 + model.leafNudge * 2,
      25,
      10,
      t,
      motion,
    );
    _pad(
      canvas,
      257 * .73,
      457 * .72 + 3 - model.leafNudge * 2,
      27,
      11,
      t + 2,
      motion,
    );
    for (final frog in model.frogs) {
      _frog(canvas, frog, model, motion);
    }
    for (final bug in model.bugs) {
      if (bug.alive) _bug(canvas, bug, model);
    }
    _weather(canvas, model, motion);
    canvas.restore();
  }

  void _sky(ui.Canvas c, PondModel m, double night) {
    for (var i = 0; i < 26; i++) {
      final d = _details[i];
      final a =
          night *
          (.2 + .5 * d.z) *
          (reducedMotion ? 1 : .8 + .2 * math.sin(m.time * .5 + d.w * 9));
      _rect(c, 35 + d.x * 190, 20 + d.y * 115, 1, 1, 0xffffebc3, a);
    }
    if (backdrop == null) {
      _oval(c, 177, 91, 13, 13, 0xffffd4a5, .15);
      _oval(c, 177, 91, 8, 8, 0xffffe5b7, .85);
      for (var i = 0; i < 9; i++) {
        final d = _details[i + 26];
        _rect(c, d.x * 220, 70 + d.y * 85, 15 + d.z * 36, 2, 0xffe3a8b0, .25);
      }
    }
  }

  void _water(ui.Canvas c, PondModel m, double motion) {
    for (var i = 30; i < 100; i++) {
      final d = _details[i];
      final y = 205 + d.y * 222;
      final wave = math.sin(m.time * .35 + d.w * 20) * motion;
      final a = (.055 + d.z * .085) * (1 + m.richness * .4);
      _rect(
        c,
        d.x * 257 + wave * 2,
        y,
        3 + d.z * 18,
        1,
        d.z > .65 ? 0xffffc6ac : 0xffa0dbcc,
        a,
      );
    }
    final reveal = ((m.richness - .2) / .3).clamp(0.0, 1.0);
    final koiOpacity = reveal * reveal * (3 - 2 * reveal);
    for (var i = 0; i < 3 && koiOpacity > 0; i++) {
      final d = _details[120 + i];
      final x = 70 + d.x * 120 + math.sin(m.time * .06 + i * 2) * 18 * motion;
      final y = 357 + i * 18.0 + math.cos(m.time * .08 + i) * 4 * motion;
      _oval(c, x, y, 7, 3, 0xffe8aa85, (.18 + m.richness * .12) * koiOpacity);
      _oval(c, x + 3, y, 3, 2, 0xfff5d9ac, .26 * koiOpacity);
      _rect(c, x - 9, y - 2, 3, 5, 0xffbf8b72, .2 * koiOpacity);
      _rect(c, x + 4, y - 1, 1, 1, 0xff244c53, .6 * koiOpacity);
    }
  }

  void _pad(
    ui.Canvas c,
    double x,
    double y,
    double rx,
    double ry,
    double t,
    double motion,
  ) {
    final bob = math.sin(t * .7) * .7 * motion;
    y += bob;
    _oval(c, x, y + 5, rx + 4, ry, 0xff092d3d, .4);
    _oval(c, x, y + 2, rx, ry, 0xff143e3a);
    _oval(c, x, y, rx, ry, 0xff32776a);
    _oval(c, x - 2, y - 2, rx - 3, ry - 2, 0xff49947a);
    _line(c, x - rx + 4, y - 3, x - 5, y - ry + 1, 0xff90bc84, .8);
    for (var i = -2; i <= 2; i++) {
      _line(c, x, y + 1, x + i * rx * .36, y - ry + 3, 0xffb7cd86, .22);
    }
    _line(c, x, y + 1, x + rx - 1, y + ry - 2, 0xff153f42, 1, 2);
    _line(c, x + 1, y + 2, x + rx - 2, y + ry - 1, 0xff67a47b);
    _rect(c, x - rx + 6, y + 2, 6, 1, 0xff94c195, .6);
  }

  void _frog(ui.Canvas c, FrogState f, PondModel m, double motion) {
    final x = (f.x * 257).roundToDouble();
    final y = (f.y * 457).roundToDouble();
    final sleeping = m.sleeping;
    final breath = !f.airborne && !f.swimming
        ? math.sin(m.time * (sleeping ? 1.1 : 1.8) + f.index) * .6 * motion
        : 0.0;
    final green = f.index == 0 ? 0xff80b867 : 0xff59ac94;
    final light = f.index == 0 ? 0xffb5d77b : 0xff94d0a3;
    const dark = 0xff193d3d;
    if (f.tongue > 0) {
      _line(c, x, y - 10, f.tongueX * 257, f.tongueY * 457, 0xffed9ca4, 1, 2);
    }
    if (f.bellyFlop > 0) {
      final spread = (1 - f.bellyFlop) * 18;
      for (var i = 0; i < 6; i++) {
        final side = i.isEven ? 1.0 : -1.0;
        _rect(
          c,
          x + side * (4 + spread + i),
          y - 5 - math.sin((1 - f.bellyFlop) * math.pi) * 12 + i % 3,
          2,
          2,
          0xffc2e5de,
          f.bellyFlop * .8,
        );
      }
      _oval(c, x, y + 3, 12 + spread, 2, 0xffb0d8d0, f.bellyFlop * .2);
    }
    if (f.swimming) {
      _oval(c, x, y + 2, 16, 3, 0xffa3c9b7, .35);
    } else {
      _oval(c, x, y + 4, f.airborne ? 7 : 13, 3, dark, .25);
    }
    c.save();
    c.translate(x, y + breath);
    if (f.index == 0 && m.pressing && !f.airborne && !f.swimming) {
      final charge = (m.holdDuration / .65).clamp(0.0, 1.0);
      c.scale(1 + charge * .05, 1 - charge * .12);
    }
    if (!f.swimming) {
      final stretch = f.airborne ? math.sin(f.jumpPhase * math.pi) * 4 : 0.0;
      _oval(c, -10 - stretch, -3, 6, 5, dark);
      _oval(c, 10 + stretch, -3, 6, 5, dark);
      _oval(c, -10 - stretch, -4, 4, 3, green);
      _oval(c, 10 + stretch, -4, 4, 3, green);
      _rect(c, -15 - stretch, 0, 8, 2, light);
      _rect(c, 8 + stretch, 0, 8, 2, light);
      _oval(c, 0, -8, 12, 10, dark);
      _oval(c, 0, -9, 11, 9, green);
      _oval(c, 0, -5, 7, 5, 0xffd8d99d);
      _rect(c, -3, -8, 5, 2, 0xffeee5b6);
    }
    _oval(c, 0, -13, 13, 7, dark);
    _oval(c, 0, -14, 12, 6, green);
    _rect(c, -6, -19, 12, 3, light);
    for (final side in [-1.0, 1.0]) {
      final ex = side * 7;
      _oval(c, ex, -20, 6, 6, dark);
      _oval(c, ex, -21, 5, 5, light);
      _oval(c, ex, -21, 4, 4, 0xffffecc1);
      final blink = !reducedMotion && ((m.time + f.index * 1.7) % 6.4) > 6.23;
      if (sleeping || blink) {
        _rect(c, ex - 3, -21, 6, 1, dark);
        _rect(c, ex - 2, -20, 4, 1, dark);
      } else {
        _rect(c, ex - 1, -24, 3, 6, dark);
        _rect(c, ex - 1, -24, 2, 2, 0xfffffff0);
        _rect(c, ex + 1, -19, 1, 1, 0xff638876);
        if (f.energy < .45) {
          _rect(c, ex - 3, -24, 7, 2, green);
          _rect(c, ex - 3, -22, 7, 1, dark, .65);
        }
      }
      _rect(c, side * 9 - 2, -13, 3, 2, 0xffdf9f92, .85);
      if (!f.swimming) {
        _line(c, side * 7, -7, side * 8, 0, dark);
        _rect(c, side * 8 - 2, 0, 5, 2, light);
      }
    }
    _rect(c, -4, -11, 8, 1, dark);
    _rect(c, -5, -12, 1, 1, dark);
    _rect(c, 4, -12, 1, 1, dark);
    _rect(c, -3, -15, 1, 1, dark, .6);
    _rect(c, 3, -15, 1, 1, dark, .6);
    _rect(c, -10, -8, 2, 2, light, .7);
    c.restore();
    if (sleeping) {
      final rise = reducedMotion ? 0.0 : (m.time * .13 + f.index * .4) % 1;
      final a = reducedMotion ? .45 : math.sin(rise * math.pi) * .65;
      final zx = x + 17;
      final zy = y - 29 - rise * 12;
      _rect(c, zx, zy, 4, 1, 0xffe1e3bf, a);
      _rect(c, zx + 2, zy + 1, 1, 1, 0xffe1e3bf, a);
      _rect(c, zx + 1, zy + 2, 1, 1, 0xffe1e3bf, a);
      _rect(c, zx, zy + 3, 4, 1, 0xffe1e3bf, a);
    }
  }

  void _foliage(ui.Canvas c, PondModel m, double motion, bool hasImage) {
    final blossom = m.biome == 'blossom';
    for (var i = 100; i < 120; i++) {
      final d = _details[i];
      final right = i.isEven;
      final x = right ? 250 - d.x * 24 : 7 + d.x * 24;
      final y = 415 + d.y * 40;
      final h = 12 + d.z * 32;
      final sway =
          (math.sin(m.time * .65 + d.w * 7) + (m.wind * 3 + m.windTell * 4)) *
          motion;
      _line(c, x, y, x + sway * 2 - 3, y - h, 0xff426c59, .9);
      _line(c, x + 1, y, x + sway * 2 - 2, y - h + 4, 0xffa4b977, .45);
      if (i % 3 == 0) {
        _rect(c, x + sway * 2 - 4, y - h - 5, 3, 8, 0xff725c49);
        _rect(c, x + sway * 2 - 4, y - h - 5, 1, 6, 0xffc09968);
      } else if (i % 3 == 1) {
        _flower(c, x + sway * 2 - 3, y - h, blossom ? 0xfff0b9cd : 0xffc9b8df);
      }
    }
    if (!hasImage) {
      for (var side = 0; side < 2; side++) {
        for (var i = 0; i < 35; i++) {
          final d = _details[i + 130];
          final x = side == 0 ? d.x * 62 - 8 : 265 - d.x * 62;
          final y = 425 + d.y * 35;
          _oval(c, x, y, 10 + d.z * 12, 5 + d.w * 8, 0xff173e40);
          _oval(c, x - 2, y - 3, 8 + d.z * 10, 3, 0xff416453);
          _rect(c, x - 3, y - 4, 4, 1, 0xffa7b775, .5);
        }
      }
      for (var side = 0; side < 2; side++) {
        for (var i = 0; i < 17; i++) {
          final d = _details[100 + i];
          final x = side == 0 ? i * 4.0 : 257 - i * 4.0;
          final top = 8 + i * .4;
          final length = 15 + d.z * 63;
          final sway = math.sin(m.time * .4 + i) * motion;
          _line(c, x, top, x + sway * 2, top + length, 0xff254b48);
          for (var j = 0; j < length; j += 4) {
            _rect(
              c,
              x + sway + (j % 8 == 0 ? -2 : 1),
              top + j,
              3,
              2,
              blossom ? 0xffcf91b1 : 0xff4e7970,
              .85,
            );
          }
        }
        _line(
          c,
          side == 0 ? 0 : 257,
          7,
          side == 0 ? 64 : 193,
          18,
          0xff18343c,
          1,
          4,
        );
      }
      _flower(c, 48, 390, 0xffe6a7b8);
      _flower(c, 218, 366, 0xffe6a7b8);
    }
  }

  void _flower(ui.Canvas c, double x, double y, int color) {
    _rect(c, x - 3, y - 1, 7, 2, color);
    _rect(c, x - 1, y - 3, 3, 6, color);
    _rect(c, x, y - 1, 2, 2, 0xfff5d795);
    _rect(c, x - 2, y - 2, 1, 1, 0xffffe1d8, .8);
  }

  void _bug(ui.Canvas c, BugState b, PondModel m) {
    final x = b.x * 257;
    final y = b.y * 457;
    final wing = reducedMotion ? 1.0 : math.sin(b.phase * 3).abs() * 2 + 1;
    final a = b.opacity;
    if (b.species == 'firefly') {
      _oval(c, x, y, 5, 5, 0xffe5e9a0, a * .07);
      _rect(c, x, y, 2, 2, 0xffffeaa6, a);
    } else if (b.species == 'ladybug') {
      _oval(c, x, y, 3, 3, 0xff293c46, a);
      _oval(c, x, y - 1, 2, 2, 0xffe78b69, a);
      _rect(c, x, y - 3, 1, 5, 0xff9f4e4b, a);
      _rect(c, x - 2, y - 1, 1, 1, 0xff293c46, a);
      _rect(c, x + 1, y, 1, 1, 0xff293c46, a);
      _rect(c, x - 1, y - 3, 1, 1, 0xffffce9b, a);
    } else if (b.species == 'butterfly') {
      _oval(c, x - 2, y, wing + 1, 3, 0xffe6ae9f, a);
      _oval(c, x + 2, y, wing + 1, 3, 0xffe6ae9f, a);
      _rect(c, x, y - 1, 1, 4, 0xff3d4254, a);
    } else {
      final dragon = b.species == 'dragonfly';
      _rect(
        c,
        x - (dragon ? 4 : 2),
        y - wing,
        dragon ? 9 : 5,
        1,
        0xffd4e5de,
        a * .7,
      );
      _rect(c, x, y - 1, 1, dragon ? 5 : 2, 0xffb7ba86, a);
      _rect(c, x, y - 1, 1, 1, 0xff243d47, a);
    }
  }

  void _weather(ui.Canvas c, PondModel m, double motion) {
    if (m.windTell > .05) {
      final direction = m.wind < 0 ? -1.0 : 1.0;
      for (var i = 0; i < 9; i++) {
        final d = _details[130 + i];
        final x = ((d.x + direction * m.time * .025) % 1) * 257;
        final y = 255 + d.y * 50 + math.sin(m.time + i) * 2;
        _line(
          c,
          x,
          y,
          x + direction * (3 + m.windTell * 5),
          y,
          0xffdfdbb2,
          m.windTell * .45,
        );
      }
    }
    final rain = m.weather == 'drizzle' || m.weather == 'storm';
    if (m.weather == 'mist' || m.weather == 'storm') {
      for (var i = 0; i < 8; i++) {
        final d = _details[70 + i];
        final x = -50 + d.x * 160 + math.sin(m.time * .035 + i) * 15 * motion;
        _rect(
          c,
          x,
          177 + i * 13.0,
          140 + d.z * 100,
          3 + d.w * 7,
          0xffb7cdd0,
          m.weather == 'mist' ? .055 : .035,
        );
      }
    }
    if (rain) {
      final count = reducedMotion ? 12 : (m.weather == 'storm' ? 90 : 38);
      for (var i = 0; i < count; i++) {
        final d = _details[i];
        final rainSpeed =
            (reducedMotion ? 12 : 85) * (.1 + .9 * m.richness.clamp(0.0, 1.0));
        final y = (d.y * 457 + m.time * rainSpeed) % 457;
        final x = (d.x * 257 + m.wind * y * .08) % 257;
        _line(
          c,
          x,
          y,
          x - 1 - m.wind * 2,
          y + 3 + d.z * 4,
          0xffb8d3d6,
          .12 + d.w * .15,
        );
      }
    }
    final night = (1 - m.daylight).clamp(0.0, 1.0);
    if (m.started && m.richness > .2 && night > 0) {
      for (var i = 0; i < 16; i++) {
        final d = _details[150 + i];
        final pulse = reducedMotion
            ? .7
            : .5 + .5 * math.sin(m.time * .9 + d.w * 20);
        final glow = pulse * m.richness * night * night;
        final x = d.x * 257 + math.sin(m.time * .2 + i) * 3 * motion;
        final y = 230 + d.y * 190;
        _rect(c, x - 1, y - 1, 3, 3, 0xffdded9d, glow * .08);
        _rect(c, x, y, 1, 1, 0xfff1e9a5, glow * .8);
      }
    }
  }

  /// Releases only procedural caches, never the externally owned image.
  void dispose() {
    _scenery?.dispose();
    _scenery = null;
    _details = const [];
    _seed = null;
    _biome = null;
  }
}

class _Mote {
  const _Mote(this.x, this.y, this.z, this.w);
  final double x, y, z, w;
}
