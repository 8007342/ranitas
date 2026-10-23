import 'dart:math' as math;
import 'dart:ui' as ui;

import 'frog_sprites.dart';
import 'pond_model.dart';

/// Widescreen pixel pond scenery implementing the 6-Tier Composable Rendering
/// Architecture (`art/INTERACTION_STYLEGUIDE.md`). The caller retains ownership
/// of [backdrop], [frogSheets], and [wildlifeSheet].
class PondRenderer {
  ui.Image? backdrop;
  List<ui.Image?> frogSheets = [null, null];
  ui.Image? wildlifeSheet;
  bool reducedMotion = false;

  static const double logicalWidth = 641;
  static const double logicalHeight = 359;
  static const double _width = logicalWidth;
  static const double _height = logicalHeight;
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

  void _ovalRing(
    ui.Canvas c,
    double x,
    double y,
    double rx,
    double ry,
    int color, [
    double opacity = 1,
  ]) {
    if (rx <= 1 || ry <= 0.5 || opacity <= 0) return;
    final ryFloor = ry.floor();
    for (var row = -ryFloor; row <= ryFloor; row++) {
      final ratio = (row / ry).clamp(-1.0, 1.0);
      final span = rx * math.sqrt(math.max(0.0, 1.0 - ratio * ratio));
      if (row.abs() == ryFloor) {
        _rect(c, x - span * .65, y + row, span * 1.3, 1, color, opacity * .85);
      } else {
        final edgeW = (1.4 + (row.abs() / math.max(1, ryFloor)) * 1.6);
        _rect(c, x - span, y + row, edgeW, 1, color, opacity);
        _rect(c, x + span - edgeW, y + row, edgeW, 1, color, opacity);
      }
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
      220,
      (_) => _Mote(
        random.nextDouble(),
        random.nextDouble(),
        random.nextDouble(),
        random.nextDouble(),
      ),
    );
    final recorder = ui.PictureRecorder();
    final c = ui.Canvas(recorder);
    for (var y = 0; y < 359; y += 2) {
      final sky = y < 145;
      final p = sky ? y / 145 : (y - 145) / 214;
      final color = ui.Color.lerp(
        ui.Color(sky ? 0xff39426c : 0xff45677b),
        ui.Color(sky ? 0xffd99991 : 0xff093f4a),
        p,
      )!;
      _rect(c, 0, y.toDouble(), _width, 2, color.toARGB32());
    }
    for (var layer = 0; layer < 3; layer++) {
      final top = 112 + layer * 13.0;
      final color = [0xff626787, 0xff3e5975, 0xff294e61][layer];
      for (var x = 0; x < 641; x += 2) {
        final y =
            top +
            math.sin(x * .014 + layer * 2) * 11 +
            math.sin(x * .041 + layer) * 5;
        _rect(c, x.toDouble(), y, 2, 162 - y, color);
      }
    }
    for (var i = 0; i < 120; i++) {
      final x = random.nextDouble() * _width;
      final y = 144 + random.nextDouble() * 16;
      final h = 4 + random.nextDouble() * 17;
      final color = i.isEven ? 0xff183e48 : 0xff245352;
      _rect(c, x, y - h, 1, h + 4, color);
      for (var j = 0; j < 5; j++) {
        _oval(c, x, y - h + j * h / 5, 1 + j * .8, 2, color);
      }
    }
    for (final d in _details) {
      final y = 165 + d.y * 188;
      _rect(
        c,
        d.x * _width,
        y,
        3 + d.z * 22,
        1,
        d.z > .5 ? 0xff7eaba1 : 0xff142f48,
        .18,
      );
    }
    _scenery = recorder.endRecording();
  }

  /// Draws directly into Flame's canvas; stretches composable layers to fill
  /// the entire viewport [size].
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

