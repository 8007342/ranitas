import 'dart:math' as math;
import 'dart:ui' as ui;

import 'pond_model.dart';

/// Depth cues belong behind the playable water. Broad cloud shadows cover
/// mountains and far lake together; fine rain and narrow waves recede toward
/// the horizon. Flocks use paired wings and a shared trajectory, never the
/// bright, independently wandering specks used for nearby insects.
class DistantAtmosphere {
  final _paint = ui.Paint()..isAntiAlias = false;

  double _bell(double x, double center, double radius) {
    final d = (x - center) / radius;
    return math.exp(-d * d * 2);
  }

  void draw(ui.Canvas c, PondModel m, {required bool reducedMotion}) {
    final cave = m.biome == 'grotto' || m.biome == 'crystal_grotto';
    if (cave) return;
    final t = reducedMotion ? 0.0 : m.ambientTime;
    final rain = m.rainIntensity * m.weatherReveal;
    // Slow, irregular coherent patches rather than a uniformly dark overlay.
    if (rain > 0) {
      for (var y = 30; y < 206; y += 6) {
        for (var x = 0; x < 641; x += 8) {
          var cloud = 0.0;
          for (var i = 0; i < 3; i++) {
            final cx =
                80 + i * 220 + math.sin(t * .012 + i * 1.7 + m.sceneSeed) * 100;
            cloud += _bell(x.toDouble(), cx, 95 + i * 17);
          }
          final sky = _bell(y.toDouble(), 62, 38);
          final land = _bell(y.toDouble(), 155, 58);
          final irregular = .72 + .28 * math.sin(x * .023 + y * .04 + t * .018);
          _paint.color = const ui.Color(0xff14263e).withValues(
            alpha: (rain * cloud * irregular * (.12 * sky + .16 * land)).clamp(
              0,
              .26,
            ),
          );
          c.drawRect(
            ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 8, 6),
            _paint,
          );
        }
      }
      c.save();
      c.clipRect(const ui.Rect.fromLTWH(0, 100, 641, 106));
      for (var i = 0; i < 38; i++) {
        final x = (i * 67.3 + m.sceneSeed % 97 + t * (1 + m.wind * 2)) % 641;
        final y = 100 + ((i * 31.7 + t * 38) % 106);
        _paint
          ..color = const ui.Color(0xffb3c3cf).withValues(alpha: rain * .16)
          ..strokeWidth = .55;
        c.drawLine(
          ui.Offset(x, y),
          ui.Offset(x + m.wind * .8, y + 2.2),
          _paint,
        );
      }
      c.restore();
    }
    // Narrow, low-contrast far-water ripples read as distance, not pad wakes.
    final farY = m.basin.topY - 13;
    for (var i = 0; i < 18; i++) {
      final y = farY + (i % 5) * 1.7;
      final x = 170 + (i * 39.7 + t * .65) % 300;
      final pulse = .5 + .5 * math.sin(t * .12 + i * 2.1);
      _paint.color = const ui.Color(0xffb0c7d1)
          .withValues(alpha: m.ambientMotion * (.015 + rain * .04) * pulse);
      c.drawRect(ui.Rect.fromLTWH(x, y, 3 + i % 7, .55), _paint);
    }
    if (m.weather == 'mist' || m.biome == 'autumn_mist') {
      for (var i = 0; i < 4; i++) {
        final y = 145 + i * 9.0;
        final x = -80 + math.sin(t * .009 + i) * 55;
        _paint.color = const ui.Color(0xffb7cdd0)
            .withValues(alpha: m.weatherReveal * .035);
        c.drawRect(ui.Rect.fromLTWH(x, y, 760, 4), _paint);
      }
    }
    if (m.distantReveal <= 0 || reducedMotion) return;
    final flight = ((t + m.sceneSeed % 47) % 96) / 96;
    final leadX = -65 + flight * 790;
    final leadY = 76 + math.sin(t * .012 + m.sceneSeed) * 16;
    _paint
      ..color = const ui.Color(0xff334653)
          .withValues(alpha: m.distantReveal * .5)
      ..strokeWidth = .65;
    for (var i = 0; i < 6; i++) {
      final x = leadX - (i ~/ 2 + 1) * 8;
      final y = leadY + (i.isEven ? -1 : 1) * (i ~/ 2 + 1) * 3;
      final wing = 1.1 + math.sin(t * 1.5 + i * .8) * .7;
      c.drawLine(ui.Offset(x - 2.6, y - wing), ui.Offset(x, y), _paint);
      c.drawLine(ui.Offset(x, y), ui.Offset(x + 2.6, y - wing), _paint);
    }
  }
}
