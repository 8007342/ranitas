import 'dart:ui';

import 'package:flame/game.dart';

import '../audio/ambience.dart';
import '../platform/scene_ready.dart';
import 'optional_assets.dart';
import 'palette_cycle.dart';
import 'pond_model.dart';
import 'pond_renderer.dart';

class RanitasGame extends FlameGame {
  RanitasGame({int? seed, double? durationOverride})
    : model = PondModel(seed: seed, durationOverride: durationOverride);
  final PondModel model;
  final PondRenderer renderer = PondRenderer();
  final PondAmbience ambience = PondAmbience();

  /// Baked palette-cycle frames for this session's backdrop; owned here.
  List<PaletteCycle> cycles = const [];
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
    renderer.frogDepthSheets = [
      await OptionalAssets.load(images, OptionalAssets.frogDepthSheet(0)),
      await OptionalAssets.load(images, OptionalAssets.frogDepthSheet(1)),
    ];
    renderer.wildlifeSheet = await images.load('pond-wildlife-sheet.webp');
    // Optional painted layers (art/ASSET_REQUESTS.md); null means procedural.
    final layers = renderer.layers;
    layers.canopyImage = await OptionalAssets.load(
      images,
      OptionalAssets.canopy(model.biome),
    );
    layers.midBankImage = await OptionalAssets.load(
      images,
      OptionalAssets.midBank(model.biome),
    );
    layers.foregroundImage =
        await OptionalAssets.load(
          images,
          OptionalAssets.foreground(model.biome),
        ) ??
        await images.load(model.foregroundAsset);
    cycles = await PaletteCycles.load(model.backdropAsset, images);
    renderer.cycles = cycles;
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
    for (final cycle in cycles) {
      cycle.dispose();
    }
    cycles = const [];
    ambience.dispose();
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // The corner foreground now draws inside the renderer's layer stack.
    renderer.render(canvas, Size(size.x, size.y), model);
  }
}
