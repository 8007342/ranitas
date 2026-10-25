import 'dart:math' as math;
import 'dart:ui' as ui;

import 'pond_model.dart';

/// Hybrid frog character renderer combining high-res 4×2 sprite sheet atlases
/// (`frog-meadow-sheet.webp` and `frog-teal-sheet.webp`) with discrete,
/// pixel-accurate micro-expressions and ground-plane jump shadow physics.
class FrogSprites {
  static const int _cols = 4;
  static const int _rows = 2;

  /// Water tone that far frogs haze toward (design D7).
  static const int _hazeTone = 0x2f5d66;

  /// Maps a pose name to its `(col, row)` cell in the 4×2 sprite sheet.
  static (int, int) _cellForPose(String pose) => switch (pose) {
    'idle' => (0, 0),
    'charging' => (1, 0),
    'landing' => (1, 0),
    'launching' => (2, 0),
    'ascending' => (3, 0),
    'chomping' => (0, 1),
    'falling' => (1, 1),
    'swallowing' => (2, 1),
    'sleeping' => (3, 1),
    _ => (0, 0),
  };

  /// Cell layout of the optional 4×2 depth sheet (`art/ASSET_REQUESTS.md` §1):
  /// row 0 is the back view, row 1 the front view.
  static (int, int) _depthCellForPose(String pose) => switch (pose) {
    'away_launch' => (0, 0),
    'away_ascend' => (1, 0),
    'away_fall' => (2, 0),
    'back_idle' => (3, 0),
    'toward_launch' => (0, 1),
    'toward_ascend' => (1, 1),
    'toward_fall' => (2, 1),
    'toward_chomp' => (3, 1),
    _ => (3, 0),
  };

