import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';

import '../audio/ambience.dart';
import '../platform/scene_ready.dart';
import 'pond_model.dart';
import 'pond_renderer.dart';

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
    final asset = model.biome == 'cypress'
        ? 'pond-mist.webp'
        : model.biome == 'blossom'
        ? 'pond-blossom.webp'
        : 'pond-dusk.webp';
    renderer.backdrop = await images.load(asset);
    foreground = await images.load('foreground-marsh.webp');
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
          model.weather,
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
    final night = 1 - model.daylight;
    final opacity = (model.richness - .12).clamp(0.0, 1.0) * .65;
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
        size.y * .32,
        size.x * 1.02,
        size.y * .68,
      ),
      Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..colorFilter = ColorFilter.mode(
          Color.lerp(
            const Color(0xffffffff),
            const Color(0xff41617c),
            night * .8,
          )!,
          BlendMode.modulate,
        ),
    );
    canvas.restore();
  }
}
