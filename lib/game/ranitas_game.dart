import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';

import '../audio/ambience.dart';
import '../platform/scene_ready.dart';
import 'optional_assets.dart';
import 'pond_model.dart';
import 'pond_renderer.dart';
import 'scene_grade.dart';

class RanitasGame extends FlameGame {
  RanitasGame({int? seed, double? durationOverride})
    : model = PondModel(seed: seed, durationOverride: durationOverride);
  final PondModel model;
  final PondRenderer renderer = PondRenderer();
  final PondAmbience ambience = PondAmbience();
  Image? foreground;
  double audioClock = 0;
  @override
  Color backgroundColor() => const Color(0xff102c36);
  @override
  Future<void> onLoad() async {
    renderer.backdrop = await images.load(model.backdropAsset);
    renderer.emissive = await OptionalAssets.load(
      images,
      OptionalAssets.emissive(model.backdropAsset),
    );
    renderer.frogSheets = [
      await images.load('frog-meadow-sheet.webp'),
      await images.load('frog-teal-sheet.webp'),
    ];
    renderer.wildlifeSheet = await images.load('pond-wildlife-sheet.webp');
    foreground = await images.load(model.foregroundAsset);
    sceneReady();
  }

  @override
  void update(double dt) {
    super.update(dt);
    model.update(dt.clamp(0, .05));
    audioClock += dt;
    if (audioClock > .2) {
      audioClock = 0;
      if (model.started) {
        ambience.update(
          model.progress,
          model.richness,
          model.audioWeather,
          model.sleeping,
        );
      }
    }
  }

  @override
  void onRemove() {
    renderer.dispose();
    ambience.dispose();
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    renderer.render(canvas, Size(size.x, size.y), model);
    final layer = foreground;
    if (layer == null) return;
    final opacity = (model.richness - .12).clamp(0.0, 1.0) * .68;
    final sway = renderer.reducedMotion
        ? 0.0
        : math.sin(model.time * .18) * size.x * .003 * model.richness;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y));
    canvas.drawImageRect(
      layer,
      Rect.fromLTWH(0, 0, layer.width.toDouble(), layer.height.toDouble()),
      Rect.fromLTWH(
        -size.x * .01 + sway,
        size.y * .14,
        size.x * 1.02,
        size.y * .86,
      ),
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        // Same continuous grade as the backdrop, so the near corner darkens
        // with the scene instead of a separate modulate tint.
        ..colorFilter = SceneGrade.filterFor(model),
    );
    canvas.restore();
  }
}