  /// Draws a single frog at its logical canvas position on a `641 × 359` stage.
  /// The frog is scaled by the perspective at its ground point, hazed and faded
  /// with distance, and shows back/front poses on up/down-screen flights.
  static void renderFrog({
    required ui.Canvas canvas,
    required ui.Paint paint,
    required FrogState frog,
    required PondModel model,
    required double motion,
    required bool reducedMotion,
    ui.Image? sheet,
    ui.Image? depthSheet,
  }) {
    final activePad = model.pads[frog.leafIndex];
    final localPerchDx = (frog.x - activePad.x) * 641;
    final padBob =
        math.sin((model.time + (frog.leafIndex == 0 ? 0 : 2)) * .7) *
        .8 *
        motion;
    final padTiltDy = localPerchDx * math.sin(activePad.tiltAngle) * .38;
    final foldDrop =
        (!frog.airborne &&
            !frog.swimming &&
            localPerchDx * activePad.edgeFoldSide > activePad.radiusX * .38)
        ? activePad.edgeFold * 2.6
        : 0.0;
    final padDx = (!frog.airborne && !frog.swimming) ? activePad.driftX : 0.0;
    final padDy = (!frog.airborne && !frog.swimming)
        ? (padBob + activePad.floatY + activePad.dipY + padTiltDy + foldDrop)
        : 0.0;

    final x = (frog.x * 641 + padDx).roundToDouble();
    final y = (frog.y * 359 + padDy).roundToDouble();
    final sleeping = model.sleeping || frog.asleep;
    final charging =
        frog.index == 0 && model.pressing && !frog.airborne && !frog.swimming;
    final pose = frog.currentPose(charging: charging);
    final viewPose = frog.viewPose(pose);
    final depthView = viewPose != pose;

    // Continuous perspective at the ground point plus atmospheric depth cues.
    // The sprite itself is drawn at the nearest whole-pixel width (1/42 steps)
    // from an integer origin, so nearest-neighbour sampling of the soft cells
    // only changes when the width does, instead of shimmering every frame.
    final s = model.frogScale(frog);
    final sDraw = (s * 42).roundToDouble() / 42;
    final depth = model.basin.depthAt(frog.groundY * 359);
    final night = (1 - model.daylight).clamp(0.0, 1.0);
    final haze = ((1 - depth) * (.25 + .35 * night)).clamp(0.0, 1.0);
    final opacityScale = 1 - .25 * (1 - depth);
    final hazeColor = ui.Color(_hazeTone);

    // Palette for Frog 0 (Meadow Tree Frog) and Frog 1 (Teal Pond Frog)
    final outline = frog.index == 0 ? 0xff143534 : 0xff13303a;
    final dark = frog.index == 0 ? 0xff3d7a52 : 0xff2e6b72;
    final mid = frog.index == 0 ? 0xff6db364 : 0xff4ea69a;
    final light = frog.index == 0 ? 0xffa8db74 : 0xff89d6be;
    final belly = frog.index == 0 ? 0xfff4eec1 : 0xffefe8bd;
    final sacColor = frog.index == 0 ? 0xffe6d88a : 0xffbce6cf;
    final toeColor = frog.index == 0 ? 0xffee8468 : 0xffe29578;
    final cheekColor = frog.index == 0 ? 0xffe58f8e : 0xffd995a8;

    void rect(
      double rx,
      double ry,
      double rw,
      double rh,
      int color, [
      double opacity = 1,
    ]) {
      if (rw <= 0 || rh <= 0 || opacity <= 0) return;
      final hazed = haze > 0
          ? ui.Color.lerp(ui.Color(color), hazeColor, haze)!
          : ui.Color(color);
      paint.color = hazed.withValues(
        alpha: (opacity * opacityScale).clamp(0.0, 1.0),
      );
      canvas.drawRect(
        ui.Rect.fromLTWH(
          rx.roundToDouble(),
          ry.roundToDouble(),
          rw.ceilToDouble(),
          rh.ceilToDouble(),
        ),
        paint,
      );
    }

    void oval(
      double ox,
      double oy,
      double rx,
      double ry,
      int color, [
      double opacity = 1,
    ]) {
      for (var row = -ry.floor(); row <= ry.floor(); row++) {
        final span = rx * math.sqrt(math.max(0, 1 - row * row / (ry * ry)));
        rect(ox - span, oy + row, span * 2, 1, color, opacity);
      }
    }

    void line(
      double x0,
      double y0,
      double x1,
      double y1,
      int color, [
      double opacity = 1,
      double thickness = 1,
    ]) {
      final steps = math.max((x1 - x0).abs(), (y1 - y0).abs()).ceil();
      for (var i = 0; i <= steps; i++) {
        final p = steps == 0 ? 0.0 : i / steps;
        rect(
          x0 + (x1 - x0) * p,
          y0 + (y1 - y0) * p,
          thickness,
          thickness,
          color,
          opacity,
        );
      }
    }

    // 1. Water splash crown & ripples on belly flop or landing
    if (frog.bellyFlop > 0) {
      final spread = (1 - frog.bellyFlop) * 24;
      oval(x, y + 3, (14 + spread) * s, 4 * s, 0xffb0d8d0, frog.bellyFlop * .32);
      oval(x, y + 3, (9 + spread * .6) * s, 2 * s, 0xffe2f7f2, frog.bellyFlop * .45);
      for (var i = 0; i < 8; i++) {
        final side = i.isEven ? 1.0 : -1.0;
        final arc = math.sin((1 - frog.bellyFlop) * math.pi);
        rect(
          x + side * (5 + spread * .85 + i * 1.4) * s,
          y - (4 + arc * (10 + (i % 3) * 3)) * s,
          2,
          2,
          0xffd8f3ec,
          frog.bellyFlop * .85,
        );
      }
    } else if (frog.landingTimer > 0) {
      final p = 1 - (frog.landingTimer / .28).clamp(0.0, 1.0);
      oval(
        x,
        y + 4 * s,
        (15 + p * 12) * s,
        (3 + p * 2) * s,
        0xffa7dbd1,
        (1 - p) * .35,
      );
    }

    // 2. Ground-Plane Jump Shadow Projection (ANIMATION_STYLEGUIDE §1)
    if (frog.swimming) {
      final wake = reducedMotion ? 0.0 : math.sin(frog.swimAge * 10) * 1.5;
      oval(x - frog.facing * 5, y + 2, 16 + wake, 4, 0xff9ed2c4, .32);
      oval(x, y + 1, 11, 3, 0xffc8ebe1, .42);
    } else {
      // Shadow always projects onto the pond/lily-pad ground plane (groundY),
      // never floating in the air with frog.y.
      final groundY = frog.airborne ? (frog.groundY * 359).roundToDouble() : y;
      final altNorm = (frog.altitude / .41).clamp(0.0, 1.0);
      final overPad = model.pads.any(
        (p) => ((frog.x - p.x) * 641).abs() <= p.radiusX * .96,
      );
      // Shadows scale with the perspective of the ground point.
      final baseRx = (overPad ? 13.5 : 15.5) * s;
      final baseRy = (overPad ? 3.8 : 4.2) * s;
      final shadowRx = baseRx * (1.0 - .35 * altNorm);
      final shadowRy = baseRy * (1.0 - .25 * altNorm);
      final shadowColor = overPad ? outline : 0xff092d3d;
      final baseAlpha = overPad ? .34 : .22;
      final altFactor = (1.0 - altNorm * .75).clamp(0.25, 1.0);
      oval(
        x,
        groundY + 3 * s,
        shadowRx,
        shadowRy,
        shadowColor,
        baseAlpha * altFactor,
      );
    }

    // 3. Dynamic elastic tongue whip during mid-air chomp
    if (frog.tongue > 0) {
      final tx = frog.tongueX * 641;
      final ty = frog.tongueY * 359;
      final mx = x + frog.facing * 6 * s;
      final my = y - 12 * s;
      line(mx, my, tx, ty, 0xff9e3b56, .95, 3);
      line(mx, my - 1, tx, ty - 1, 0xfff08da1, 1, 2);
      oval(tx, ty, 3, 3, 0xffffb8c6, .95);
      rect(tx - 1, ty - 1, 2, 2, 0xffffeef2, .9);
    }

    // 4. Swimming state: dedicated submerged frog-kick animation
    if (frog.swimming) {
      final kick = reducedMotion ? 0.0 : math.sin(frog.swimAge * 14);
      final bob = reducedMotion ? 0.0 : math.cos(frog.swimAge * 7) * .8;
      canvas.save();
      canvas.translate(x, y + bob);
      canvas.scale(frog.facing * s, s);
      final legSpread = 4 + kick * 4;
      line(-6, 1, -15 - kick * 3, -legSpread, dark, .75, 2);
      line(-6, 2, -15 - kick * 3, legSpread, dark, .75, 2);
      rect(-18 - kick * 3, -legSpread - 1, 3, 3, toeColor, .75);
      rect(-18 - kick * 3, legSpread - 1, 3, 3, toeColor, .75);
      oval(-2, 0, 10, 4, dark, .7);
      oval(-1, -1, 8, 3, mid, .85);
      oval(4, -3, 7, 4, outline);
      oval(4, -4, 6, 3, mid);
      rect(2, -6, 6, 2, light);
      for (final ex in [2.0, 7.0]) {
        oval(ex, -7, 3, 3, outline);
        oval(ex, -7, 2, 2, 0xffffeaad);
        rect(ex, -8, 2, 2, outline);
        rect(ex, -8, 1, 1, 0xfffffff5);
      }
      line(4, 1, 9 + kick * 2, 3, mid, .85, 2);
      rect(-12, 2, 24, 1, 0xffbee8de, .65);
      canvas.restore();
      return;
    }

    // 5. Posture transforms (breathing, charge crouch, damped landing squash, discrete swallow nod)
    final breath = !frog.airborne && !frog.swimming
        ? math.sin(model.time * (sleeping ? 1.1 : 2.1) + frog.index * 1.3) *
              .6 *
              motion
        : 0.0;
    var scaleX = 1.0;
    var scaleY = 1.0;
    var offsetY = breath;

    if (charging) {
      final c = (model.holdDuration / .26).clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - c, 3).toDouble();
      scaleX = 1 + eased * .14;
      scaleY = 1 - eased * .20;
      offsetY += eased * 2.2;
    } else if (frog.landingTimer > 0) {
      final tLand = 1 - (frog.landingTimer / .28).clamp(0.0, 1.0);
      final damped = math.sin(tLand * math.pi * 2.2) * math.exp(-3.2 * tLand);
      scaleX = 1 + damped * .16;
      scaleY = 1 - damped * .18;
      offsetY += damped * 2.0;
    } else if (frog.swallowTimer > 0) {
      // Discrete, natural head-gulp nod (3.5% scale modulation, zero external balloon bulge)
      final p = 1 - (frog.swallowTimer / .88).clamp(0.0, 1.0);
      final gulp = math.sin(p * math.pi);
      scaleX = 1 + gulp * .035;
      scaleY = 1 - gulp * .030;
      offsetY -= gulp * 1.1;
    }

