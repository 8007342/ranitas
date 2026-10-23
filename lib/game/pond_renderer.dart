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

    // TIER 4: Floating Interactive Lily Pads, Lotus Blooms, Splash Droplets, Frogs & Bugs
    _pad(
      canvas,
      model.pads[0],
      _width * model.pads[0].x,
      _height * model.pads[0].y + 3 + model.leafNudge * 2,
      t,
      motion,
      model.biome,
    );
    _pad(
      canvas,
      model.pads[1],
      _width * model.pads[1].x,
      _height * model.pads[1].y + 3 - model.leafNudge * 2,
      t + 2,
      motion,
      model.biome,
    );
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
    // Dappled sub-surface caustic light ribbons and submerged lily stems
    for (var i = 0; i < 24; i++) {
      final d = _details[48 + i];
      final y = 198 + d.y * 145;
      final drift = math.sin(m.time * .28 + d.w * 14) * 5 * motion;
      final causticColor = m.biome == 'grotto' ? 0xff49c9c4 : 0xff5ca89f;
      _rect(
        c,
        75 + d.x * 490 + drift,
        y,
        6 + d.z * 18,
        1,
        causticColor,
        .045 + d.z * .04,
      );
    }
    for (final pad in m.pads) {
      final px = pad.x * _width + pad.driftX * .5;
      final py = pad.y * _height + 5 + pad.dipY * .5;
      final sway = math.sin(m.time * .6 + pad.index) * 2.5 * motion;
      _line(c, px, py, px + sway, py + 28, 0xff0d333b, .35, 2);
    }
  }

  void _subsurfaceWildlife(ui.Canvas c, PondModel m, double motion) {
    // 1. Darting pond tadpoles in deeper water
    final tadpoleAlpha = (.18 + m.richness * .22).clamp(0.18, 0.40);
    for (final tp in m.tadpoles) {
      final dirX = math.cos(tp.heading);
      final dirY = math.sin(tp.heading) * .6;
      final perpX = -dirY;
      final perpY = dirX;
      final wag = reducedMotion ? 0.0 : math.sin(tp.swimPhase) * 1.8;
      // Tadpole shadow on silt
      _oval(c, tp.x, tp.y + 4, 3, 1.5, 0xff061d26, tadpoleAlpha * .45);
      // Tadpole head & undulating tail
      _oval(c, tp.x, tp.y, 2.5, 1.8, 0xff193c45, tadpoleAlpha);
      _line(
        c,
        tp.x - dirX * 2,
        tp.y - dirY * 2,
        tp.x - dirX * 7 + perpX * wag,
        tp.y - dirY * 7 + perpY * wag,
        0xff27555e,
        tadpoleAlpha * .85,
      );
    }

    // 2. Ornamental Multi-Segment Koi Fish (Kohaku, Yamabuki, Showa, Asagi)
    //    Visible throughout the session with richness brightening their luster
    final baseKoiVisibility = (.38 + m.richness * .38).clamp(0.38, 0.76);
    for (final k in m.koi) {
      final depthFade = (1.0 - k.depth * .45).clamp(0.45, 0.92);
      final alpha = baseKoiVisibility * depthFade;
      final dirX = math.cos(k.heading);
      final dirY = math.sin(k.heading) * .55;
      final perpX = -dirY;
      final perpY = dirX;

      // Palette per Koi variety (blended with deep teal water tint)
      final (int bodyCol, int patch1, int patch2, int finCol) =
          switch (k.variant % 4) {
            0 => (0xffe8e2d3, 0xffd94832, 0xffe8684a, 0xfff0ebe1), // Kohaku
            1 => (0xffeab344, 0xffffdf7d, 0xffcf9129, 0xfff7dca0), // Yamabuki
            2 => (0xffe3ded2, 0xffcc392f, 0xff1e2d38, 0xffe6e0d5), // Showa
            _ => (0xff6794b0, 0xff94bfd9, 0xffe37349, 0xffeb8960), // Asagi
          };

      // Soft subsurface shadow on pond floor below Koi
      final shadowDepthOffset = 4.0 + k.depth * 6.0;
      _oval(
        c,
        k.x,
        k.y + shadowDepthOffset,
        12,
        4,
        0xff071d26,
        alpha * .32,
      );

      // Articulated 5-segment sinusoidal spine:
      // i=0 (head), i=1 (shoulders), i=2 (mid-body), i=3 (peduncle), i=4 (caudal tail)
      double segX(int i, double sOffset) {
        final wave = reducedMotion
            ? 0.0
            : (0.4 + 0.45 * i * i) * math.sin(k.swimPhase - i * 0.9);
        return k.x + dirX * sOffset + perpX * wave;
      }

      double segY(int i, double sOffset) {
        final wave = reducedMotion
            ? 0.0
            : (0.4 + 0.45 * i * i) * math.sin(k.swimPhase - i * 0.9);
        return k.y + dirY * sOffset + perpY * wave;
      }

      final hx = segX(0, 7);
      final hy = segY(0, 7);
      final sx = segX(1, 2);
      final sy = segY(1, 2);
      final mx = segX(2, -4);
      final my = segY(2, -4);
      final px = segX(3, -9);
      final py = segY(3, -9);
      final tx = segX(4, -14);
      final ty = segY(4, -14);

      // Swept pectoral fins flanking shoulders
      final finFlutter = reducedMotion
          ? 0.0
          : math.sin(k.swimPhase * 1.2) * 1.2;
      _oval(
        c,
        sx + perpX * (5.5 + finFlutter),
        sy + perpY * (5.5 + finFlutter),
        3.5,
        2.0,
        finCol,
        alpha * .52,
      );
      _oval(
        c,
        sx - perpX * (5.5 + finFlutter),
        sy - perpY * (5.5 + finFlutter),
        3.5,
        2.0,
        finCol,
        alpha * .52,
      );

      // Flowing forked caudal tail fin
      _line(
        c,
        px,
        py,
        tx + perpX * 3,
        ty + perpY * 3,
        finCol,
        alpha * .58,
        2,
      );
      _line(
        c,
        px,
        py,
        tx - perpX * 3,
        ty - perpY * 3,
        finCol,
        alpha * .58,
        2,
      );

      // Tapered body segments (tail base -> mid -> shoulders -> head)
      _oval(c, px, py, 3.0, 2.0, bodyCol, alpha * .82);
      _oval(c, mx, my, 5.0, 3.0, bodyCol, alpha * .88);
      _oval(c, mx, my, 3.5, 2.2, patch2, alpha * .82);
      _oval(c, sx, sy, 6.2, 3.6, bodyCol, alpha * .92);
      _oval(c, sx + dirX * 1.5, sy + dirY * 1.5, 4.2, 2.5, patch1, alpha * .9);
      _oval(c, hx, hy, 4.2, 2.6, bodyCol, alpha * .92);
      _oval(c, hx - dirX, hy - dirY, 2.5, 1.6, patch1, alpha * .85);

      // Subtle dorsal ridge & eyes
      _line(c, sx, sy - 1, mx, my - 1, finCol, alpha * .55);
      _rect(c, hx + dirX * 2, hy - 1, 1, 1, 0xff162d36, alpha * .85);
    }
  }

  void _waterSurfaceAndRipples(ui.Canvas c, PondModel m, double motion) {
    // 1. Specular water surface shimmer lines (composited OVER Koi & Tadpoles)
    for (var i = 30; i < 115; i++) {
      final d = _details[i];
      final y = 162 + d.y * 178;
      final wave = math.sin(m.time * .35 + d.w * 20) * motion;
      final a = (.055 + d.z * .085) * (1 + m.richness * .4);
      final shimmerColor = switch (m.biome) {
        'maple' => d.z > .55 ? 0xffffb380 : 0xff9ad8cb,
        'grotto' => d.z > .55 ? 0xff7df4eb : 0xff9b92f0,
        'sanctuary' => d.z > .6 ? 0xffffd28a : 0xff8ed6c1,
        'alpine' => d.z > .6 ? 0xffffd3dc : 0xffa8e9f0,
        _ => d.z > .65 ? 0xffffc6ac : 0xffa0dbcc,
      };
      _rect(
        c,
        d.x * _width + wave * 3,
        y,
        4 + d.z * 26,
        1,
        shimmerColor,
        a,
      );
    }

    // 2. Composable Dual-Ring Expanding Water Ripples (INTERACTION_STYLEGUIDE §2)
    //    Outer bright specular crest + inner dark refraction trough ring
    final crestColor = switch (m.biome) {
      'grotto' => 0xff9ef7f0,
      'maple' || 'sanctuary' => 0xffffe5ba,
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
    final ry = (pad.radiusY - pad.dipY.abs() * .18).clamp(8.5, 14.0);
    final tilt = pad.tiltAngle;
    final fold = pad.edgeFold;
    final foldSide = pad.edgeFoldSide;

    final padMid = biome == 'grotto'
        ? 0xff288588
        : biome == 'maple'
        ? 0xff3b785f
        : 0xff32776a;
    final padLight = biome == 'grotto'
        ? 0xff49b0a8
        : biome == 'maple'
        ? 0xff5ca177
        : 0xff49947a;
    final veinColor = biome == 'grotto' ? 0xff92efe3 : 0xffb7cd86;

    // 1. Subsurface pad shadow (expands slightly when pad dips into water)
    _oval(
      c,
      px,
      py + 5 - pad.dipY * .3,
      rx + 5 + pad.dipY.clamp(0, 4) * .6,
      ry + 1,
      0xff092d3d,
      .44,
    );

    // 2. Reddish-plum underside reveal when opposite rim lifts during tilt or edge fold
    final rimLift = (rx * math.sin(tilt.abs()) + fold * 3.0);
    if (rimLift > 0.6) {
      final liftedSide = tilt >= 0 ? -1.0 : 1.0;
      _oval(
        c,
        px + liftedSide * 2.5,
        py + 2.5,
        rx - 1,
        ry,
        0xff6b3a50,
        (rimLift / 3.5).clamp(0.35, 0.92),
      );
    }

    // 3. Dark teal outer rim & main emerald leaf body (compressed on folded edge)
    final foldCompressX = fold * 2.8;
    final bodyCenterX = px - foldSide * foldCompressX * .5;
    final bodyRx = rx - foldCompressX * .5;
    _oval(c, bodyCenterX, py + 2, bodyRx, ry, 0xff143e3a);
    _oval(c, bodyCenterX, py, bodyRx, ry, padMid);
    _oval(c, bodyCenterX - 3, py - 2 + tilt * 3, bodyRx - 4, ry - 2, padLight);

    // 4. Center water-cup depression when frog lands in Zone A (center)
    if (pad.dipY > 1.0 && fold < 0.35) {
      final cupAlpha = ((pad.dipY - 1.0) / 3.5).clamp(0.0, 0.55);
      _oval(c, bodyCenterX, py - 1, bodyRx * .48, ry * .48, 0xff215c58, cupAlpha);
    }

    // 5. Radial leaf veins & V-notch
    _line(
      c,
      bodyCenterX - bodyRx + 5,
      py - 3,
      bodyCenterX - 6,
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
        py - ry + 3 + i * tilt * 2.5,
        veinColor,
        .28,
      );
    }
    _line(
      c,
      bodyCenterX,
      py + 1,
      bodyCenterX + bodyRx - 1,
      py + ry - 2,
      0xff153f42,
      1,
      2,
    );
    _line(
      c,
      bodyCenterX + 1,
      py + 2,
      bodyCenterX + bodyRx - 2,
      py + ry - 1,
      0xff67a47b,
    );
    _rect(c, bodyCenterX - bodyRx + 8, py + 2, 8, 1, 0xff94c195, .65);

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
    final dropX = bodyCenterX - pad.index * 8 + 4;
    final dropY = py - 2 - pad.dewdropBounce.abs() * 1.4;
    _rect(c, dropX, dropY, 2, 2, 0xffb8efe6, .78);
    _rect(c, dropX, dropY, 1, 1, 0xffffffff, .9);

    // 8. Companion floating water lotus bloom beside pad 0
    if (pad.index == 0) {
      final lx = px - rx - 10 + math.sin(t * .5) * 1.2 * motion;
      final ly = py + 5 + pad.dipY * .35;
      _oval(c, lx, ly + 2, 8, 3, 0xff1f5750, .85);
      _oval(c, lx - 3, ly, 4, 2, 0xffe69cb8, .92);
      _oval(c, lx + 3, ly, 4, 2, 0xffe69cb8, .92);
      _oval(c, lx, ly - 1, 4, 3, 0xfffad2e1, .95);
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
    if (m.biome == 'sanctuary') {
      final flicker = reducedMotion
          ? .85
          : .75 + .25 * math.sin(m.time * 4.3) * math.cos(m.time * 2.7);
      final glowAlpha = (.18 + night * .35 + m.richness * .2) * flicker;
      _oval(c, 114, 168, 12, 9, 0xffffb85c, glowAlpha * .45);
      _oval(c, 114, 168, 5, 4, 0xffffefc2, glowAlpha * .85);
      for (var i = 0; i < 7; i++) {
        final sway = math.sin(m.time * 1.4 + i) * 2.5 * motion;
        _rect(
          c,
          104 + sway + (i % 2) * 3,
          252 + i * 6.0,
          16 - i * 1.6,
          2,
          0xffffbe66,
          glowAlpha * (.55 - i * .06),
        );
      }
    } else if (m.biome == 'grotto') {
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
    } else if (m.biome == 'maple' || m.biome == 'blossom') {
      final isMaple = m.biome == 'maple';
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
    } else if (m.biome == 'cypress') {
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
    final blossom = m.biome == 'blossom' || m.biome == 'sanctuary';
    final maple = m.biome == 'maple';
    final grotto = m.biome == 'grotto';
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
    if (m.weather == 'mist' || m.weather == 'storm') {
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
          m.weather == 'mist' ? .055 : .035,
        );
      }
    }
    if (rain) {
      final count = reducedMotion ? 16 : (m.weather == 'storm' ? 110 : 48);
      for (var i = 0; i < count; i++) {
        final d = _details[i];
        final rainSpeed =
            (reducedMotion ? 12 : 85) * (.1 + .9 * m.richness.clamp(0.0, 1.0));
        final y = (d.y * _height + m.time * rainSpeed) % _height;
        final x = (d.x * _width + m.wind * y * .08) % _width;
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