    // TIER 0: Full-bleed Composable Scenic Backdrop & Sky
    final source = backdrop;
    if (source == null) {
      canvas.drawPicture(_scenery!);
    } else {
      _paint
        ..color = const ui.Color(0xffffffff)
        ..filterQuality = ui.FilterQuality.none;
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        const ui.Rect.fromLTWH(0, 0, _width, _height),
        _paint,
      );
    }
    _rect(canvas, 0, 0, _width, _height, 0xff101f48, .06 + night * .60);
    if (model.cycle == 'dawn') {
      _rect(canvas, 0, 0, _width, 185, 0xffffc68e, progress * .12);
    }
    _sky(canvas, model, night);

    // TIER 1: Sub-Surface Water Caustics & Submerged Stems
    _waterCaustics(canvas, model, motion);

    // TIER 2: Sub-Surface Aquatic Life (Koi Fish & Tadpoles swimming UNDER ripples)
    _subsurfaceWildlife(canvas, model, motion);

    // TIER 3: Composable Water Surface Shimmer & Expanding Refraction Ripples
    // (Rendered OVER Koi & Tadpoles so ripples refract across underlying sprites)
    _waterSurfaceAndRipples(canvas, model, motion);

    // TIER 4: Floating Interactive Lily Pads (Ambient + Hero), Lotus Blooms, Splash Droplets, Frogs & Bugs
    final allPads = <(PadState, double, double, double)>[
      for (final p in model.ambientPads)
        (
          p,
          _width * p.x,
          _height * p.y + 3 + p.floatY,
          t + p.index * 1.1,
        ),
      (
        model.pads[0],
        _width * model.pads[0].x,
        _height * model.pads[0].y + 3 + model.leafNudge * 2 + model.pads[0].floatY,
        t,
      ),
      (
        model.pads[1],
        _width * model.pads[1].x,
        _height * model.pads[1].y + 3 - model.leafNudge * 2 + model.pads[1].floatY,
        t + 2,
      ),
    ]..sort((a, b) => a.$3.compareTo(b.$3));

    for (final entry in allPads) {
      _pad(
        canvas,
        entry.$1,
        entry.$2,
        entry.$3,
        entry.$4,
        motion,
        model.biome,
      );
    }
    _splashDroplets(canvas, model);

    for (final frog in model.frogs) {
      final sheet = frog.index < frogSheets.length
          ? frogSheets[frog.index]
          : null;
      FrogSprites.renderFrog(
        canvas: canvas,
        paint: _paint,
        frog: frog,
        model: model,
        motion: motion,
        reducedMotion: reducedMotion,
        sheet: sheet,
      );
    }
    for (final bug in model.bugs) {
      if (bug.alive) _bug(canvas, bug, model);
    }

    // TIER 5: Shore Foliage, Biome Atmospheric Motifs & Weather
    _foliage(canvas, model, motion, source != null);
    _motifs(canvas, model, motion, night);
    _weather(canvas, model, motion);
    canvas.restore();
  }

  void _sky(ui.Canvas c, PondModel m, double night) {
    for (var i = 0; i < 36; i++) {
      final d = _details[i];
      final a =
          night *
          (.2 + .55 * d.z) *
          (reducedMotion ? 1 : .8 + .2 * math.sin(m.time * .5 + d.w * 9));
      _rect(c, 55 + d.x * 530, 14 + d.y * 92, 1, 1, 0xffffebc3, a);
    }
    if (backdrop == null) {
      _oval(c, 445, 68, 14, 14, 0xffffd4a5, .15);
      _oval(c, 445, 68, 8, 8, 0xffffe5b7, .85);
      for (var i = 0; i < 11; i++) {
        final d = _details[i + 36];
        _rect(
          c,
          d.x * 560,
          52 + d.y * 65,
          24 + d.z * 55,
          2,
          0xffe3a8b0,
          .25,
        );
      }
    }
  }

  void _waterCaustics(ui.Canvas c, PondModel m, double motion) {
    // Dappled sub-surface caustic light ribbons constrained to the biome water basin
    final isGrotto = m.biome == 'grotto' || m.biome == 'crystal_grotto';
    final causticColor = isGrotto ? 0xff49c9c4 : 0xff5ca89f;
    for (var i = 0; i < 24; i++) {
      final d = _details[48 + i];
      final y = m.basin.topY + d.y * (m.basin.bottomY - m.basin.topY);
      final left = m.basin.leftX(y);
      final right = m.basin.rightX(y);
      final drift = math.sin(m.time * .28 + d.w * 14) * 5 * motion;
      final x = (left + d.x * (right - left) + drift).clamp(left, right - 12);
      _rect(
        c,
        x,
        y,
        6 + d.z * 18,
        1,
        causticColor,
        .045 + d.z * .04,
      );
    }
    for (final pad in [...m.ambientPads, ...m.pads]) {
      final px = pad.x * _width + pad.driftX * .5;
      final py = pad.y * _height + 5 + pad.floatY + pad.dipY * .5;
      final sway = math.sin(m.time * .6 + pad.index) * 2.5 * motion;
      final stemLen = pad.isAmbient ? 16.0 : 28.0;
      _line(c, px, py, px + sway, py + stemLen, 0xff0d333b, .35, pad.isAmbient ? 1 : 2);
    }
  }

  void _subsurfaceWildlife(ui.Canvas c, PondModel m, double motion) {
    final deepWater = (m.biome == 'grotto' || m.biome == 'crystal_grotto')
        ? const ui.Color(0xff082833)
        : const ui.Color(0xff0b303c);

    int submergeColor(int hex, double depth, double viewportDist) {
      final t = (depth * .76 + viewportDist * .24).clamp(0.12, 0.92);
      return ui.Color.lerp(ui.Color(hex), deepWater, t)!.toARGB32();
    }

    // 1. Darting pond tadpoles (depth-attenuated & perspective-scaled, no detached bean shadow)
    final tadpoleAlpha = (.24 + m.richness * .24).clamp(0.24, 0.48);
    for (final tp in m.tadpoles) {
      final vDist = ((338.0 - tp.y) / 146.0).clamp(0.0, 1.0);
      final tScale = 1.05 - .48 * vDist;
      final dirX = math.cos(tp.heading) * tScale;
      final dirY = math.sin(tp.heading) * (.62 - .22 * vDist) * tScale;
      final perpX = -dirY;
      final perpY = dirX;
      final wag = reducedMotion ? 0.0 : math.sin(tp.swimPhase) * 1.8 * tScale;
      final headCol = submergeColor(0xff1e4752, .45, vDist);
      final tailCol = submergeColor(0xff2e636e, .55, vDist);
      _oval(
        c,
        tp.x,
        tp.y,
        2.6 * tScale,
        1.7 * tScale * (.68 - .25 * vDist),
        headCol,
        tadpoleAlpha,
      );
      _line(
        c,
        tp.x - dirX * 2,
        tp.y - dirY * 2,
        tp.x - dirX * 7.5 + perpX * wag,
        tp.y - dirY * 7.5 + perpY * wag,
        tailCol,
        tadpoleAlpha * .82,
      );
    }

    // 2. Ornamental Multi-Segment Koi Fish (Kohaku, Yamabuki, Showa, Asagi)
    //    Perspective-scaled by distance from viewport (y), foreshortened by viewing
    //    angle & dive pitch, and shaded per-segment via Beer-Lambert water absorption.
    final baseKoiVisibility = (.58 + m.richness * .30).clamp(0.58, 0.88);
    // Sort Koi from farthest/deepest to nearest/shallowest for true underwater painter's order
    final sortedKoi = [...m.koi]
      ..sort((a, b) => (a.y - a.depth * 25).compareTo(b.y - b.depth * 25));

    for (final k in sortedKoi) {
      final viewportDist = ((338.0 - k.y) / 146.0).clamp(0.0, 1.0);
      // Perspective scale: smaller near far bank (y~195), larger in foreground (y~335),
      // and slightly smaller as the fish dives deeper into the water column.
      final scale = (1.14 - .62 * viewportDist) * (1.0 - .20 * k.depth);
      // Viewing angle foreshortening: steeper in foreground, shallower grazing angle near horizon
      final aspectY = (.68 - .30 * viewportDist).clamp(0.36, 0.70);
      final pitchCos = math.cos(k.pitch).clamp(0.76, 1.0);

      final dirX = math.cos(k.heading) * scale * pitchCos;
      final dirY = math.sin(k.heading) * aspectY * scale * pitchCos;
      final perpX = -math.sin(k.heading) * scale;
      final perpY = math.cos(k.heading) * aspectY * scale;

      // Per-segment depth (i=0 snout .. i=6 caudal tail tip):
      // Diving down (pitch > 0) makes head deeper than tail;
      // Rising up (pitch < 0) brings head into the sunlit surface layer first.
      double segDepth(int i) =>
          (k.depth + math.sin(k.pitch) * (2.5 - i) * .095).clamp(0.05, 0.96);

      double segAlpha(double sDepth) =>
          (baseKoiVisibility * (1.0 - sDepth * .48) * (1.0 - viewportDist * .18))
              .clamp(0.22, 0.90);

      final (int rawBody, int rawPatch1, int rawPatch2, int rawFin) =
          switch (k.variant % 4) {
            0 => (0xfff4efe2, 0xffe04832, 0xfff06a4d, 0xfff7f2e6), // Kohaku
            1 => (0xfff5bc47, 0xffffe484, 0xffd49326, 0xffffe8ad), // Yamabuki
            2 => (0xffede8dc, 0xffd43b30, 0xff1c2b36, 0xfff0ebe0), // Showa
            _ => (0xff6e9db8, 0xff9ec8e0, 0xffeb784d, 0xfff29168), // Asagi
          };

      double segX(int i, double sOffset) {
        final wave = reducedMotion
            ? 0.0
            : (0.25 + 0.28 * i * i) * math.sin(k.swimPhase - i * 0.75);
        return k.x + dirX * sOffset + perpX * wave;
      }

      double segY(int i, double sOffset) {
        final wave = reducedMotion
            ? 0.0
            : (0.25 + 0.28 * i * i) * math.sin(k.swimPhase - i * 0.75);
        return k.y + dirY * sOffset + perpY * wave;
      }

      // 7 spine nodes from snout (0) to forked tail tip (6)
      const offsets = [8.5, 5.5, 1.5, -3.0, -7.5, -11.5, -16.5];
      const radii = [2.8, 4.4, 5.8, 5.2, 3.8, 2.4, 1.5];

      // Swept pectoral & pelvic fins (drawn beneath the body core at shoulder/mid depth)
      final shoulderDepth = (segDepth(2) + .08).clamp(0.08, 0.96);
      final finAlpha = segAlpha(shoulderDepth) * .62;
      final finColor = submergeColor(rawFin, shoulderDepth, viewportDist);
      final sx = segX(2, offsets[2]);
      final sy = segY(2, offsets[2]);
      final finBeat = reducedMotion
          ? 0.0
          : math.sin(k.swimPhase * 1.15 + .4) * 1.1;
      for (final side in [-1.0, 1.0]) {
        final fx = sx - dirX * 1.2 + perpX * side * (5.2 + finBeat);
        final fy = sy - dirY * 1.2 + perpY * side * (5.2 + finBeat);
        _oval(
          c,
          fx,
          fy,
          3.4 * scale,
          2.0 * scale * aspectY,
          finColor,
          finAlpha,
        );
      }

      // Flowing forked caudal veil tail (node 5 -> node 6)
      final tailDepth = segDepth(6);
      final tailAlpha = segAlpha(tailDepth) * .68;
      final tailCol = submergeColor(rawFin, tailDepth, viewportDist);
      final px = segX(5, offsets[5]);
      final py = segY(5, offsets[5]);
      final tx = segX(6, offsets[6]);
      final ty = segY(6, offsets[6]);
      _line(
        c,
        px,
        py,
        tx + perpX * 3.2,
        ty + perpY * 3.2,
        tailCol,
        tailAlpha,
        math.max(1, (2.0 * scale).roundToDouble()),
      );
      _line(
        c,
        px,
        py,
        tx - perpX * 3.2,
        ty - perpY * 3.2,
        tailCol,
        tailAlpha,
        math.max(1, (2.0 * scale).roundToDouble()),
      );

      // Draw body segments ordered from deepest to shallowest so diving/rising
      // self-occlusion matches the 3D water column
      final segOrder = [5, 4, 3, 2, 1, 0]
        ..sort((a, b) => segDepth(b).compareTo(segDepth(a)));

      for (final i in segOrder) {
        final cx = segX(i, offsets[i]);
        final cy = segY(i, offsets[i]);
        final r = radii[i] * scale;
        final ry = math.max(1.0, r * (.58 + .28 * aspectY));
        final sDepth = segDepth(i);
        final sAlpha = segAlpha(sDepth);

        // Concentric subsurface water-scatter rim (hugs the fish body, never detached)
        final haloCol = submergeColor(0xff072029, sDepth + .12, viewportDist);
        _oval(c, cx, cy + .6 * scale, r + 1.0, ry + .6, haloCol, sAlpha * .42);

        // Main depth-attenuated body segment
        final bCol = submergeColor(rawBody, sDepth, viewportDist);
        _oval(c, cx, cy, r, ry, bCol, sAlpha);

        // Dorsal pattern markings (Kohaku / Yamabuki / Showa / Asagi)
        if (i == 1 || i == 2) {
          final p1Col = submergeColor(rawPatch1, sDepth - .03, viewportDist);
          _oval(c, cx, cy - .3 * scale, r * .72, ry * .72, p1Col, sAlpha * .95);
        } else if (i == 3 || i == 4) {
          final p2Col = submergeColor(rawPatch2, sDepth, viewportDist);
          _oval(c, cx, cy, r * .68, ry * .68, p2Col, sAlpha * .92);
        }

        // Overhead underwater caustic light glint when segment is near surface
        if (sDepth < 0.36 && (i == 1 || i == 2 || i == 3)) {
          final glintAlpha = ((0.36 - sDepth) / 0.36) * sAlpha * .55;
          final glintCol = submergeColor(0xffb8f7ee, sDepth * .5, viewportDist);
          _rect(c, cx - r * .35, cy - ry * .45, r * .7, 1, glintCol, glintAlpha);
        }
      }

      // Eyes on head segment (node 1) when shallow/mid-depth
      final headDepth = segDepth(1);
      if (headDepth < 0.78) {
        final hx = segX(1, offsets[1]);
        final hy = segY(1, offsets[1]);
        final eyeCol = submergeColor(0xff10262e, headDepth, viewportDist);
        final eyeAlpha = segAlpha(headDepth) * .88;
        _rect(
          c,
          hx + perpX * 2.2,
          hy + perpY * 2.2,
          1,
          1,
          eyeCol,
          eyeAlpha,
        );
        _rect(
          c,
          hx - perpX * 2.2,
          hy - perpY * 2.2,
          1,
          1,
          eyeCol,
          eyeAlpha,
        );
      }
    }
  }

  void _waterSurfaceAndRipples(ui.Canvas c, PondModel m, double motion) {
    // 1. Specular water surface shimmer lines constrained to the biome water basin
    for (var i = 30; i < 115; i++) {
      final d = _details[i];
      final y = m.basin.topY + d.y * (m.basin.bottomY - m.basin.topY);
      final left = m.basin.leftX(y);
      final right = m.basin.rightX(y);
      final wave = math.sin(m.time * .35 + d.w * 20) * motion;
      final a = (.055 + d.z * .085) * (1 + m.richness * .4);
      final shimmerColor = switch (m.biome) {
        'maple' || 'autumn_mist' => d.z > .55 ? 0xffffb380 : 0xff9ad8cb,
        'grotto' || 'crystal_grotto' => d.z > .55 ? 0xff7df4eb : 0xff9b92f0,
        'sanctuary' || 'jade_sanctuary' => d.z > .6 ? 0xffffd28a : 0xff8ed6c1,
        'alpine' => d.z > .6 ? 0xffffd3dc : 0xffa8e9f0,
        'lotus' => d.z > .55 ? 0xfff7c0d8 : 0xff9ae3d2,
        'firefly' => d.z > .55 ? 0xffeef29b : 0xff85d1cf,
        _ => d.z > .65 ? 0xffffc6ac : 0xffa0dbcc,
      };
      final w = 4.0 + d.z * 26.0;
      final x = (left + d.x * (right - left) + wave * 3.0)
          .clamp(left, math.max(left, right - w))
          .toDouble();
      _rect(
        c,
        x,
        y,
        w,
        1,
        shimmerColor,
        a,
      );
    }

    // 2. Composable Dual-Ring Expanding Water Ripples (INTERACTION_STYLEGUIDE §2)
    //    Outer bright specular crest + inner dark refraction trough ring
    final crestColor = switch (m.biome) {
      'grotto' || 'crystal_grotto' => 0xff9ef7f0,
      'maple' || 'autumn_mist' || 'sanctuary' || 'jade_sanctuary' => 0xffffe5ba,
      'lotus' => 0xfffce2ed,
      _ => 0xffd0f5ee,
    };
    for (final r in m.ripples) {
      final p = r.progress;
      final fade = (1.0 - p) * (1.0 - p) * r.intensity;
      if (fade <= 0.02) continue;
      final rx = r.currentRadius;
      final ry = math.max(1.5, rx * .31);
      final cx = r.x + r.biasX * p;
      final cy = r.y;

      // Inner refraction shadow trough ring
      if (rx > 4) {
        _ovalRing(c, cx, cy + 1, rx - 1.5, ry - .5, 0xff0a2834, fade * .36);
      }
      // Primary specular crest ring
      _ovalRing(c, cx, cy, rx, ry, crestColor, fade * .58);
      // Secondary trailing harmonic ring on stronger impacts
      if (r.intensity > .55 && rx > 12) {
        _ovalRing(
          c,
          cx - r.biasX * p * .35,
          cy,
          rx * .68,
          ry * .68,
          crestColor,
          fade * .34,
        );
      }
    }
  }

  void _pad(
    ui.Canvas c,
    PadState pad,
    double x,
    double y,
    double t,
    double motion,
    String biome,
  ) {
    final bob = math.sin(t * .7) * .8 * motion;
    final px = x + pad.driftX;
    final py = y + bob + pad.dipY;
    final rx = pad.radiusX;
    final minRy = math.min(pad.radiusY, math.max(2.2, pad.radiusY * .72));
    final maxRy = math.max(minRy, pad.radiusY + .5);
    final ry = (pad.radiusY - pad.dipY.abs() * .18).clamp(minRy, maxRy);
    final scaleRatio = (rx / 35.0).clamp(0.32, 1.15);
    final tilt = pad.tiltAngle;
    final fold = pad.edgeFold;
    final foldSide = pad.edgeFoldSide;

    final isGrotto = biome == 'grotto' || biome == 'crystal_grotto';
    final isMaple = biome == 'maple' || biome == 'autumn_mist';
    final padMid = isGrotto
        ? 0xff288588
        : isMaple
        ? 0xff3b785f
        : 0xff32776a;
    final padLight = isGrotto
        ? 0xff49b0a8
        : isMaple
        ? 0xff5ca177
        : 0xff49947a;
    final veinColor = isGrotto ? 0xff92efe3 : 0xffb7cd86;

    // 1. Subsurface pad shadow (expands slightly when pad dips into water)
    _oval(
      c,
      px,
      py + 4 * scaleRatio - pad.dipY * .3,
      rx + 4 * scaleRatio + pad.dipY.clamp(0, 4) * .6,
      ry + 1,
      0xff092d3d,
      .44,
    );

    // 2. Reddish-plum underside reveal when opposite rim lifts during tilt or edge fold
    final rimLift = (rx * math.sin(tilt.abs()) + fold * 3.0);
    if (rimLift > 0.5) {
      final liftedSide = tilt >= 0 ? -1.0 : 1.0;
      _oval(
        c,
        px + liftedSide * 2.2 * scaleRatio,
        py + 2.0 * scaleRatio,
        rx - 1,
        ry,
        0xff6b3a50,
        (rimLift / 3.5).clamp(0.35, 0.92),
      );
    }

    // 3. Dark teal outer rim & main emerald leaf body (compressed on folded edge)
    final foldCompressX = fold * 2.8 * scaleRatio;
    final bodyCenterX = px - foldSide * foldCompressX * .5;
    final bodyRx = math.max(3.5, rx - foldCompressX * .5);
    _oval(c, bodyCenterX, py + 1.5 * scaleRatio, bodyRx, ry, 0xff143e3a);
    _oval(c, bodyCenterX, py, bodyRx, ry, padMid);
    if (bodyRx > 6 && ry > 3.2) {
      _oval(
        c,
        bodyCenterX - 2.5 * scaleRatio,
        py - 1.5 * scaleRatio + tilt * 3 * scaleRatio,
        bodyRx - 3.5 * scaleRatio,
        math.max(1.5, ry - 1.8 * scaleRatio),
        padLight,
      );
    }

    // 4. Center water-cup depression when frog lands in Zone A (center)
    if (pad.dipY > 1.0 && fold < 0.35) {
      final cupAlpha = ((pad.dipY - 1.0) / 3.5).clamp(0.0, 0.55);
      _oval(c, bodyCenterX, py - 1, bodyRx * .48, ry * .48, 0xff215c58, cupAlpha);
    }

    // 5. Radial leaf veins & V-notch
    if (scaleRatio > 0.55) {
      _line(
        c,
        bodyCenterX - bodyRx + 5 * scaleRatio,
        py - 3 * scaleRatio,
        bodyCenterX - 6 * scaleRatio,
        py - ry + 1,
        0xff90bc84,
        .8,
      );
      for (var i = -3; i <= 3; i++) {
        _line(
          c,
          bodyCenterX,
          py + 1,
          bodyCenterX + i * bodyRx * .26,
          py - ry + 3 * scaleRatio + i * tilt * 2.5,
          veinColor,
          .28,
        );
      }
    }
    _line(
      c,
      bodyCenterX,
      py + 1,
      bodyCenterX + bodyRx - 1,
      py + ry - 1.5 * scaleRatio,
      0xff153f42,
      1,
      scaleRatio > 0.65 ? 2 : 1,
    );
    if (scaleRatio > 0.5) {
      _line(
        c,
        bodyCenterX + 1,
        py + 2,
        bodyCenterX + bodyRx - 2,
        py + ry - 1,
        0xff67a47b,
      );
      _rect(
        c,
        bodyCenterX - bodyRx + 7 * scaleRatio,
        py + 1.5 * scaleRatio,
        7 * scaleRatio,
        1,
        0xff94c195,
        .65,
      );
    }

    // 6. Edge-Fold Deformation & Water-Wash Tongue (Zone C Edge Landing)
    if (fold > 0.05) {
      final lobeX = px + foldSide * (rx * .62);
      final lobeY = py + 1.5 + fold * 2.5;
      // Curled leaf rim dipping down into the pond
      _oval(
        c,
        lobeX,
        lobeY,
        rx * .34,
        ry * (.65 - fold * .18),
        0xff1f5954,
        (fold * .95).clamp(0.0, 1.0),
      );
      // Translucent water tongue washing over the submerged leaf edge
      _oval(
        c,
        lobeX + foldSide * 3,
        lobeY + 1,
        rx * .32,
        ry * .52,
        0xff85d4cb,
        pad.waterWashAlpha,
      );
      // Frothy white-cyan splash crescent along the folded lip
      _ovalRing(
        c,
        lobeX + foldSide * 4,
        lobeY + 1,
        rx * .35,
        ry * .55,
        0xffdffaf5,
        (fold * .82).clamp(0.0, 1.0),
      );
    }

    // 7. Bouncing surface dewdrop bead on the pad
    if (scaleRatio > 0.48) {
      final dropX = bodyCenterX - (pad.index % 2) * 6 * scaleRatio + 3 * scaleRatio;
      final dropY = py - 1.5 * scaleRatio - pad.dewdropBounce.abs() * 1.4;
      _rect(c, dropX, dropY, 2, 2, 0xffb8efe6, .78);
      _rect(c, dropX, dropY, 1, 1, 0xffffffff, .9);
    }

    // 8. Companion floating water lotus bloom beside pad 0 or lotus-bearing ambient pads
    if (pad.index == 0 || pad.hasLotus) {
      final bScale = pad.isAmbient ? (scaleRatio * 1.15).clamp(0.55, 0.95) : 1.0;
      final lx = px - rx - 8 * bScale + math.sin(t * .5) * 1.2 * motion;
      final ly = py + 4 * bScale + pad.dipY * .35;
      _oval(c, lx, ly + 2 * bScale, 8 * bScale, 3 * bScale, 0xff1f5750, .85);
      _oval(c, lx - 3 * bScale, ly, 4 * bScale, 2 * bScale, 0xffe69cb8, .92);
      _oval(c, lx + 3 * bScale, ly, 4 * bScale, 2 * bScale, 0xffe69cb8, .92);
      _oval(c, lx, ly - 1 * bScale, 4 * bScale, 3 * bScale, 0xfffad2e1, .95);
      _rect(c, lx - 1, ly - 1, 2, 2, 0xffffd966, .95);
    }
  }

  void _splashDroplets(ui.Canvas c, PondModel m) {
    for (final d in m.splashDroplets) {
      final life = (1.0 - d.age / d.maxAge).clamp(0.0, 1.0);
      _rect(c, d.x, d.y, 2, 2, 0xffe0faf5, life * .9);
      _rect(c, d.x, d.y, 1, 1, 0xffffffff, life);
    }
  }

  void _motifs(ui.Canvas c, PondModel m, double motion, double night) {
    if (m.biome == 'sanctuary' || m.biome == 'jade_sanctuary') {
      final flicker = reducedMotion
          ? .85
          : .75 + .25 * math.sin(m.time * 4.3) * math.cos(m.time * 2.7);
      final glowAlpha = (.18 + night * .35 + m.richness * .2) * flicker;
      final glowCol = m.biome == 'jade_sanctuary' ? 0xff7ef5c4 : 0xffffb85c;
      final coreCol = m.biome == 'jade_sanctuary' ? 0xffdfffe8 : 0xffffefc2;
      _oval(c, 114, 168, 12, 9, glowCol, glowAlpha * .45);
      _oval(c, 114, 168, 5, 4, coreCol, glowAlpha * .85);
      for (var i = 0; i < 7; i++) {
        final sway = math.sin(m.time * 1.4 + i) * 2.5 * motion;
        _rect(
          c,
          104 + sway + (i % 2) * 3,
          252 + i * 6.0,
          16 - i * 1.6,
          2,
          glowCol,
          glowAlpha * (.55 - i * .06),
        );
      }
    } else if (m.biome == 'grotto' || m.biome == 'crystal_grotto') {
      for (var i = 0; i < 18; i++) {
        final d = _details[165 + i];
        final pulse = reducedMotion
            ? .75
            : .5 + .5 * math.sin(m.time * 1.3 + d.w * 12);
        final sideX = i.isEven ? 24 + d.x * 135 : _width - 24 - d.x * 135;
        final sy =
            210 + d.y * 120 - (reducedMotion ? 0 : (m.time * 4 + i * 9) % 28);
        final color = i % 3 == 0
            ? 0xff5ef2e8
            : i % 3 == 1
            ? 0xffc68cff
            : 0xffffca7a;
        _oval(c, sideX, sy, 3, 2, color, pulse * (.14 + m.richness * .18));
        _rect(c, sideX, sy, 1, 1, 0xffffffff, pulse * (.45 + night * .35));
      }
    } else if (m.biome == 'maple' ||
        m.biome == 'autumn_mist' ||
        m.biome == 'blossom' ||
        m.biome == 'lotus') {
      final isMaple = m.biome == 'maple' || m.biome == 'autumn_mist';
      for (var i = 0; i < 16; i++) {
        final d = _details[170 + i];
        final driftX =
            (d.x * _width +
                (reducedMotion
                    ? 0
                    : m.time * (isMaple ? 3.5 : 5.2) +
                          math.sin(m.time * .7 + i) * 8)) %
            _width;
        final driftY = 185 + d.y * 155 + math.cos(m.time * .9 + i) * 2 * motion;
        final color = isMaple
            ? (i % 3 == 0
                  ? 0xffe2523a
                  : i % 3 == 1
                  ? 0xfff08c3b
                  : 0xffe6b84c)
            : (i.isEven ? 0xfff7bfd4 : 0xffffdfe9);
        _rect(c, driftX, driftY, isMaple ? 4 : 3, 2, color, .55 + d.z * .3);
        _rect(c, driftX + 1, driftY - 1, 2, 1, color, .4);
      }
    } else if (m.biome == 'cypress' || m.biome == 'firefly') {
      for (var i = 0; i < 14; i++) {
        final d = _details[185 + i];
        final x = i.isEven ? 20 + d.x * 150 : _width - 20 - d.x * 150;
        final len = 14 + d.z * 26;
        final sway = math.sin(m.time * .55 + i) * 2.5 * motion;
        _line(c, x, 4 + d.y * 28, x + sway, 4 + d.y * 28 + len, 0xff5a7a6e, .5);
      }
    }
  }

  void _foliage(ui.Canvas c, PondModel m, double motion, bool hasImage) {
    final blossom = m.biome == 'blossom' ||
        m.biome == 'sanctuary' ||
        m.biome == 'lotus';
    final maple = m.biome == 'maple' || m.biome == 'autumn_mist';
    final grotto = m.biome == 'grotto' || m.biome == 'crystal_grotto';
    for (var i = 100; i < 126; i++) {
      final d = _details[i];
      final right = i.isEven;
      final x = right ? _width - 8 - d.x * 58 : 8 + d.x * 58;
      final y = 322 + d.y * 34;
      final h = 11 + d.z * 28;
      final sway =
          (math.sin(m.time * .65 + d.w * 7) + (m.wind * 3 + m.windTell * 4)) *
          motion;
      final stemColor = grotto ? 0xff2f6d6f : 0xff426c59;
      _line(c, x, y, x + sway * 2 - 3, y - h, stemColor, .9);
      _line(c, x + 1, y, x + sway * 2 - 2, y - h + 4, 0xffa4b977, .45);
      if (i % 3 == 0) {
        _rect(c, x + sway * 2 - 4, y - h - 5, 3, 8, 0xff725c49);
        _rect(c, x + sway * 2 - 4, y - h - 5, 1, 6, 0xffc09968);
      } else if (i % 3 == 1) {
        final flowerColor = grotto
            ? 0xff6ef2ea
            : maple
            ? 0xffe86a45
            : blossom
            ? 0xfff0b9cd
            : 0xffc9b8df;
        _flower(c, x + sway * 2 - 3, y - h, flowerColor);
      }
    }
    if (!hasImage) {
      for (var side = 0; side < 2; side++) {
        for (var i = 0; i < 35; i++) {
          final d = _details[i + 130];
          final x = side == 0 ? d.x * 130 - 8 : _width + 8 - d.x * 130;
          final y = 330 + d.y * 28;
          _oval(c, x, y, 12 + d.z * 16, 5 + d.w * 8, 0xff173e40);
          _oval(c, x - 2, y - 3, 10 + d.z * 12, 3, 0xff416453);
          _rect(c, x - 3, y - 4, 5, 1, 0xffa7b775, .5);
        }
      }
      _flower(c, 92, 306, 0xffe6a7b8);
      _flower(c, 548, 294, 0xffe6a7b8);
    }
  }

  void _flower(ui.Canvas c, double x, double y, int color) {
    _rect(c, x - 3, y - 1, 7, 2, color);
    _rect(c, x - 1, y - 3, 3, 6, color);
    _rect(c, x, y - 1, 2, 2, 0xfff5d795);
    _rect(c, x - 2, y - 2, 1, 1, 0xffffe1d8, .8);
  }

  void _bug(ui.Canvas c, BugState b, PondModel m) {
    final x = b.x * _width;
    final y = b.y * _height;
    final wing = reducedMotion ? 1.0 : math.sin(b.phase * 3).abs() * 2 + 1;
    final a = b.opacity;
    if (b.species == 'firefly') {
      _oval(c, x, y, 6, 6, 0xffe5e9a0, a * .09);
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
        a * .75,
      );
      _rect(c, x, y - 1, 1, dragon ? 5 : 2, 0xffb7ba86, a);
      _rect(c, x, y - 1, 1, 1, 0xff243d47, a);
    }
  }

  void _weather(ui.Canvas c, PondModel m, double motion) {
    if (m.windTell > .05) {
      final direction = m.wind < 0 ? -1.0 : 1.0;
      for (var i = 0; i < 12; i++) {
        final d = _details[130 + i];
        final x = ((d.x + direction * m.time * .025) % 1) * _width;
        final y = 195 + d.y * 45 + math.sin(m.time + i) * 2;
        _line(
          c,
          x,
          y,
          x + direction * (5 + m.windTell * 9),
          y,
          0xffdfdbb2,
          m.windTell * .45,
        );
      }
    }
    final rain = m.weather == 'drizzle' || m.weather == 'storm';
    if (m.weather == 'mist' || m.weather == 'storm' || m.biome == 'autumn_mist') {
      for (var i = 0; i < 9; i++) {
        final d = _details[70 + i];
        final x = -70 + d.x * 380 + math.sin(m.time * .035 + i) * 24 * motion;
        _rect(
          c,
          x,
          135 + i * 11.0,
          240 + d.z * 180,
          3 + d.w * 6,
          0xffb7cdd0,
          m.weather == 'mist' || m.biome == 'autumn_mist' ? .055 : .035,
        );
      }
    }
    if (rain) {
      if (!reducedMotion && m.raindrops.isNotEmpty) {
        final windDx = m.wind * 2.4;
        for (final drop in m.raindrops) {
          if (drop.y < -8) continue;
          final endY = math.min(drop.y, drop.targetY);
          final startY = endY - drop.length;
          if (startY > drop.targetY) continue;
          _line(
            c,
            drop.x - windDx,
            startY,
            drop.x,
            endY,
            0xffc6e4e8,
            .32,
          );
          _rect(c, drop.x, endY, 1, 1, 0xffe8fafc, .52);
        }
      } else {
        for (var i = 0; i < 16; i++) {
          final d = _details[i];
          final y = (d.y * _height + m.time * 12) % _height;
          final x = (d.x * _width + m.wind * y * .08) % _width;
          _line(c, x, y, x - 1 - m.wind * 2, y + 4, 0xffb8d3d6, .18);
        }
      }
    }
    final night = (1 - m.daylight).clamp(0.0, 1.0);
    if (m.started && m.richness > .2 && night > 0) {
      for (var i = 0; i < 22; i++) {
        final d = _details[150 + i];
        final pulse = reducedMotion
            ? .7
            : .5 + .5 * math.sin(m.time * .9 + d.w * 20);
        final glow = pulse * m.richness * night * night;
        final x = d.x * _width + math.sin(m.time * .2 + i) * 4 * motion;
        final y = 175 + d.y * 155;
        _rect(c, x - 1, y - 1, 3, 3, 0xffdded9d, glow * .08);
        _rect(c, x, y, 1, 1, 0xfff1e9a5, glow * .8);
      }
    }
  }

  /// Releases only procedural caches, never the externally owned images.
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