    canvas.save();
    canvas.translate(x, y + (offsetY * sDraw).roundToDouble());
    canvas.scale(frog.facing * scaleX * sDraw, scaleY * sDraw);

    void drawCell(ui.Image image, (int, int) cell) {
      final (col, row) = cell;
      final cellW = image.width / _cols;
      final cellH = image.height / _rows;
      final src = ui.Rect.fromLTWH(col * cellW, row * cellH, cellW, cellH);
      const dstW = 42.0;
      const dstH = 36.0;
      final dst = ui.Rect.fromLTWH(-dstW / 2, -dstH + 5, dstW, dstH);
      paint
        ..color = ui.Color.fromRGBO(255, 255, 255, opacityScale)
        ..colorFilter = haze > 0
            ? ui.ColorFilter.mode(
                hazeColor.withValues(alpha: haze),
                ui.BlendMode.srcATop,
              )
            : null
        ..filterQuality = ui.FilterQuality.none;
      canvas.drawImageRect(image, src, dst, paint);
      // The paint is shared with the rest of the renderer.
      paint
        ..colorFilter = null
        ..color = const ui.Color(0xffffffff);
    }

    if (depthView) {
      if (depthSheet != null) {
        drawCell(depthSheet, _depthCellForPose(viewPose));
      } else {
        _renderDepthPose(
          rect: rect,
          oval: oval,
          line: line,
          frog: frog,
          model: model,
          pose: viewPose,
          reducedMotion: reducedMotion,
          outline: outline,
          dark: dark,
          mid: mid,
          light: light,
          belly: belly,
          toeColor: toeColor,
          cheekColor: cheekColor,
        );
      }
    } else if (sheet != null) {
      drawCell(sheet, _cellForPose(pose));

      _renderSpriteMicroExpressions(
        rect: rect,
        oval: oval,
        frog: frog,
        model: model,
        pose: pose,
        sleeping: sleeping,
        reducedMotion: reducedMotion,
        outline: outline,
        mid: mid,
        sacColor: sacColor,
        cheekColor: cheekColor,
      );
    } else {
      _renderProceduralPose(
        rect: rect,
        oval: oval,
        line: line,
        frog: frog,
        model: model,
        pose: pose,
        sleeping: sleeping,
        reducedMotion: reducedMotion,
        outline: outline,
        dark: dark,
        mid: mid,
        light: light,
        belly: belly,
        sacColor: sacColor,
        toeColor: toeColor,
        cheekColor: cheekColor,
      );
    }
    canvas.restore();

