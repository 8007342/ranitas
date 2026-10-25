import 'dart:ui' as ui;

import 'package:flame/cache.dart';

/// Painted assets that may be supplied later (see `art/ASSET_REQUESTS.md`).
/// Every entry is optional: a missing or undecodable file yields `null` and the
/// renderer falls back to procedural art. Keep this list and the request
/// document in sync.
class OptionalAssets {
  OptionalAssets._();

  /// Filename stem for a biome id, e.g. `autumn_mist` -> `autumn-mist`.
  static String stem(String biome) => biome.replaceAll('_', '-');

  /// Backdrop stem from its asset name, e.g. `pond-blossom.webp` -> `pond-blossom`.
  static String backdropStem(String backdropAsset) =>
      backdropAsset.replaceAll('.webp', '');

  static String frogDepthSheet(int frogIndex) => frogIndex == 0
      ? 'frog-meadow-depth-sheet.webp'
      : 'frog-teal-depth-sheet.webp';
  static String canopy(String biome) => 'canopy-${stem(biome)}.webp';
  static String midBank(String biome) => 'midbank-${stem(biome)}.webp';
  static String foreground(String biome) => 'foreground-${stem(biome)}.webp';
  static String emissive(String backdropAsset) =>
      'emissive-${backdropStem(backdropAsset)}.webp';
  static String cycleIndex(String backdropAsset, String region) =>
      'cycle-${backdropStem(backdropAsset)}-$region.webp';

  /// Loads [name] from the Flame image cache, or returns `null` when the file
  /// is absent or fails to decode. Never throws.
  static Future<ui.Image?> load(Images images, String name) async {
    try {
      return await images.load(name);
    } catch (_) {
      return null;
    }
  }
}