    // 6. Discrete post-landing delight sparkle or nocturnal sleeping Zzzs
    if (frog.swallowTimer > 0 && !sleeping) {
      final p = 1 - (frog.swallowTimer / .88).clamp(0.0, 1.0);
      if (p >= .35 && p <= .92) {
        final sp = (p - .35) / .57;
        final a = math.sin(sp * math.pi) * .72;
        final mx = x + frog.facing * 10 * s;
        final my = y - (26 + sp * 5) * s;
        rect(mx, my - 1, 1, 3, 0xffffeaa6, a);
        rect(mx - 1, my, 3, 1, 0xffffeaa6, a);
        rect(mx, my, 1, 1, 0xffffffff, a);
      }
    }
    if (sleeping) {
      final rise = reducedMotion ? 0.0 : (model.time * .14 + frog.index * .4) % 1;
      final a = reducedMotion ? .5 : math.sin(rise * math.pi) * .72;
      final zx = x + 15 * s;
      final zy = y - (24 + rise * 11) * s;
      rect(zx, zy, 4, 1, 0xffe8e9c9, a);
      rect(zx + 2, zy + 1, 1, 1, 0xffe8e9c9, a);
      rect(zx + 1, zy + 2, 1, 1, 0xffe8e9c9, a);
      rect(zx, zy + 3, 4, 1, 0xffe8e9c9, a);
    }
  }

  static void _renderSpriteMicroExpressions({
    required void Function(double, double, double, double, int, [double]) rect,
    required void Function(double, double, double, double, int, [double]) oval,
    required FrogState frog,
    required PondModel model,
    required String pose,
    required bool sleeping,
    required bool reducedMotion,
    required int outline,
    required int mid,
    required int sacColor,
    required int cheekColor,
  }) {
    if (pose == 'idle' || pose == 'charging' || pose == 'landing') {
      // Discrete 1px internal under-chin vocal shimmer (strictly inside chin contour)
      final vocalWave = reducedMotion
          ? 0.0
          : math.max(
              0.0,
              math.sin(model.time * 2.4 + frog.index * 2.2) - .45,
            );
      if (vocalWave > 0 && !sleeping && pose == 'idle') {
        rect(1, -11, 3, 1, sacColor, vocalWave * .75);
        rect(2, -10, 2, 1, 0xfffff9d6, vocalWave * .55);
      }
      // Natural eye blink on idle/charging poses
      final blink =
          !reducedMotion && ((model.time + frog.index * 1.7) % 5.8) > 5.62;
      if (blink || sleeping) {
        final ey = pose == 'idle' ? -21.0 : -18.0;
        oval(0, ey, 4, 3, mid);
        rect(-3, ey, 6, 1, outline);
      }
    } else if (pose == 'swallowing') {
      // Discrete in-boundary swallow shimmer + contented happy eye squint (no protruding bulge)
      final p = 1 - (frog.swallowTimer / .88).clamp(0.0, 1.0);
      final gulpAlpha = math.sin(p * math.pi);
      // Contented squinting eye arc
      oval(0, -21, 3, 2, mid, .9);
      rect(-2, -21, 4, 1, outline, .9);
      // Subtle warm cheek blush
      rect(-4, -15, 2, 1, cheekColor, .45 + gulpAlpha * .35);
      // Tiny 2x1 internal throat highlight sliding down 2.5px inside chin contour
      final shimmerY = -12.0 + p * 2.5;
      rect(1, shimmerY, 2, 1, sacColor, gulpAlpha * .75);
      rect(2, shimmerY, 1, 1, 0xfffff9d6, gulpAlpha * .65);
      // Tiny vanishing wing tip at lip line at very start of swallow (p < 0.22)
      if (p < .22) {
        final wa = (1 - p / .22) * .75;
        rect(4, -16, 2, 1, 0xffd4e5de, wa);
      }
    }
  }

  static void _renderProceduralPose({
    required void Function(double, double, double, double, int, [double]) rect,
    required void Function(double, double, double, double, int, [double]) oval,
    required void Function(
      double,
      double,
      double,
      double,
      int, [
      double,
      double,
    ])
    line,
    required FrogState frog,
    required PondModel model,
    required String pose,
    required bool sleeping,
    required bool reducedMotion,
    required int outline,
    required int dark,
    required int mid,
    required int light,
    required int belly,
    required int sacColor,
    required int toeColor,
    required int cheekColor,
  }) {
    final airborne = frog.airborne;
    final stretch = pose == 'launching'
        ? 5.0
        : pose == 'ascending'
        ? 6.0
        : pose == 'chomping'
        ? 4.0
        : pose == 'falling'
        ? 3.0
        : 0.0;
    // Hind legs
    oval(-9 - stretch * .5, -3 + stretch * .4, 6, 5, outline);
    oval(9 + stretch * .4, -3 + stretch * .4, 6, 5, outline);
    oval(-9 - stretch * .5, -4 + stretch * .4, 5, 3, dark);
    oval(9 + stretch * .4, -4 + stretch * .4, 5, 3, mid);
    rect(-14 - stretch * .6, 0 + stretch * .6, 7, 2, toeColor);
    rect(7 + stretch * .5, 0 + stretch * .6, 7, 2, toeColor);
    // Torso & belly
    oval(0, -8, 12, 9, outline);
    oval(0, -9, 11, 8, mid);
    oval(-3, -10, 6, 4, light, .75);
    oval(1, -6, 7, 5, belly);
    // Head
    oval(1, -14, 12, 7, outline);
    oval(1, -15, 11, 6, mid);
    rect(-5, -19, 12, 2, light);
    // Discrete internal throat shimmer during swallow
    if (pose == 'swallowing') {
      final p = 1 - (frog.swallowTimer / .88).clamp(0.0, 1.0);
      rect(0, -11 + p * 2.0, 3, 1, sacColor, .85);
      rect(1, -11 + p * 2.0, 2, 1, 0xfffff9d6, .75);
    }
    // Chomping open mouth
    if (pose == 'chomping') {
      oval(4, -12, 6, 4, outline);
      oval(4, -12, 5, 3, 0xff8f3247);
      oval(5, -11, 4, 2, 0xffe87a90);
    } else {
      rect(-3, -12, 9, 1, outline);
    }
    // Eyes
    for (final side in [-1.0, 1.0]) {
      final ex = side * 6 + 1;
      oval(ex, -20, 5, 5, outline);
      oval(ex, -20, 4, 4, 0xffffeaad);
      final blink =
          !reducedMotion && ((model.time + frog.index * 1.7) % 6.4) > 6.23;
      if (sleeping || blink || pose == 'swallowing') {
        rect(ex - 3, -20, 6, 1, outline);
      } else {
        rect(ex - 1, -22, 3, 4, outline);
        rect(ex - 1, -22, 2, 2, 0xfffffff0);
      }
      rect(side * 8, -14, 3, 2, cheekColor, .85);
      if (!airborne) {
        line(side * 6, -7, side * 7, 0, outline, 1, 2);
        rect(side * 7 - 2, 0, 5, 2, toeColor);
      } else {
        final armY = pose == 'ascending' ? -18.0 : -14.0;
        line(side * 7, -11, side * 12, armY, outline, 1, 2);
        rect(side * 12 - 2, armY - 1, 4, 2, toeColor);
      }
    }
  }
  /// Procedural back (`away_*`, `back_idle`) and front (`toward_*`) views in
  /// the same pixel-primitive style and palette as the side poses. Drawn in
  /// the frog's local space: feet on `y = 0`, facing right before mirroring.
  static void _renderDepthPose({
    required void Function(double, double, double, double, int, [double]) rect,
    required void Function(double, double, double, double, int, [double]) oval,
    required void Function(
      double,
      double,
      double,
      double,
      int, [
      double,
      double,
    ])
    line,
    required FrogState frog,
    required PondModel model,
    required String pose,
    required bool reducedMotion,
    required int outline,
    required int dark,
    required int mid,
    required int light,
    required int belly,
    required int toeColor,
    required int cheekColor,
  }) {
    final away = pose.startsWith('away') || pose == 'back_idle';
    final crouch =
        pose == 'away_launch' || pose == 'toward_launch' || pose == 'back_idle';
    final ascend = pose == 'away_ascend' || pose == 'toward_ascend';
    final spread = pose == 'away_fall' || pose == 'toward_fall';
    final chomp = pose == 'toward_chomp';
    // A crouch sits lower; ascent and fall lift the body off the baseline.
    final lift = crouch
        ? -2.0
        : ascend
        ? 3.0
        : 1.0;

    // Hind legs: coiled beside the body, trailing below, or spread wide.
    for (final side in [-1.0, 1.0]) {
      if (crouch) {
        oval(side * 10, -3 - lift, 6, 4, outline);
        oval(side * 10, -4 - lift, 5, 3, side < 0 ? dark : mid);
        rect(side * 13 - 2, 0, 5, 2, toeColor);
      } else if (ascend) {
        line(side * 6, -5, side * 8, 5, outline, 1, 3);
        line(side * 6, -5, side * 8, 4, side < 0 ? dark : mid, 1, 1);
        rect(side * 8 - 2, 5, 5, 2, toeColor);
      } else {
        line(side * 6, -5, side * 14, 1, outline, 1, 3);
        line(side * 6, -5, side * 13, 0, side < 0 ? dark : mid, 1, 1);
        rect(side * 14 - 2, 1, 5, 2, toeColor);
      }
    }

    // Torso: a plain back dome seen from behind, or the belly from the front.
    final bodyY = -8 - lift;
    oval(0, bodyY, 12, 9, outline);
    oval(0, bodyY - 1, 11, 8, mid);
    if (away) {
      oval(-2, bodyY - 2, 7, 4, light, .55);
      rect(-1, bodyY - 8, 2, 11, light, .6);
      rect(-4, bodyY + 2, 8, 1, dark, .55);
    } else {
      oval(0, bodyY + 1, 8, 6, belly);
      oval(0, bodyY + 2, 6, 4, 0xfffff8dc, .5);
    }

    // Head.
    final headY = -14 - lift;
    oval(0, headY, 12, 7, outline);
    oval(0, headY - 1, 11, 6, mid);
    if (away) {
      oval(0, headY - 2, 9, 4, dark, .45);
      rect(-5, headY - 5, 10, 2, light);
    } else {
      rect(-6, headY - 5, 12, 2, light);
      if (chomp) {
        oval(0, headY + 2, 6, 3, outline);
        oval(0, headY + 2, 5, 2, 0xff8f3247);
        rect(-1, headY + 2, 3, 2, 0xffe87a90);
      } else {
        rect(-5, headY + 2, 11, 1, outline);
      }
    }

    // Eyes: the back of the bulges from behind, both pupils from the front.
    final blink =
        !reducedMotion && ((model.time + frog.index * 1.7) % 6.4) > 6.23;
    for (final side in [-1.0, 1.0]) {
      final ex = side * 6;
      final ey = headY - 6;
      oval(ex, ey, 5, 5, outline);
      if (away) {
        oval(ex, ey, 4, 4, mid);
        rect(ex + side * 3, ey - 1, 1, 3, 0xffffeaad, .9);
      } else {
        oval(ex, ey, 4, 4, 0xffffeaad);
        if (blink) {
          rect(ex - 3, ey, 6, 1, outline);
        } else {
          rect(ex - 1, ey - 1, 3, 3, outline);
          rect(ex - 1, ey - 2, 1, 1, 0xfffffff0);
        }
        rect(side * 9 - 1, headY + 1, 2, 2, cheekColor, .85);
      }
    }

    // Arms: reaching ahead (mostly hidden behind the back) or toward the viewer.
    for (final side in [-1.0, 1.0]) {
      if (away) {
        final armY = ascend
            ? headY - 5
            : spread
            ? bodyY - 2
            : bodyY + 2;
        final armX = spread ? 14.0 : 10.0;
        line(side * 7, bodyY - 3, side * armX, armY, outline, 1, 2);
        rect(side * armX - 2, armY - 1, 4, 2, toeColor, ascend ? 1 : .8);
      } else {
        final armX = spread
            ? 14.0
            : ascend
            ? 12.0
            : 8.0;
        final armY = ascend
            ? headY - 3
            : spread
            ? bodyY - 2
            : bodyY + 5;
        line(side * 7, bodyY - 2, side * armX, armY, outline, 1, 2);
        rect(side * armX - 2, armY - 1, 5, 3, toeColor);
      }
    }
  }
}
